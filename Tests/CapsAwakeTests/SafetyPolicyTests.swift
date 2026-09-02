import XCTest
@testable import CapsAwakeShared

final class SafetyPolicyTests: XCTestCase {
    func testForceSleepOnLowBatteryUnplugged() {
        XCTAssertTrue(SafetyPolicy.shouldForceSleep(batteryPercent: 5, onAC: false, thermalState: .nominal))
    }

    func testNoForceJustAboveThreshold() {
        XCTAssertFalse(SafetyPolicy.shouldForceSleep(batteryPercent: 16, onAC: false, thermalState: .nominal))
    }

    func testNoForceOnACEvenAtZero() {
        XCTAssertFalse(SafetyPolicy.shouldForceSleep(batteryPercent: 0, onAC: true, thermalState: .nominal))
    }

    func testForceSleepOnCriticalThermal() {
        XCTAssertTrue(SafetyPolicy.shouldForceSleep(batteryPercent: 100, onAC: true, thermalState: .critical))
    }

    func testNoForceOnSeriousThermal() {
        XCTAssertFalse(SafetyPolicy.shouldForceSleep(batteryPercent: 100, onAC: true, thermalState: .serious))
    }

    func testConditionsClearedWhenRecharged() {
        XCTAssertTrue(SafetyPolicy.conditionsCleared(batteryPercent: 30, onAC: false, thermalState: .nominal))
    }

    func testConditionsNotClearedWhileDangerous() {
        XCTAssertFalse(SafetyPolicy.conditionsCleared(batteryPercent: 5, onAC: false, thermalState: .nominal))
        XCTAssertFalse(SafetyPolicy.conditionsCleared(batteryPercent: 100, onAC: true, thermalState: .critical))
    }

    func testConditionsClearedOnAC() {
        XCTAssertTrue(SafetyPolicy.conditionsCleared(batteryPercent: 1, onAC: true, thermalState: .nominal))
    }
}
