import XCTest
@testable import CentreeNaming

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
        let parser = NameParser(pattern: "%app%_screenshot.png", counter: { 1 })
        let result = parser.resolve(appName: "Xcode")
        XCTAssertEqual(result, "Xcode_screenshot.png")
    }

    func testCounterToken() {
        var count = 0
        let parser = NameParser(pattern: "shot_%counter%.png", counter: { count += 1; return count })
        XCTAssertEqual(parser.resolve(), "shot_1.png")
        XCTAssertEqual(parser.resolve(), "shot_2.png")
    }

    func testMissingAppNameFallback() {
        let parser = NameParser(pattern: "%app%.png", counter: { 1 })
        XCTAssertEqual(parser.resolve(appName: ""), "unknown.png")
    }

    // MARK: - Helpers

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return Calendar.current.date(from: comps)!
    }
}
