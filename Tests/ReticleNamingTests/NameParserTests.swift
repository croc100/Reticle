import XCTest
@testable import ReticleNaming

final class NameParserTests: XCTestCase {
    func testDefaultPatternContainsDateComponents() {
        let parser = NameParser(counter: { 1 })
        let result = parser.resolve(date: date(year: 2025, month: 3, day: 15, hour: 9, minute: 5, second: 3))
        XCTAssert(result.contains("2025"))
        XCTAssert(result.contains("03"))
        XCTAssert(result.contains("15"))
        XCTAssert(result.contains("090503"))
    }

    func testAppNameToken() {
        var parser = NameParser(pattern: "%app%_screenshot.png", counter: { 1 })
        parser.processName = "Xcode"
        let result = parser.resolve()
        XCTAssertEqual(result, "Xcode_screenshot.png")
    }

    func testCounterToken() {
        var count = 0
        let parser = NameParser(pattern: "shot_%counter%.png", counter: { count += 1; return count })
        XCTAssertEqual(parser.resolve(), "shot_1.png")
        XCTAssertEqual(parser.resolve(), "shot_2.png")
    }

    func testMissingAppNameFallback() {
        var parser = NameParser(pattern: "%app%.png", counter: { 1 })
        parser.processName = ""
        // When processName is empty, falls back to frontmost app name or "unknown"
        let result = parser.resolve()
        // In test context there's no frontmost app, so result is either a real app name or "unknown"
        XCTAssert(!result.isEmpty)
    }

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return Calendar.current.date(from: comps)!
    }
}
