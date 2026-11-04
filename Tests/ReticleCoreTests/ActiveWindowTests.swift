import CoreGraphics
import XCTest
@testable import ReticleCore

/// "Capture the window I am working in" is a question about ownership and
/// stacking order, so the rules are pure and testable with made-up windows —
/// no window server, no Screen Recording permission, and notably no
/// coordinates.
final class ActiveWindowTests: XCTestCase {

    // MARK: - Fixtures

    private let mine: pid_t = 50
    private let editor: pid_t = 100
    private let browser: pid_t = 200

    private func window(
        _ windowID: CGWindowID,
        pid: pid_t = 100,
        layer: Int = 0,
        onScreen: Bool = true,
        width: CGFloat = 800,
        height: CGFloat = 600
    ) -> WindowCandidate {
        WindowCandidate(
            windowID: windowID,
            layer: layer,
            isOnScreen: onScreen,
            processID: pid,
            width: width,
            height: height)
    }

    private func choose(
        _ candidates: [WindowCandidate],
        order: [CGWindowID],
        frontmost: pid_t?,
        excluding excluded: pid_t? = nil
    ) -> CGWindowID? {
        ActiveWindowChooser.choose(
            from: candidates,
            frontToBack: order,
            frontmostProcessID: frontmost,
            excluding: excluded)
    }

    // MARK: - The simple case

    func testChoosesTheOnlyWindow() {
        XCTAssertEqual(
            choose([window(7, pid: editor)], order: [7], frontmost: editor), 7)
    }

    func testReturnsNilForNoCandidates() {
        XCTAssertNil(choose([], order: [], frontmost: editor))
    }

    // MARK: - Focus beats stacking order

    /// A floating panel from another application can sit in front of the window
    /// the user is actually typing into, so the focused application's windows
    /// are considered first and the order only breaks ties among those.
    func testPrefersTheFocusedApplicationOverStackingOrder() {
        let candidates = [window(1, pid: editor), window(2, pid: browser)]
        // The browser's window is in front.
        XCTAssertEqual(choose(candidates, order: [2, 1], frontmost: editor), 1)
        // And with focus the other way round, the other answer.
        XCTAssertEqual(choose(candidates, order: [2, 1], frontmost: browser), 2)
    }

    func testStackingOrderDecidesWithinTheFocusedApplication() {
        let candidates = [window(1, pid: editor), window(2, pid: editor), window(3, pid: editor)]
        XCTAssertEqual(choose(candidates, order: [3, 2, 1], frontmost: editor), 3)
        XCTAssertEqual(choose(candidates, order: [2, 1, 3], frontmost: editor), 2)
    }

    /// The focused application may own nothing capturable — it can be showing
    /// only a panel, or have all its windows minimised. Falling back to the
    /// frontmost window of anything is more useful than refusing.
    func testFallsBackToAnyWindowWhenTheFocusedAppHasNone() {
        let candidates = [window(1, pid: editor), window(2, pid: editor)]
        XCTAssertEqual(choose(candidates, order: [2, 1], frontmost: 999), 2)
    }

    func testUnknownFocusFallsBackToStackingOrder() {
        let candidates = [window(1, pid: editor), window(2, pid: browser)]
        XCTAssertEqual(choose(candidates, order: [2, 1], frontmost: nil), 2)
    }

    // MARK: - What is not a window you want

    func testSkipsOffScreenWindows() {
        let candidates = [
            window(1, pid: editor, onScreen: false),
            window(2, pid: editor),
        ]
        XCTAssertEqual(choose(candidates, order: [1, 2], frontmost: editor), 2)
    }

    /// Panels, menus, tooltips, the Dock and the desktop picture all sit on
    /// levels other than zero.
    func testSkipsEverythingButOrdinaryWindows() {
        let candidates = [
            window(1, pid: editor, layer: 3),      // floating panel
            window(2, pid: editor, layer: 25),     // status level
            window(3, pid: editor, layer: -1),     // behind everything
            window(4, pid: editor, layer: 0),
        ]
        XCTAssertEqual(choose(candidates, order: [1, 2, 3, 4], frontmost: editor), 4)
    }

    /// Applications keep invisible one-point helper windows around. Without a
    /// floor the chooser picks one and the capture is a single pixel.
    func testSkipsTinyHelperWindows() {
        let candidates = [
            window(1, pid: editor, width: 1, height: 1),
            window(2, pid: editor),
        ]
        XCTAssertEqual(choose(candidates, order: [1, 2], frontmost: editor), 2)
    }

    func testTheSizeFloorIsInclusive() {
        let side = ActiveWindowChooser.minimumSide
        let justBig = window(1, pid: editor, width: side, height: side)
        let justSmall = window(2, pid: editor, width: side - 1, height: side)

        XCTAssertEqual(choose([justBig], order: [1], frontmost: editor), 1)
        XCTAssertNil(choose([justSmall], order: [2], frontmost: editor))
    }

    /// The focused application owning only a helper window is the same as
    /// owning nothing: fall through to another application's real window.
    func testAFocusedAppWithOnlyTinyWindowsFallsThrough() {
        let candidates = [
            window(1, pid: editor, width: 1, height: 1),
            window(2, pid: browser),
        ]
        XCTAssertEqual(choose(candidates, order: [1, 2], frontmost: editor), 2)
    }

    func testReturnsNilWhenNothingIsEligible() {
        let candidates = [
            window(1, pid: editor, onScreen: false),
            window(2, pid: editor, layer: 3),
            window(3, pid: editor, width: 2, height: 2),
        ]
        XCTAssertNil(choose(candidates, order: [1, 2, 3], frontmost: editor))
    }

    // MARK: - Never ourselves

    /// Reticle is a menu-bar app and does not take focus, but opening its menu
    /// can briefly make it frontmost — and "capture the window I am working in"
    /// must never answer "Reticle".
    func testNeverChoosesTheExcludedProcess() {
        let candidates = [window(1, pid: mine), window(2, pid: browser)]

        // Even with our own process frontmost and our window in front.
        XCTAssertEqual(
            choose(candidates, order: [1, 2], frontmost: mine, excluding: mine), 2)
        // And with no focus information at all.
        XCTAssertEqual(
            choose(candidates, order: [1, 2], frontmost: nil, excluding: mine), 2)
        // Our window alone leaves nothing to capture.
        XCTAssertNil(
            choose([window(1, pid: mine)], order: [1], frontmost: mine, excluding: mine))
    }

    // MARK: - When the order list does not help

    /// Should not happen for on-screen windows, but it is not worth failing
    /// over. The largest is usually the main window.
    func testFallsBackToTheLargestWhenTheOrderIsEmpty() {
        let candidates = [
            window(1, pid: editor, width: 400, height: 300),
            window(2, pid: editor, width: 1200, height: 800),
        ]
        XCTAssertEqual(choose(candidates, order: [], frontmost: editor), 2)
    }

    /// Equal areas resolve by window ID, so the answer does not depend on the
    /// order the candidates happened to arrive in.
    func testTheLargestFallbackIsDeterministic() {
        let small = window(1, pid: editor, width: 800, height: 600)
        let same = window(2, pid: editor, width: 600, height: 800)
        XCTAssertEqual(choose([small, same], order: [], frontmost: editor), 2)
        XCTAssertEqual(choose([same, small], order: [], frontmost: editor), 2)
    }

    // MARK: - Order list quirks

    /// A duplicated ID in the order list keeps its frontmost position rather
    /// than a later one overwriting it.
    func testDuplicateEntriesInTheOrderKeepTheFrontmostPosition() {
        let candidates = [window(1, pid: editor), window(2, pid: editor)]
        XCTAssertEqual(choose(candidates, order: [1, 2, 1], frontmost: editor), 1)
    }

    /// Windows missing from the order are ranked behind those present, not
    /// treated as frontmost.
    func testWindowsMissingFromTheOrderDoNotWin() {
        let candidates = [window(1, pid: editor), window(2, pid: editor)]
        XCTAssertEqual(choose(candidates, order: [2], frontmost: editor), 2)
    }
}
