import XCTest
@testable import NeoQuill

final class BetaGracePromptTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "neoquill.test.betagrace"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func snapshot(status: LicenseStatus, mode: LicenseEnforcementMode) -> LicenseSnapshot {
        LicenseSnapshot(
            status: status, mode: mode,
            firstLaunchDate: nil, cutoffDate: nil, activation: nil
        )
    }

    func test_showsForBetaGraceUnderEnforcedMode_whenFlagNotSet() {
        XCTAssertTrue(BetaGracePrompt.shouldShow(
            snapshot: snapshot(status: .betaGrace, mode: .enforced),
            defaults: defaults
        ))
    }

    func test_doesNotShow_whenFlagAlreadySet() {
        defaults.set(true, forKey: BetaGracePrompt.userDefaultsKey)
        XCTAssertFalse(BetaGracePrompt.shouldShow(
            snapshot: snapshot(status: .betaGrace, mode: .enforced),
            defaults: defaults
        ))
    }

    func test_doesNotShow_whenModeIsDisabled() {
        // Beta-Grace im Disabled-Modus sollte gar nicht auftreten, aber sicherheitshalber.
        XCTAssertFalse(BetaGracePrompt.shouldShow(
            snapshot: snapshot(status: .betaGrace, mode: .disabled),
            defaults: defaults
        ))
    }

    func test_doesNotShow_forOtherStatuses() {
        let statuses: [LicenseStatus] = [
            .notRequired,
            .trial(daysRemaining: 5),
            .trialExpired,
            .activated(tier: .lifetime, lastValidatedAt: Date()),
            .invalidated(reason: .refunded)
        ]
        for status in statuses {
            XCTAssertFalse(BetaGracePrompt.shouldShow(
                snapshot: snapshot(status: status, mode: .enforced),
                defaults: defaults
            ))
        }
    }

    func test_markAsShown_persistsFlag() {
        BetaGracePrompt.markAsShown(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: BetaGracePrompt.userDefaultsKey))
    }

    func test_reset_clearsFlag() {
        defaults.set(true, forKey: BetaGracePrompt.userDefaultsKey)
        BetaGracePrompt.reset(defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: BetaGracePrompt.userDefaultsKey))
    }
}
