import XCTest
@testable import NeoQuill

final class LicenseEnforcementTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LicenseEnforcement.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LicenseEnforcement.userDefaultsKey)
        super.tearDown()
    }

    // MARK: - Mode-Resolution

    func test_currentMode_returnsDisabled_byDefault() {
        let mode = LicenseEnforcement.currentMode()
        XCTAssertEqual(mode, .disabled)
    }

    func test_currentMode_respectsUserDefaultsOverride() {
        UserDefaults.standard.set("enforced", forKey: LicenseEnforcement.userDefaultsKey)
        XCTAssertEqual(LicenseEnforcement.currentMode(), .enforced)
    }

    func test_currentMode_ignoresInvalidUserDefaultsValue() {
        UserDefaults.standard.set("blub", forKey: LicenseEnforcement.userDefaultsKey)
        XCTAssertEqual(LicenseEnforcement.currentMode(), .disabled)
    }

    // MARK: - Feature-Gates

    private func snapshot(status: LicenseStatus, mode: LicenseEnforcementMode = .enforced) -> LicenseSnapshot {
        LicenseSnapshot(
            status: status,
            mode: mode,
            firstLaunchDate: nil,
            cutoffDate: nil,
            activation: nil
        )
    }

    func test_canRecord_alwaysTrue() {
        XCTAssertTrue(LicenseEnforcement.canRecord(snapshot(status: .notRequired)))
        XCTAssertTrue(LicenseEnforcement.canRecord(snapshot(status: .trialExpired)))
        XCTAssertTrue(LicenseEnforcement.canRecord(snapshot(status: .invalidated(reason: .refunded))))
    }

    func test_canTranscribeLocally_alwaysTrue() {
        XCTAssertTrue(LicenseEnforcement.canTranscribeLocally(snapshot(status: .trialExpired)))
        XCTAssertTrue(LicenseEnforcement.canTranscribeLocally(snapshot(status: .invalidated(reason: .other))))
    }

    func test_canUseSummary_trueForActiveEntitlement() {
        XCTAssertTrue(LicenseEnforcement.canUseSummary(snapshot(status: .notRequired)))
        XCTAssertTrue(LicenseEnforcement.canUseSummary(snapshot(status: .betaGrace)))
        XCTAssertTrue(LicenseEnforcement.canUseSummary(snapshot(status: .trial(daysRemaining: 5))))
        XCTAssertTrue(LicenseEnforcement.canUseSummary(snapshot(status: .activated(tier: .lifetime, lastValidatedAt: now))))
    }

    func test_canUseSummary_falseForExpiredOrInvalidated() {
        XCTAssertFalse(LicenseEnforcement.canUseSummary(snapshot(status: .trial(daysRemaining: 0))))
        XCTAssertFalse(LicenseEnforcement.canUseSummary(snapshot(status: .trialExpired)))
        XCTAssertFalse(LicenseEnforcement.canUseSummary(snapshot(status: .invalidated(reason: .refunded))))
    }

    func test_canImportTranscript_followsEntitlement() {
        XCTAssertTrue(LicenseEnforcement.canImportTranscript(snapshot(status: .betaGrace)))
        XCTAssertFalse(LicenseEnforcement.canImportTranscript(snapshot(status: .trialExpired)))
    }

    func test_canCrossMeetingSpeakerID_followsEntitlement() {
        XCTAssertTrue(LicenseEnforcement.canCrossMeetingSpeakerID(snapshot(status: .activated(tier: .team5, lastValidatedAt: now))))
        XCTAssertFalse(LicenseEnforcement.canCrossMeetingSpeakerID(snapshot(status: .trialExpired)))
    }
}
