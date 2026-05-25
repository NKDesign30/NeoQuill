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
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: nil,
            appVersionRaw: nil
        )
        XCTAssertEqual(mode, .disabled)
    }

    func test_currentMode_keepsZeroNineBuildsFree_evenWhenConfiguredEnforced() {
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: "enforced",
            appVersionRaw: "0.9.14"
        )
        XCTAssertEqual(mode, .disabled)
    }

    func test_currentMode_enforcesByDefault_fromVersionOne() {
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: nil,
            appVersionRaw: "1.0.0"
        )
        XCTAssertEqual(mode, .enforced)
    }

    func test_currentMode_respectsInfoPlistDisabled_fromVersionOne() {
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: "disabled",
            appVersionRaw: "1.0.0"
        )
        XCTAssertEqual(mode, .disabled)
    }

    func test_currentMode_ignoresUserDefaultsOverrideByDefault() {
        UserDefaults.standard.set("enforced", forKey: LicenseEnforcement.userDefaultsKey)
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: "disabled",
            appVersionRaw: "1.0.0"
        )
        XCTAssertEqual(mode, .disabled)
    }

    func test_currentMode_respectsExplicitUserDefaultsOverride_forQA() {
        UserDefaults.standard.set("disabled", forKey: LicenseEnforcement.userDefaultsKey)
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: "enforced",
            appVersionRaw: "1.0.0",
            allowUserDefaultsOverride: true
        )
        XCTAssertEqual(mode, .disabled)
    }

    func test_currentMode_ignoresInvalidUserDefaultsValue() {
        UserDefaults.standard.set("blub", forKey: LicenseEnforcement.userDefaultsKey)
        let mode = LicenseEnforcement.currentMode(
            configuredModeRaw: "enforced",
            appVersionRaw: "1.0.0",
            allowUserDefaultsOverride: true
        )
        XCTAssertEqual(mode, .enforced)
    }

    func test_releaseVersionPolicy_parsesPrereleaseAsCoreVersion() {
        XCTAssertTrue(ReleaseVersionPolicy.isPaidVersion("1.0.0-beta.1"))
        XCTAssertFalse(ReleaseVersionPolicy.isPaidVersion("0.9.99"))
        XCTAssertFalse(ReleaseVersionPolicy.isPaidVersion(nil))
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
