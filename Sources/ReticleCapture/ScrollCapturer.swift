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

    // MARK: - Matching constants

    /// Rows that have to match before an alignment is believed.
    ///
    /// The old matcher used a fixed 32-row reference and took the first row it
    /// matched at.  On repetitive content — a table, a list, indented code —
    /// the first match is not necessarily the right one, so the search now
    /// keeps the alignment with the *longest* run of matching rows and this is
    /// the floor below which a run is not evidence of anything.
    private static let minimumRun = 16

    /// Narrowest side margin kept out of the comparison, in pixels.
    ///
    /// A scrollbar lives on one edge and redraws as the page moves; window
    /// chrome and shadows sit on the other.  Comparing them compares things
    /// that change for reasons that have nothing to do with scrolling.
    private static let minimumSideMargin = 50

    /// Widest column compared.  Sampling is cheap but not free, and a wider
    /// column says no more about vertical position than a narrow one.
    private static let maximumSampleWidth = 256

    /// Per-channel slack when two pixels are compared.
    private static let tolerance = 10

    /// The most of a frame, as a fraction denominator, that may be written off
    /// as not scrolling.  A third, so two thirds always remain to match on.
    private static let stickyLimitDivisor = 3

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
        var alignments: [FrameAlignment] = []
        let first = try await capturer.capture(mode: .window(CGWindowID(window.windowID)))
        frames.append(first.image)

        var noProgressStreak = 0

        for _ in 0..<maxSteps {
            postScroll(lines: scrollLines)
            try await Task.sleep(nanoseconds: settleDelay)

            let shot = try await capturer.capture(mode: .window(CGWindowID(window.windowID)))
            guard let previous = frames.last else { break }

            // An alignment that cannot be found at all counts as no progress
            // rather than as a reason to stop outright: one bad frame, mid
            // animation or mid lazy-load, should not end the capture.
            let alignment = align(prev: previous, curr: shot.image)
            guard let alignment, alignment.scrolled >= 4 else {
                noProgressStreak += 1
                if noProgressStreak >= noProgressLimit { break }
                continue
            }

            noProgressStreak = 0
            frames.append(shot.image)
            alignments.append(alignment)
        }

        return try stitch(frames, alignments: alignments)
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

    // MARK: - Frame alignment

    /// What one frame shares with the frame before it.
    public struct FrameAlignment: Equatable, Sendable {
        /// Rows at the top of both frames that did not move: a sticky header.
        public let stickyTop: Int
        /// Rows at the bottom of both frames that did not move: a sticky
        /// footer, a toolbar, a floating button, a status bar.
        public let stickyBottom: Int
        /// Height of what lies between them — the part that actually scrolls.
        public let scrollingHeight: Int
        /// Rows of that part the two frames have in common.  Equal to
        /// ``scrollingHeight`` when the page did not move at all.
        public let overlap: Int

        /// How far the page moved, in pixels.
        public var scrolled: Int { scrollingHeight - overlap }
    }

    /// Works out what `curr` shares with `prev`, or nil when it cannot tell.
    ///
    /// Three things are established, in this order:
    ///
    /// 1. **The bands that do not scroll.** Rows identical in both frames *at
    ///    the same position* did not move.  On the modern web that is a sticky
    ///    header or footer, and leaving them in the comparison wrecks it: a
    ///    footer pinned to the bottom of every frame matches itself at every
    ///    candidate alignment, so the overlap comes back enormous and the
    ///    capture decides the page never moved.  Both ends are measured, not
    ///    just the bottom — sticky headers are at least as common as sticky
    ///    footers.
    /// 2. **Where the previous frame's content now sits**, searched over what
    ///    is left in between.
    /// 3. **How far that is**, which is what the caller needs.
    ///
    /// Over-measuring a sticky band is safe: it narrows the window the search
    /// runs in, but ``stitch(_:alignments:)`` reconstructs the same pixels for
    /// any band width, because the band cancels out of the arithmetic.
    /// Under-measuring is the one that hurts, which is why both ends are
    /// grown as far as the content allows.
    func align(prev: CGImage, curr: CGImage) -> FrameAlignment? {
        guard prev.width == curr.width, prev.height == curr.height else { return nil }

        let width = curr.width
        let height = curr.height

        // ShareX's rule, which is a good one: a twentieth of the width, never
        // less than 50 px, never more than a third.
        let margin = min(max(Self.minimumSideMargin, width / 20), width / 3)
        let sampleWidth = min(width - 2 * margin, Self.maximumSampleWidth)
        guard sampleWidth > 0 else { return nil }
        let sampleX = (width - sampleWidth) / 2

        guard let previousColumn = sampleColumn(of: prev, x: sampleX, width: sampleWidth),
              let currentColumn = sampleColumn(of: curr, x: sampleX, width: sampleWidth)
        else { return nil }

        let limit = height / Self.stickyLimitDivisor
        let stickyTop = stickyBand(previousColumn, currentColumn, fromTop: true, limit: limit)
        let stickyBottom = stickyBand(previousColumn, currentColumn, fromTop: false, limit: limit)

        let scrollingHeight = height - stickyTop - stickyBottom
        guard scrollingHeight >= Self.minimumRun else { return nil }

        guard let overlap = findOverlap(
            previousColumn, currentColumn,
            regionTop: stickyTop, regionHeight: scrollingHeight
        ) else { return nil }

        return FrameAlignment(stickyTop: stickyTop,
                              stickyBottom: stickyBottom,
                              scrollingHeight: scrollingHeight,
                              overlap: overlap)
    }

    /// How many rows at one end of the frame are unchanged between the two.
    private func stickyBand(
        _ previous: SampleColumn,
        _ current: SampleColumn,
        fromTop: Bool,
        limit: Int
    ) -> Int {
        var band = 0
        while band < limit {
            let row = fromTop ? band : previous.height - 1 - band
            guard rowsMatch(previous, row, current, row) else { break }
            band += 1
        }
        return band
    }

    /// Rows of the scrolling region the two frames have in common.
    ///
    /// `bottom` is the row of `curr`'s scrolling region where `prev`'s last
    /// scrolling row would sit, so the overlap is `bottom + 1`.  Candidates are
    /// walked from the largest down, i.e. smallest scroll distance first, so a
    /// tie goes to the alignment that assumes the least movement — including
    /// the no-movement case, which is how the caller learns the page has
    /// stopped.
    ///
    /// The run is capped at half the region, after which no candidate can do
    /// better and the search stops.  Each candidate gives up on its first
    /// mismatching row, so in practice this costs one row comparison per
    /// candidate, not a run per candidate.
    private func findOverlap(
        _ previous: SampleColumn,
        _ current: SampleColumn,
        regionTop: Int,
        regionHeight: Int
    ) -> Int? {
        let runCap = max(Self.minimumRun, regionHeight / 2)
        let lastRow = regionTop + regionHeight - 1
        var bestBottom = -1
        var bestRun = 0

        var bottom = regionHeight - 1
        while bottom >= Self.minimumRun - 1 {
            var run = 0
            while run < runCap, run <= bottom,
                  rowsMatch(previous, lastRow - run, current, regionTop + bottom - run) {
                run += 1
            }
            if run > bestRun {
                bestRun = run
                bestBottom = bottom
                if run >= runCap { break }
            }
            bottom -= 1
        }

        guard bestRun >= Self.minimumRun, bestBottom >= 0 else { return nil }
        return bestBottom + 1
    }

    // MARK: - Row comparison

    /// One column of a frame, rendered into a bitmap so its rows can be
    /// compared byte for byte.
    ///
    /// Holds its `CGContext` because `data` points into it; dropping the
    /// context would leave the pointer dangling.
    private struct SampleColumn {
        let context: CGContext
        let data: UnsafeMutableRawPointer
        let bytesPerRow: Int
        let width: Int
        let height: Int
    }

    private func sampleColumn(of image: CGImage, x: Int, width: Int) -> SampleColumn? {
        let height = image.height
        guard let cropped = image.cropping(
                to: CGRect(x: x, y: 0, width: width, height: height)),
              let context = bitmapCtx(w: width, h: height),
              let data = context.data
        else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return SampleColumn(context: context, data: data,
                            bytesPerRow: context.bytesPerRow,
                            width: width, height: height)
    }

    /// Whether two rows look the same.
    ///
    /// Every fourth pixel is sampled, and all three colour channels of it.  A
    /// flat byte step compared one channel only — blue, since the context is
    /// `byteOrder32Little` — so content with a uniform blue channel matched
    /// anywhere.
    ///
    /// A tolerance rather than exact equality.  ShareX requires rows to be
    /// identical byte for byte, which any subpixel antialiasing difference, any
    /// animated element and any lazily-loaded image breaks outright, and it
    /// then falls back to a guessed offset.  A few units of slack keeps the
    /// match and costs nothing.
    ///
    /// A `CGBitmapContext`'s buffer is top-down — byte row 0 is the image's top
    /// row — because `makeImage()` hands that buffer straight to a `CGImage`,
    /// and a `CGImage` always reads row 0 as the top.  So a row index here is
    /// an image row index, with no conversion.
    private func rowsMatch(
        _ left: SampleColumn, _ leftRow: Int,
        _ right: SampleColumn, _ rightRow: Int
    ) -> Bool {
        let leftOffset = leftRow * left.bytesPerRow
        let rightOffset = rightRow * right.bytesPerRow
        let span = min(left.width, right.width) * 4
        var column = 0
        while column < span {
            for channel in 0..<3 {
                let a = left.data.load(fromByteOffset: leftOffset + column + channel,
                                       as: UInt8.self)
                let b = right.data.load(fromByteOffset: rightOffset + column + channel,
                                        as: UInt8.self)
                if abs(Int(a) - Int(b)) > Self.tolerance { return false }
            }
            column += 16       // sample every 4 pixels
        }
        return true
    }

    // MARK: - Stitching

    /// Aligns each consecutive pair, then stitches.
    ///
    /// Only for callers that hold frames without their alignments — tests, and
    /// anything that re-stitches after the fact.  ``capture(window:scrollToTop:)``
    /// keeps the alignments it already computed rather than redoing them.
    func stitch(_ frames: [CGImage]) throws -> CGImage {
        guard frames.count > 1 else { return try stitch(frames, alignments: []) }

        var alignments: [FrameAlignment] = []
        for index in 1..<frames.count {
            if let alignment = align(prev: frames[index - 1], curr: frames[index]) {
                alignments.append(alignment)
            } else if let previous = alignments.last {
                // Nothing matched.  Pages scroll by a fixed amount, so the last
                // distance that did match is a better guess than giving up, and
                // a far better one than assuming the whole region is new.
                alignments.append(previous)
            } else {
                throw ScrollCaptureError.noOverlap
            }
        }
        return try stitch(frames, alignments: alignments)
    }

    /// Stitch captured frames into one tall image.
    ///
    /// The first frame contributes everything it shows bar its sticky footer;
    /// each later frame contributes only what scrolled into view, taken from
    /// just above that footer; and the footer itself is taken once, from the
    /// last frame, so it lands at the bottom of the result rather than being
    /// stitched in at every step.  The sticky header comes along with the first
    /// frame, at the top, for the same reason.
    ///
    /// The sticky footer width is one value for the whole stitch — the largest
    /// measured — because the arithmetic needs a single band and over-measuring
    /// is the safe direction: the band cancels out, so the result is the same
    /// pixels either way, while under-measuring stitches the footer into the
    /// middle of the image.
    ///
    /// Not private so the tests can drive it with synthetic frames: everything
    /// here is arithmetic over coordinate spaces, which is the part that needs
    /// no screen to check and the part that was wrong.
    func stitch(_ frames: [CGImage], alignments: [FrameAlignment]) throws -> CGImage {
        guard let first = frames.first else { throw ScrollCaptureError.noFrames }
        guard frames.count > 1 else { return first }
        guard alignments.count == frames.count - 1 else {
            throw ScrollCaptureError.alignmentMismatch(
                frames: frames.count, alignments: alignments.count)
        }

        // The narrowest frame, not the first one's width: a window resized
        // mid-scroll makes `cropping(to:)` return nil for a width the frame
        // does not have, and the strip was then dropped without a word.
        guard let width = frames.map(\.width).min(), width > 0 else {
            throw ScrollCaptureError.noFrames
        }

        let stickyBottom = alignments.map(\.stickyBottom).max() ?? 0

        struct Strip { let image: CGImage; let height: Int }
        var strips: [Strip] = []

        func append(_ frame: CGImage, rows range: Range<Int>) {
            guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= frame.height,
                  let cropped = frame.cropping(to: CGRect(
                    x: 0, y: range.lowerBound, width: width, height: range.count))
            else { return }
            strips.append(Strip(image: cropped, height: range.count))
        }

        append(first, rows: 0..<max(0, first.height - stickyBottom))

        for (index, alignment) in alignments.enumerated() {
            let frame = frames[index + 1]
            let bottom = frame.height - stickyBottom
            append(frame, rows: max(0, bottom - alignment.scrolled)..<max(0, bottom))
        }

        if stickyBottom > 0, let last = frames.last {
            append(last, rows: (last.height - stickyBottom)..<last.height)
        }

        guard !strips.isEmpty else { throw ScrollCaptureError.noFrames }

        let totalHeight = strips.reduce(0) { $0 + $1.height }
        guard let ctx = bitmapCtx(w: width, h: totalHeight) else {
            throw ScrollCaptureError.contextFailed
        }

        // No CTM flip.  Flipping the context flips the *content* of every image
        // drawn into it, so each strip came out mirrored top-to-bottom — right
        // order, upside-down contents.  Every other bitmap draw in this project
        // leaves the CTM alone; this was the one that did not.
        //
        // So place the strips from the top down in a y-up context instead: the
        // first strip, which is the top of the page, sits highest.
        var top = totalHeight
        for strip in strips {
            top -= strip.height
            ctx.draw(strip.image,
                     in: CGRect(x: 0, y: top, width: width, height: strip.height))
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
    case noOverlap
    case alignmentMismatch(frames: Int, alignments: Int)

    public var errorDescription: String? {
        switch self {
        case .noFrames:
            return "No frames were captured during scroll."
        case .contextFailed:
            return "Failed to create graphics context for stitching."
        case .noOverlap:
            return "The scrolled frames had nothing in common, so they could not be joined."
        case .alignmentMismatch(let frames, let alignments):
            return "Cannot stitch \(frames) frames with \(alignments) alignments."
        }
    }
}
