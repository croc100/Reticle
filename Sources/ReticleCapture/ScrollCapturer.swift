import AppKit
import CoreGraphics
import ScreenCaptureKit

// MARK: - ScrollCapturer

/// Scrolling screenshot: moves the cursor into a window, repeatedly posts scroll-down
/// events, captures a frame after each step, then stitches unique strips into one tall image.
///
/// Requires:
///   - Screen Recording entitlement (for SCStream captures)
///   - Accessibility permission (`AXIsProcessTrusted()`) for posting CGEvents
public final class ScrollCapturer {

    // MARK: - Configuration

    /// How many lines to scroll per step.  Matches ShareX default (3 lines).
    public var scrollLines: Int32 = -3

    /// Delay (nanoseconds) after each scroll event before the next capture.
    public var settleDelay: UInt64 = 300_000_000   // 300 ms

    /// Maximum number of scroll steps (guard against infinite pages).
    public var maxSteps: Int = 60

    /// Number of consecutive steps with no new unique content before stopping.
    public var noProgressLimit: Int = 3

    // MARK: - Private state

    private let capturer = Capturer()

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Capture a full-scroll screenshot of `window`.
    ///
    /// - Parameters:
    ///   - window: The `SCWindow` to capture.  Its `frame` uses Quartz display
    ///             coordinates (top-left origin, y increases downward).
    ///   - scrollToTop: If `true`, sends a large scroll-up event first so that
    ///                  capture always starts from the top of the content.
    /// - Returns: A stitched `CGImage` containing all unique scroll content.
    public func capture(window: SCWindow, scrollToTop: Bool = true) async throws -> CGImage {

        // Place cursor in the window centre so scroll events reach it.
        let centre = CGPoint(x: window.frame.midX, y: window.frame.midY)
        CGDisplayMoveCursorToPoint(CGMainDisplayID(), centre)
        try await Task.sleep(nanoseconds: 150_000_000)   // 150 ms cursor settle

        // Optional: scroll all the way to the top before starting.
        if scrollToTop {
            postScroll(lines: 10_000)                    // very large positive = scroll up
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Capture initial frame.
        var frames: [CGImage] = []
        let first = try await capturer.capture(mode: .window(CGWindowID(window.windowID)))
        frames.append(first.image)

        var noProgressStreak = 0

        for _ in 0..<maxSteps {
            postScroll(lines: scrollLines)
            try await Task.sleep(nanoseconds: settleDelay)

            let shot = try await capturer.capture(mode: .window(CGWindowID(window.windowID)))
            guard let previous = frames.last else { break }
            let overlap = findOverlap(prev: previous, curr: shot.image)
            let newH    = shot.image.height - overlap

            if newH < 4 {
                noProgressStreak += 1
                if noProgressStreak >= noProgressLimit { break }
                continue
            }
            noProgressStreak = 0
            frames.append(shot.image)
        }

        return try stitch(frames)
    }

    // MARK: - CGEvent scroll

    private func postScroll(lines: Int32) {
        let src = CGEventSource(stateID: .hidSystemState)
        let evt = CGEvent(
            scrollWheelEvent2Source: src,
            units: .line,
            wheelCount: 1,
            wheel1: lines,
            wheel2: 0,
            wheel3: 0
        )
        evt?.post(tap: .cghidEventTap)
    }

    // MARK: - Overlap detection

    /// Returns the number of pixels at the **top** of `curr` (in CGImage space, y=0=top)
    /// that overlap with the **bottom** of `prev`.
    ///
    /// Algorithm:
    ///   1. Render the bottom `refH` rows of `prev` into a small bitmap context (refCtx).
    ///   2. Render a narrow vertical slab of `curr` into another bitmap context (slabCtx).
    ///   3. A `CGBitmapContext`'s buffer is stored **top-down**: byte row 0 is the
    ///      image's top row.  It has to be, because `makeImage()` hands that buffer
    ///      straight to a `CGImage`, and a `CGImage` always reads row 0 as the top.
    ///   4. Find the byte row `y` of the slab where the reference strip sits.
    ///      Matching there means `curr` row `y + k` holds `prev` row
    ///      `h - refH + k`, so the page moved by `h - refH - y` pixels and the
    ///      rows the two frames share number `refH + y`.
    ///
    /// Both frames must be the same size — they come from one window through one
    /// capture path.  A resize mid-scroll gives up and returns 0, which costs a
    /// duplicated strip rather than a silently wrong one.
    func findOverlap(prev: CGImage, curr: CGImage) -> Int {
        guard prev.width == curr.width, prev.height == curr.height else { return 0 }

        let w    = curr.width
        let h    = curr.height
        let refH = 32                           // reference strip height in pixels
        let sw   = min(w, 256)                  // sample column width
        let cx   = (w - sw) / 2                 // centre the sample column

        guard h > refH * 4 else { return 0 }

        // --- Reference: bottom `refH` rows of `prev` ---
        guard let prevCrop = prev.cropping(to: CGRect(x: cx,
                                                       y: prev.height - refH,
                                                       width: sw, height: refH)),
              let refCtx   = bitmapCtx(w: sw, h: refH)
        else { return 0 }
        refCtx.draw(prevCrop, in: CGRect(x: 0, y: 0, width: sw, height: refH))
        guard let refData = refCtx.data else { return 0 }
        let refBpr = refCtx.bytesPerRow

        // --- Slab: narrow vertical slice of `curr` ---
        guard let currCrop = curr.cropping(to: CGRect(x: cx, y: 0, width: sw, height: h)),
              let slabCtx  = bitmapCtx(w: sw, h: h)
        else { return 0 }
        slabCtx.draw(currCrop, in: CGRect(x: 0, y: 0, width: sw, height: h))
        guard let slabData = slabCtx.data else { return 0 }
        let slabBpr = slabCtx.bytesPerRow

        /// Whether the reference strip sits at byte row `y` of the slab.
        ///
        /// Every fourth pixel is sampled, and all three colour channels of it.
        /// Stepping a flat 16 bytes compared one channel only — blue, as it
        /// happens, since the context is `byteOrder32Little` — so any content
        /// with a uniform blue channel matched everywhere.
        func matches(at y: Int) -> Bool {
            for k in 0..<refH {
                let refOff  = k * refBpr
                let slabOff = (y + k) * slabBpr
                var col = 0
                while col < sw * 4 {
                    for channel in 0..<3 {
                        let a = refData.load(fromByteOffset: refOff + col + channel, as: UInt8.self)
                        let b = slabData.load(fromByteOffset: slabOff + col + channel, as: UInt8.self)
                        if abs(Int(a) - Int(b)) > 10 { return false }
                    }
                    col += 16       // sample every 4 pixels
                }
            }
            return true
        }

        // The no-scroll case first.  It is the one the caller leans on to know
        // when to stop, and an ascending scan can match a flat region higher up
        // and report a smaller overlap — which reads as progress that is not
        // there, so the scroll runs to `maxSteps` stitching duplicates.
        if matches(at: h - refH) { return h }

        // Otherwise the lowest matching row wins, i.e. the smallest overlap.
        // A false positive then duplicates a strip instead of dropping one.
        for y in 0..<(h - refH) where matches(at: y) {
            return refH + y
        }
        return 0
    }

    // MARK: - Stitching

    /// Stitch captured frames into one tall image.
    ///
    /// Frame 0 contributes its full height.  Each subsequent frame contributes
    /// only the unique bottom strip (rows `overlap..<h` in CGImage space).
    ///
    /// Not private so the tests can drive it with synthetic frames: everything
    /// here is arithmetic over coordinate spaces, which is exactly the part
    /// that was wrong and exactly the part that needs no screen to check.
    func stitch(_ frames: [CGImage]) throws -> CGImage {
        guard !frames.isEmpty else { throw ScrollCaptureError.noFrames }
        guard frames.count > 1 else { return frames[0] }

        // The narrowest frame, not the first one's width: a window resized
        // mid-scroll makes `cropping(to:)` return nil for a width the frame
        // does not have, and the strip was then dropped without a word.
        guard let w = frames.map(\.width).min(), w > 0 else {
            throw ScrollCaptureError.noFrames
        }

        struct Strip { let img: CGImage; let h: Int }
        var strips: [Strip] = []

        for (index, frame) in frames.enumerated() {
            // Frame 0 keeps all of itself; the rest keep what is new.
            let overlap = index == 0 ? 0 : findOverlap(prev: frames[index - 1], curr: frame)
            let newH    = frame.height - overlap
            guard newH > 0 else { continue }
            // Crop rows [overlap..<frame.height] in CGImage space = unique bottom strip.
            guard let cropped = frame.cropping(
                to: CGRect(x: 0, y: overlap, width: w, height: newH)) else { continue }
            strips.append(Strip(img: cropped, h: newH))
        }

        guard !strips.isEmpty else { throw ScrollCaptureError.noFrames }

        let totalH = strips.reduce(0) { $0 + $1.h }
        guard let ctx = bitmapCtx(w: w, h: totalH) else { throw ScrollCaptureError.contextFailed }

        // No CTM flip.  Flipping the context flips the *content* of every image
        // drawn into it, so each strip came out mirrored top-to-bottom — right
        // order, upside-down contents.  Every other bitmap draw in this project
        // leaves the CTM alone; this was the one that did not.
        //
        // So place the strips from the top down in a y-up context instead: the
        // first strip, which is the top of the page, sits highest.
        var top = totalH
        for strip in strips {
            top -= strip.h
            ctx.draw(strip.img, in: CGRect(x: 0, y: top, width: w, height: strip.h))
        }

        guard let result = ctx.makeImage() else { throw ScrollCaptureError.contextFailed }
        return result
    }

    // MARK: - Helpers

    private func bitmapCtx(w: Int, h: Int) -> CGContext? {
        CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                      | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}

// MARK: - Error

public enum ScrollCaptureError: LocalizedError {
    case noFrames
    case contextFailed

    public var errorDescription: String? {
        switch self {
        case .noFrames:      return "No frames were captured during scroll."
        case .contextFailed: return "Failed to create graphics context for stitching."
        }
    }
}
