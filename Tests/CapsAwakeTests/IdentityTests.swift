import XCTest
@testable import CapsAwakeShared

final class IdentityTests: XCTestCase {
    private let appID = "com.piszeprogramy.capsawake"

    func testHelperLabelSuffix() {
        XCTAssertEqual(CapsAwakeIdentity.helperLabel(appBundleID: appID), "\(appID).helper")
    }

    func testAppBundleIDRoundTrip() {
        let label = CapsAwakeIdentity.helperLabel(appBundleID: appID)
        XCTAssertEqual(CapsAwakeIdentity.appBundleID(fromHelperLabel: label), appID)
    }

    func testAppBundleIDFromUnknownLabelReturnsNil() {
        XCTAssertNil(CapsAwakeIdentity.appBundleID(fromHelperLabel: "com.example.other"))
        XCTAssertNil(CapsAwakeIdentity.appBundleID(fromHelperLabel: appID))
        XCTAssertNil(CapsAwakeIdentity.appBundleID(fromHelperLabel: ""))
    }

    func testHelperBundleIDMatchesLabel() {
        XCTAssertEqual(
            CapsAwakeIdentity.helperBundleID(appBundleID: appID),
            CapsAwakeIdentity.helperLabel(appBundleID: appID)
        )
    }

    /// A malformed requirement (embedded newline / stray quote) kills the
    /// daemon's rejection of every connection. Pin it to a single line.
    func testRequirementIsSingleLine() {
        let requirement = CapsAwakeIdentity.codeSigningRequirement(appBundleID: appID)
        XCTAssertFalse(requirement.contains("\n"))
        XCTAssertFalse(requirement.contains("\r"))
    }

    func testRequirementPinsAppIdentifier() {
        let requirement = CapsAwakeIdentity.codeSigningRequirement(appBundleID: appID)
        XCTAssertTrue(requirement.contains("identifier \"\(appID)\""))
    }

    func testRequirementPinsAppleGenericAnchor() {
        XCTAssertTrue(
            CapsAwakeIdentity.codeSigningRequirement(appBundleID: appID)
                .contains("anchor apple generic")
        )
    }

    func testRequirementPinsTeamOU() {
        let requirement = CapsAwakeIdentity.codeSigningRequirement(appBundleID: appID)
        XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"\(CapsAwakeIdentity.teamID)\""))
    }
}
