import XCTest
@testable import CapsAwakeShared

final class PmsetParsingTests: XCTestCase {
    /// Captured from a macOS 26 host where the flag was never set: the line is
    /// entirely absent under a successful `pmset -g`.
    private let macos26AbsentSample = """
    System-wide power settings:
    Currently in use:
     standby              1
     Sleep On Power Button 1
     sleep                1 (sleep prevented by powerd)
     disksleep            10
     displaysleep         120
    """

    func testParseEnabled() {
        XCTAssertEqual(
            PmsetParsing.parseSleepDisabled(stdout: "SleepDisabled        1\n sleep 1"),
            .enabled
        )
    }

    func testParseDisabled() {
        XCTAssertEqual(
            PmsetParsing.parseSleepDisabled(stdout: "SleepDisabled        0"),
            .disabled
        )
    }

    func testParseAbsentWhenLineMissing() {
        XCTAssertEqual(PmsetParsing.parseSleepDisabled(stdout: macos26AbsentSample), .absent)
    }

    func testParseIgnoresOtherSleepKeys() {
        let output = "sleep                1\nSleepDisabled        0\nsleep disabled by others"
        XCTAssertEqual(PmsetParsing.parseSleepDisabled(stdout: output), .disabled)
    }

    func testParseKeyCaseInsensitive() {
        XCTAssertEqual(PmsetParsing.parseSleepDisabled(stdout: "sleepdisabled 1"), .enabled)
    }

    func testParseMalformedValue() {
        XCTAssertEqual(PmsetParsing.parseSleepDisabled(stdout: "SleepDisabled maybe"), .malformed)
    }

    func testParseMalformedWhenKeyAlone() {
        XCTAssertEqual(PmsetParsing.parseSleepDisabled(stdout: "SleepDisabled"), .malformed)
    }

    func testParseDoesNotMatchKeyPrefix() {
        XCTAssertEqual(PmsetParsing.parseSleepDisabled(stdout: "SleepDisabledness 1"), .absent)
    }

    func testResolveEnabledOnCleanExit() {
        XCTAssertEqual(
            PmsetParsing.resolveFlag(status: 0, stdout: "SleepDisabled        1"),
            .enabled
        )
    }

    func testResolveDisabledOnCleanExitWithZero() {
        XCTAssertEqual(
            PmsetParsing.resolveFlag(status: 0, stdout: "SleepDisabled        0"),
            .disabled
        )
    }

    /// The macOS 26 reality: clean exit, no line => flag unset, safe to sleep.
    func testResolveDisabledWhenAbsentOnCleanExit() {
        XCTAssertEqual(
            PmsetParsing.resolveFlag(status: 0, stdout: macos26AbsentSample),
            .disabled
        )
    }

    func testResolveUnknownOnNonZeroExit() {
        XCTAssertEqual(
            PmsetParsing.resolveFlag(status: 1, stdout: "SleepDisabled        1"),
            .unknown
        )
    }

    func testResolveUnknownOnEmptyOutput() {
        XCTAssertEqual(PmsetParsing.resolveFlag(status: 0, stdout: ""), .unknown)
    }

    func testResolveUnknownOnMalformed() {
        XCTAssertEqual(
            PmsetParsing.resolveFlag(status: 0, stdout: "SleepDisabled nonsense"),
            .unknown
        )
    }
}
