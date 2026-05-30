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
            let overlap = findOverlap(prev: frames.last!, curr: shot.image)
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
    ///   3. Both contexts store rows bottom-up (CGContext y=0 = bottom of image).
    ///      The reference corresponds to slab memory position `slab_start = D` where D
    ///      is the scroll distance in pixels.
    ///   4. Scan slab from y=1 upward; first match gives overlap = h - y.
    ///
    func findOverlap(prev: CGImage, curr: CGImage) -> Int {
        let w    = min(prev.width, curr.width)
        let h    = min(prev.height, curr.height)
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

        // --- Scan slab (y=1 → y=h-refH) looking for reference strip ---
        //
        // CGContext memory layout: byte row 0 = bottom of image, row (h-1) = top.
        // At memory position y in slab: content matches prev bottom when y == D (scroll dist).
        // → overlap = h - y.
        //
        for y in 1...(h - refH) {
            var ok = true
            outer: for k in 0..<refH {
                let refOff  = k * refBpr
                let slabOff = (y + k) * slabBpr
                var col = 0
                while col < sw * 4 {
                    let a = refData.load(fromByteOffset: refOff + col, as: UInt8.self)
                    let b = slabData.load(fromByteOffset: slabOff + col, as: UInt8.self)
                    if abs(Int(a) - Int(b)) > 10 { ok = false; break outer }
                    col += 16       // sample every 4 pixels
                }
            }
            if ok { return h - y }
        }
        return 0
    }

    // MARK: - Stitching

    /// Stitch captured frames into one tall image.
    ///
    /// Frame 0 contributes its full height.  Each subsequent frame contributes
    /// only the unique bottom strip (rows `overlap..<h` in CGImage space).
    private func stitch(_ frames: [CGImage]) throws -> CGImage {
        guard !frames.isEmpty else { throw ScrollCaptureError.noFrames }
        guard frames.count > 1 else { return frames[0] }

        let w = frames[0].width

        // Compute unique strip for each frame after the first.
        struct Strip { let img: CGImage; let h: Int }
        var strips: [Strip] = [Strip(img: frames[0], h: frames[0].height)]

        for i in 1..<frames.count {
            let overlap = findOverlap(prev: frames[i - 1], curr: frames[i])
            let newH    = frames[i].height - overlap
            guard newH > 0 else { continue }
            // Crop rows [overlap..<frames[i].height] in CGImage space = unique bottom strip.
            if let cropped = frames[i].cropping(to: CGRect(x: 0, y: overlap, width: w, height: newH)) {
                strips.append(Strip(img: cropped, h: newH))
            }
        }

        let totalH = strips.reduce(0) { $0 + $1.h }
        guard let ctx = bitmapCtx(w: w, h: totalH) else { throw ScrollCaptureError.contextFailed }

        // Flip the context so y=0 is at the top (screen orientation).
        ctx.translateBy(x: 0, y: CGFloat(totalH))
        ctx.scaleBy(x: 1, y: -1)

        var y = 0
        for strip in strips {
            ctx.draw(strip.img, in: CGRect(x: 0, y: y, width: w, height: strip.h))
            y += strip.h
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
