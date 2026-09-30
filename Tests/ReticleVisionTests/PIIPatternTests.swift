import XCTest
@testable import ReticleVision

/// Tests for the PII pattern set.
///
/// Redaction is coarse — one match hides the whole recognised text block — so a false
/// positive is not a cosmetic problem: it blacks out a line of the screenshot. Both
/// directions therefore get the same attention, and the false-positive cases are named
/// after the ordinary things that used to trip the patterns.
final class PIIPatternTests: XCTestCase {

    private let allPatterns = Set(PIIDetector.allPatternNames)

    // MARK: - Phone numbers: the things that are not phone numbers

    func testBareFourDigitNumbersAreNotPhoneNumbers() {
        // The original pattern made every separator optional around four one-digit groups,
        // so its shortest possible match was four digits. Years, ports, and screen
        // dimensions all hid the line they sat on.
        for text in ["2026", "1920", "8080", "Build 1234", "Port 3000", "1080p"] {
            XCTAssertFalse(matchesPhone(text), "\"\(text)\" should not read as a phone number")
        }
    }

    func testOrdinaryNumbersAreNotPhoneNumbers() {
        for text in [
            "Total: 1234.56",
            "Line 42 of 9999",
            "v1.2.3",
            "192.168.1.1",
            "10.0.0.254",
            "255.255.255.0",
            "Order 5551234",
        ] {
            XCTAssertFalse(matchesPhone(text), "\"\(text)\" should not read as a phone number")
        }
    }

    func testDigitRunsTooLongForE164AreNotPhoneNumbers() {
        // E.164 tops out at 15 digits.
        XCTAssertFalse(matchesPhone("1234567890123456"))
        XCTAssertFalse(matchesPhone("99999999999999999999"))
    }

    // MARK: - Phone numbers: the things that are

    func testRecognisesGroupedPhoneNumbers() {
        for text in [
            "010-1234-5678",
            "+82 10 1234 5678",
            "+1 (555) 123-4567",
            "(555) 123-4567",
            "555.123.4567",
            "+44 20 7946 0958",
            "Call me at 010-9876-5432 tomorrow",
        ] {
            XCTAssertTrue(matchesPhone(text), "\"\(text)\" should read as a phone number")
        }
    }

    func testRecognisesUngroupedNumbersAtFullLength() {
        // No grouping to go on, so only a full-length run counts.
        XCTAssertTrue(matchesPhone("01012345678"))
        XCTAssertTrue(matchesPhone("5551234567"))
        XCTAssertFalse(matchesPhone("5551234"), "a bare 7-digit run is more often an ID")
    }

    // MARK: - Credit cards

    func testRecognisesCardNumbersThatPassLuhn() {
        // Scheme test numbers, all Luhn-valid.
        for text in [
            "4111111111111111",       // Visa
            "4012888888881881",       // Visa
            "5555555555554444",       // Mastercard
            "5105105105105100",       // Mastercard
            "378282246310005",        // Amex
            "371449635398431",        // Amex
            "6011111111111117",       // Discover
        ] {
            XCTAssertTrue(matches("credit_card", text), "\"\(text)\" should read as a card number")
        }
    }

    func testRejectsCardShapedNumbersThatFailLuhn() {
        // The regex matches on prefix and length alone, so without a checksum any 16-digit
        // run starting with 4 reads as a Visa number.
        for text in [
            "4111111111111112",
            "4000000000000000",
            "5555555555554445",
            "1234567812345678",
        ] {
            XCTAssertFalse(matches("credit_card", text), "\"\(text)\" should not read as a card number")
        }
    }

    func testLuhnCheckIsExactAboutItsArithmetic() {
        XCTAssertTrue(PIIDetector.passesLuhnCheck("4111111111111111"))
        XCTAssertFalse(PIIDetector.passesLuhnCheck(String("4111111111111111".dropLast()) + "0"))
        // Too short to be a card number at all.
        XCTAssertFalse(PIIDetector.passesLuhnCheck("18"))
        XCTAssertFalse(PIIDetector.passesLuhnCheck(""))
    }

    func testLuhnCheckIgnoresGroupingCharacters() {
        XCTAssertTrue(PIIDetector.passesLuhnCheck("4111 1111 1111 1111"))
        XCTAssertTrue(PIIDetector.passesLuhnCheck("4111-1111-1111-1111"))
    }

    // MARK: - Email

    func testRecognisesEmailAddresses() {
        for text in [
            "someone@example.com",
            "first.last+tag@sub.example.co.uk",
            "Contact: dev_team@company.io for details",
        ] {
            XCTAssertTrue(matches("email", text), "\"\(text)\" should read as an email address")
        }
    }

    func testDoesNotTreatEveryAtSignAsAnEmail() {
        for text in ["@mention", "user@", "@ example.com", "100@once"] {
            XCTAssertFalse(matches("email", text), "\"\(text)\" should not read as an email address")
        }
    }

    // MARK: - Tokens and keys

    func testRecognisesAWSAccessKeyIDs() {
        XCTAssertTrue(matches("aws_key", "AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(matches("aws_key", "ASIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(matches("aws_key", "AKIA_TOO_SHORT"))
        XCTAssertFalse(matches("aws_key", "akiaiosfodnn7example"), "the prefix is uppercase")
    }

    func testRecognisesGitHubTokens() {
        let token = "ghp_" + String(repeating: "a", count: 36)
        XCTAssertTrue(matches("github_pat", token))
        XCTAssertTrue(matches("github_pat", "ghs_" + String(repeating: "B", count: 36)))
        XCTAssertFalse(matches("github_pat", "ghp_tooshort"))
    }

    func testRecognisesJWTs() {
        let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertTrue(matches("jwt", jwt))
        XCTAssertFalse(matches("jwt", "eyJhbGciOiJIUzI1NiJ9"), "a lone header is not a JWT")
    }

    func testRecognisesLongHexSecrets() {
        XCTAssertTrue(matches("hex_secret", String(repeating: "a1b2", count: 8)))   // 32 chars
        XCTAssertFalse(matches("hex_secret", String(repeating: "ab", count: 8)))    // 16 chars
        XCTAssertFalse(matches("hex_secret", "not hex at all"))
    }

    func testRecognisesIBANs() {
        for text in ["GB82WEST12345698765432", "DE89370400440532013000"] {
            XCTAssertTrue(matches("iban", text), "\"\(text)\" should read as an IBAN")
        }
        XCTAssertFalse(matches("iban", "GB82"), "too short to be an IBAN")
    }

    // MARK: - Enablement

    func testAnEmptyEnabledSetMatchesNothing() {
        // Untoggling every pattern in Settings turns redaction off, not on.
        XCTAssertTrue(PIIDetector.matchedPatterns(in: "someone@example.com", enabled: []).isEmpty)
        XCTAssertFalse(PIIDetector.containsPII("4111111111111111", enabled: []))
    }

    func testOnlyEnabledPatternsAreConsidered() {
        let text = "someone@example.com"
        XCTAssertEqual(PIIDetector.matchedPatterns(in: text, enabled: ["email"]), ["email"])
        XCTAssertTrue(PIIDetector.matchedPatterns(in: text, enabled: ["credit_card"]).isEmpty)
    }

    func testReportsEveryPatternThatMatches() {
        let text = "mail someone@example.com or call +1 (555) 123-4567"
        let hits = PIIDetector.matchedPatterns(in: text, enabled: allPatterns)
        XCTAssertTrue(hits.contains("email"))
        XCTAssertTrue(hits.contains("phone_intl"))
    }

    func testCleanTextMatchesNothing() {
        for text in [
            "Hello, world",
            "The quick brown fox",
            "Screenshot saved to Desktop",
            "",
        ] {
            let hits = PIIDetector.matchedPatterns(in: text, enabled: allPatterns)
            XCTAssertTrue(hits.isEmpty, "\"\(text)\" matched \(hits.sorted())")
        }
    }

    func testAnUnknownPatternNameIsIgnored() {
        XCTAssertTrue(PIIDetector.matchedPatterns(in: "someone@example.com",
                                                  enabled: ["no_such_pattern"]).isEmpty)
    }

    func testEveryPatternCompiled() {
        // compactMap in the pattern table silently drops anything that fails to compile.
        XCTAssertEqual(PIIDetector.allPatternNames.count, 8, "a pattern failed to compile")
        XCTAssertEqual(Set(PIIDetector.allPatternNames), [
            "email", "phone_intl", "credit_card", "iban",
            "jwt", "aws_key", "github_pat", "hex_secret",
        ])
    }

    // MARK: - Helpers

    private func matches(_ pattern: String, _ text: String) -> Bool {
        PIIDetector.matchedPatterns(in: text, enabled: [pattern]).contains(pattern)
    }

    private func matchesPhone(_ text: String) -> Bool {
        matches("phone_intl", text)
    }
}
