import CoreGraphics
import XCTest
@testable import ReticleCore

/// Which display a point is on is pure geometry, so it is tested with made-up
/// layouts rather than whatever monitors the CI runner has — which is none.
///
/// Every frame here is in AppKit's global screen space: origin at the primary
/// display's bottom-left, y upward. The vertical cases are the ones that
/// matter, because that is where an implementation written against Quartz
/// coordinates agrees with this one on single-monitor setups and disagrees
/// everywhere else.
final class DisplayLayoutTests: XCTestCase {

    // MARK: - Fixtures

    private let primaryID: CGDirectDisplayID = 1
    private let secondaryID: CGDirectDisplayID = 2
    private let thirdID: CGDirectDisplayID = 3

    /// 1920×1080 primary with its bottom-left at the origin.
    private var primary: DisplayLayout.Display {
        DisplayLayout.Display(displayID: primaryID, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    private func layout(_ displays: DisplayLayout.Display...) -> DisplayLayout {
        DisplayLayout(displays: displays, primary: primaryID)
    }

    // MARK: - Single display

    func testPointOnTheOnlyDisplay() {
        let sut = layout(primary)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 960, y: 540)), primaryID)
    }

    func testEmptyLayoutFallsBackToPrimary() {
        let sut = DisplayLayout(displays: [], primary: primaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 960, y: 540)), primaryID)
    }

    // MARK: - Side by side

    func testPointOnADisplayToTheRight() {
        let right = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let sut = layout(primary, right)

        XCTAssertEqual(sut.display(containing: CGPoint(x: 100, y: 540)), primaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 2500, y: 540)), secondaryID)
    }

    /// A display to the left of the primary has a negative origin, which is
    /// ordinary and worth covering since it is easy to write geometry that
    /// assumes non-negative coordinates.
    func testPointOnADisplayToTheLeft() {
        let left = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let sut = layout(primary, left)

        XCTAssertEqual(sut.display(containing: CGPoint(x: -500, y: 540)), secondaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 500, y: 540)), primaryID)
    }

    /// Exactly on the seam. `CGRect.contains` excludes the max edges, so the
    /// shared column belongs to the right-hand display and to it alone — the
    /// answer must not depend on which display was listed first.
    func testTheSeamBelongsToExactlyOneDisplay() {
        let right = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        let seam = CGPoint(x: 1920, y: 540)

        XCTAssertEqual(layout(primary, right).display(containing: seam), secondaryID)
        XCTAssertEqual(layout(right, primary).display(containing: seam), secondaryID)
        // And one pixel back is still the left-hand display.
        XCTAssertEqual(layout(primary, right).display(containing: CGPoint(x: 1919, y: 540)),
                       primaryID)
    }

    // MARK: - Stacked vertically

    /// The case that catches a Quartz/AppKit mix-up.  In AppKit a display
    /// *above* the primary has a positive y origin; in Quartz the same display
    /// has a negative one, so geometry written against the wrong space sends
    /// this point to the primary.
    func testPointOnADisplayAbove() {
        let above = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080))
        let sut = layout(primary, above)

        XCTAssertEqual(sut.display(containing: CGPoint(x: 960, y: 1500)), secondaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 960, y: 500)), primaryID)
    }

    func testPointOnADisplayBelow() {
        let below = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 0, y: -1080, width: 1920, height: 1080))
        let sut = layout(primary, below)

        XCTAssertEqual(sut.display(containing: CGPoint(x: 960, y: -500)), secondaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 960, y: 500)), primaryID)
    }

    // MARK: - Three displays

    func testThreeDisplaysEachClaimTheirOwnPoints() {
        let right = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        let above = DisplayLayout.Display(
            displayID: thirdID,
            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1200))
        let sut = layout(primary, right, above)

        XCTAssertEqual(sut.display(containing: CGPoint(x: 10, y: 10)), primaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 3000, y: 1200)), secondaryID)
        XCTAssertEqual(sut.display(containing: CGPoint(x: 1000, y: 2000)), thirdID)
    }

    // MARK: - Points that land nowhere

    /// Displays need not tile the plane: an L-shaped arrangement leaves gaps,
    /// and a layout read a moment before a display slept or moved can put the
    /// pointer outside all of them. The nearest display is the useful answer,
    /// not the primary, which may be on the other side of the desk.
    func testAPointInAGapGoesToTheNearestDisplay() {
        let far = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1000, y: 0, width: 100, height: 100))
        let sut = DisplayLayout(
            displays: [
                DisplayLayout.Display(displayID: primaryID, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
                far,
            ],
            primary: primaryID)

        // Above the right-hand display, outside both. Horizontally it is inside
        // `far`'s span and 950 px from the primary, so `far` is nearer.
        XCTAssertEqual(sut.display(containing: CGPoint(x: 1050, y: 500)), secondaryID)
        // And just above the primary, the primary is nearer.
        XCTAssertEqual(sut.display(containing: CGPoint(x: 50, y: 500)), primaryID)
    }

    func testCornerDistanceIsMeasuredFromTheCorner() {
        let diagonal = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 200, y: 200, width: 100, height: 100))
        let sut = DisplayLayout(
            displays: [
                DisplayLayout.Display(displayID: primaryID, frame: CGRect(x: 0, y: 0, width: 100, height: 100)),
                diagonal,
            ],
            primary: primaryID)

        // (160, 160) is 60 px diagonally from the primary's top-right corner
        // and 40 px from the other display's bottom-left corner.
        XCTAssertEqual(sut.display(containing: CGPoint(x: 160, y: 160)), secondaryID)
        // (130, 130) is nearer the primary.
        XCTAssertEqual(sut.display(containing: CGPoint(x: 130, y: 130)), primaryID)
    }

    // MARK: - Bounding box

    func testBoundsOfASingleDisplayIsItsFrame() {
        XCTAssertEqual(layout(primary).bounds, primary.frame)
    }

    func testBoundsOfAnEmptyLayoutIsZero() {
        XCTAssertEqual(DisplayLayout(displays: [], primary: primaryID).bounds, .zero)
    }

    func testBoundsSpanDisplaysSideBySide() {
        let right = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(layout(primary, right).bounds,
                       CGRect(x: 0, y: 0, width: 3840, height: 1080))
    }

    /// A display left of or below the primary has a negative origin, so the
    /// bounding box does too — and the placements below are measured from it.
    func testBoundsSpanANegativeOrigin() {
        let left = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(layout(primary, left).bounds,
                       CGRect(x: -1920, y: 0, width: 3840, height: 1080))
    }

    /// Displays are rarely aligned in practice: a taller one beside a shorter
    /// one usually hangs off both ends.
    func testBoundsSpanAStaggeredLayout() {
        let bigger = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1920, y: -200, width: 2560, height: 1440))
        XCTAssertEqual(layout(primary, bigger).bounds,
                       CGRect(x: 0, y: -200, width: 4480, height: 1440))
    }

    // MARK: - Placement within the bounding box

    func testPlacementIsMeasuredFromTheBoundingBox() {
        let left = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        let sut = layout(primary, left)

        XCTAssertEqual(sut.placement(of: primaryID),
                       CGRect(x: 1920, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(sut.placement(of: secondaryID),
                       CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testPlacementOfAStaggeredLayout() {
        let bigger = DisplayLayout.Display(
            displayID: secondaryID,
            frame: CGRect(x: 1920, y: -200, width: 2560, height: 1440))
        let sut = layout(primary, bigger)

        XCTAssertEqual(sut.placement(of: primaryID),
                       CGRect(x: 0, y: 200, width: 1920, height: 1080))
        XCTAssertEqual(sut.placement(of: secondaryID),
                       CGRect(x: 1920, y: 0, width: 2560, height: 1440))
    }

    func testPlacementOfAnUnknownDisplayIsNil() {
        XCTAssertNil(layout(primary).placement(of: thirdID))
    }
}
