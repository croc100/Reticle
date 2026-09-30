import XCTest
@testable import ReticleNaming

/// Token-by-token coverage for `NameParser`.
///
/// Tokens that read the environment — the frontmost app, the account name, the machine
/// name — are asserted on structurally rather than by value, since CI has no frontmost
/// app and no fixed hostname.
final class NameParserTokenTests: XCTestCase {

    private let reference = Calendar.current.date(from: DateComponents(
        year: 2025, month: 3, day: 15, hour: 14, minute: 7, second: 9
    ))

    // MARK: - Date and time

    func testZeroPadsDateComponents() throws {
        let date = try XCTUnwrap(reference)
        XCTAssertEqual(resolve("%year%", date), "2025")
        XCTAssertEqual(resolve("%yy%", date), "25")
        XCTAssertEqual(resolve("%month%", date), "03")
        XCTAssertEqual(resolve("%day%", date), "15")
        XCTAssertEqual(resolve("%hour%", date), "14")
        XCTAssertEqual(resolve("%minute%", date), "07")
        XCTAssertEqual(resolve("%second%", date), "09")
    }

    func testTwelveHourToken() throws {
        let date = try XCTUnwrap(reference)
        XCTAssertEqual(resolve("%h12%", date), "02", "14:07 is 02 in 12-hour form")
    }

    func testAmPmTokenSwitchesHourToTwelveHourForm() throws {
        let afternoon = try XCTUnwrap(reference)
        // %pm% present means %hour% reads as 12-hour, matching ShareX.
        XCTAssertEqual(resolve("%hour%%pm%", afternoon), "02PM")
        XCTAssertEqual(resolve("%hour%", afternoon), "14", "without %pm% the hour stays 24-hour")

        let morning = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2025, month: 3, day: 15, hour: 9, minute: 0, second: 0
        )))
        XCTAssertEqual(resolve("%hour%%pm%", morning), "09AM")
    }

    func testMidnightAndNoonInTwelveHourForm() throws {
        let midnight = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2025, month: 3, day: 15, hour: 0, minute: 0, second: 0
        )))
        XCTAssertEqual(resolve("%h12%%pm%", midnight), "12AM", "midnight is 12 AM, not 00")

        let noon = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2025, month: 3, day: 15, hour: 12, minute: 0, second: 0
        )))
        XCTAssertEqual(resolve("%h12%%pm%", noon), "12PM")
    }

    func testUnixTimestampToken() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(resolve("%unix%", date), "1700000000")
    }

    func testMillisecondsTokenIsThreeDigits() throws {
        let date = try XCTUnwrap(reference)
        let result = resolve("%ms%", date)
        XCTAssertEqual(result.count, 3, "%ms% should be zero-padded to three digits")
        XCTAssertTrue(result.allSatisfy(\.isNumber))
    }

    func testWeekNumberIsTwoDigits() throws {
        let date = try XCTUnwrap(reference)
        let result = resolve("%weeknum%", date)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy(\.isNumber))
    }

    func testMonthAndWeekdayNamesAreNonEmpty() throws {
        // Locale-dependent, so only the shape is asserted.
        let date = try XCTUnwrap(reference)
        XCTAssertFalse(resolve("%mon%", date).isEmpty)
        XCTAssertFalse(resolve("%weekday%", date).isEmpty)
    }

    // MARK: - Counter

    func testCounterIsReadOncePerResolve() {
        // %counter%, %ix% and %ia% are three views of the same number, so a pattern using
        // all three must not advance the counter three times.
        var calls = 0
        let parser = NameParser(pattern: "%counter%-%ix%-%ia%", counter: { calls += 1; return 255 })

        XCTAssertEqual(parser.resolve(), "255-ff-73")
        XCTAssertEqual(calls, 1, "the counter was read \(calls) times for one filename")
    }

    func testHexAndBase36CounterTokens() {
        XCTAssertEqual(resolveWithCounter("%ix%", 255), "ff")
        XCTAssertEqual(resolveWithCounter("%ix%", 16), "10")
        XCTAssertEqual(resolveWithCounter("%ia%", 35), "z")
        XCTAssertEqual(resolveWithCounter("%ia%", 36), "10")
        XCTAssertEqual(resolveWithCounter("%ia%", 0), "0")
    }

    // MARK: - Image dimensions

    func testDimensionTokens() {
        var parser = NameParser(pattern: "%width%x%height%", counter: { 1 })
        parser.imageWidth = 1920
        parser.imageHeight = 1080
        XCTAssertEqual(parser.resolve(), "1920x1080")
    }

    func testDimensionTokensAreBlankWhenUnset() {
        let parser = NameParser(pattern: "shot%width%.png", counter: { 1 })
        XCTAssertEqual(parser.resolve(), "shot.png")
    }

    // MARK: - Random

    func testRandomTokensHaveTheRightShape() {
        XCTAssertEqual(resolve("%rn%").count, 1)
        XCTAssertTrue(resolve("%rn%").allSatisfy(\.isNumber))
        XCTAssertEqual(resolve("%ra%").count, 1)
        XCTAssertEqual(resolve("%rx%").count, 1)
        XCTAssertNotNil(UUID(uuidString: resolve("%uuid%")))
        XCTAssertNotNil(UUID(uuidString: resolve("%guid%")))
    }

    func testGuidIsLowercasedAndUuidIsNot() {
        // Each resolve draws a fresh UUID, so compare each value against itself.
        let guid = resolve("%guid%")
        XCTAssertEqual(guid, guid.lowercased())

        let uuid = resolve("%uuid%")
        XCTAssertEqual(uuid, uuid.uppercased())
    }

    // MARK: - App and system tokens

    func testProcessNameOverridesTheFrontmostApp() {
        var parser = NameParser(pattern: "%app%", counter: { 1 })
        parser.processName = "Xcode"
        XCTAssertEqual(parser.resolve(), "Xcode")
    }

    func testAppAndPnAreTheSameToken() {
        var parser = NameParser(pattern: "%app%-%pn%", counter: { 1 })
        parser.processName = "Safari"
        XCTAssertEqual(parser.resolve(), "Safari-Safari")
    }

    func testSystemTokensResolveToSomething() {
        XCTAssertFalse(resolve("%un%").isEmpty)
        XCTAssertFalse(resolve("%cn%").isEmpty)
    }

    // MARK: - Sanitising externally supplied values

    func testPathSeparatorsInAnAppNameAreNeutralised() {
        // A `/` would add a directory level that does not exist, so the write fails and the
        // capture is lost.
        var parser = NameParser(pattern: "%app%.png", counter: { 1 })
        parser.processName = "Some/App"
        let result = parser.resolve()

        XCTAssertFalse(result.contains("/"), "resolved to \(result)")
        XCTAssertEqual(result, "Some-App.png")
    }

    func testColonsInAnAppNameAreNeutralised() {
        var parser = NameParser(pattern: "%app%.png", counter: { 1 })
        parser.processName = "10:30 Meeting"
        XCTAssertEqual(parser.resolve(), "10-30 Meeting.png")
    }

    func testLiteralSeparatorsInThePatternAreKept() {
        // A pattern is allowed to describe sub-folders, so only substituted values are
        // sanitised.
        var parser = NameParser(pattern: "%app%/shot.png", counter: { 1 })
        parser.processName = "Safari"
        XCTAssertEqual(parser.resolve(), "Safari/shot.png")
    }

    func testSanitiserRejectsNamesThatWouldPointAtADirectory() {
        XCTAssertEqual(NameParser.sanitized("."), "unknown")
        XCTAssertEqual(NameParser.sanitized(".."), "unknown")
        XCTAssertEqual(NameParser.sanitized(""), "unknown")
        XCTAssertEqual(NameParser.sanitized("   "), "unknown")
    }

    func testSanitiserLeavesOrdinaryNamesAlone() {
        XCTAssertEqual(NameParser.sanitized("Safari"), "Safari")
        XCTAssertEqual(NameParser.sanitized("Visual Studio Code"), "Visual Studio Code")
        XCTAssertEqual(NameParser.sanitized("한글 앱"), "한글 앱")
    }

    // MARK: - Pattern handling

    func testUnknownTokensArePassedThrough() {
        XCTAssertEqual(resolve("%nosuchtoken%.png"), "%nosuchtoken%.png")
    }

    func testPatternWithNoTokensIsReturnedVerbatim() {
        XCTAssertEqual(resolve("screenshot.png"), "screenshot.png")
    }

    func testDefaultPatternResolvesToADatedFilename() throws {
        let date = try XCTUnwrap(reference)
        let result = NameParser(counter: { 7 }).resolve(date: date)
        XCTAssertEqual(result, "2025-03-15_140709_7.png")
    }

    func testMonthTokenIsNotClobberedByTheMonthNameToken() throws {
        // "%month%" and "%mon%" overlap as text; substituting in the wrong order would
        // leave debris behind.
        let date = try XCTUnwrap(reference)
        let result = resolve("%month%_%mon%", date)
        XCTAssertTrue(result.hasPrefix("03_"), "got \(result)")
        XCTAssertFalse(result.contains("%"), "a token was left unresolved: \(result)")
    }

    // MARK: - Helpers

    private func resolve(_ pattern: String, _ date: Date = Date()) -> String {
        NameParser(pattern: pattern, counter: { 1 }).resolve(date: date)
    }

    private func resolveWithCounter(_ pattern: String, _ value: Int) -> String {
        NameParser(pattern: pattern, counter: { value }).resolve()
    }
}
