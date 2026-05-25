import XCTest
@testable import NeoQuill

@MainActor
final class LicenseServiceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let day: TimeInterval = 86_400

    private func makeService(
        mode: LicenseEnforcementMode = .enforced,
        cutoff: Date? = nil,
        markerInitial: Date? = nil,
        trialInitialStart: Date? = nil,
        recordInitial: ActivationRecord? = nil,
        clientActivate: Result<LSActivationResponse, Error> = .failure(LSLicenseError.nonHTTPResponse),
        clientValidate: Result<LSValidationResponse, Error> = .failure(LSLicenseError.nonHTTPResponse),
        clientDeactivate: Result<LSDeactivationResponse, Error> = .failure(LSLicenseError.nonHTTPResponse)
    ) -> (LicenseService, InMemoryFirstLaunchMarker, InMemoryTrialTracker, InMemoryLicenseSecretStore, MockLemonSqueezyLicenseClient) {
        let marker = InMemoryFirstLaunchMarker(initialDate: markerInitial)
        let trial = InMemoryTrialTracker(startedAt: trialInitialStart, lastSeen: trialInitialStart)
        let store = InMemoryLicenseSecretStore(initial: recordInitial)
        let client = MockLemonSqueezyLicenseClient()
        client.activateResult = clientActivate
        client.validateResult = clientValidate
        client.deactivateResult = clientDeactivate
        let validator = LicenseValidator(client: client, secretStore: store)

        let service = LicenseService(
            marker: marker,
            trial: trial,
            validator: validator,
            modeProvider: { mode },
            cutoffProvider: { cutoff }
        )
        return (service, marker, trial, store, client)
    }

    private func successfulActivation(variant: Int = VariantIDMap.lifetime) -> LSActivationResponse {
        LSActivationResponse(
            activated: true, errorMessage: nil,
            licenseKey: LSLicenseKeyInfo(id: 1, status: "active", key: "K",
                                        activationLimit: 1, activationUsage: 1, expiresAt: nil),
            instance: LSInstanceInfo(id: "inst-test", name: "Mac", createdAt: nil),
            meta: LSMeta(storeID: 386920, orderID: 1, orderItemID: 1,
                         productID: 1086348, productName: "NeoQuill",
                         variantID: variant, variantName: "v", customerEmail: "t@e.com")
        )
    }

    // MARK: - bootstrap

    func test_bootstrap_writesFirstLaunchMarker_evenWhenDisabled() async {
        let (service, marker, _, _, _) = makeService(mode: .disabled)
        XCTAssertNil(marker.firstLaunchDate())

        await service.bootstrap(now: now)

        XCTAssertEqual(marker.firstLaunchDate(), now)
        XCTAssertEqual(service.snapshot.status, .notRequired)
    }

    func test_bootstrap_disabled_doesNotStartTrial() async {
        let (service, _, trial, _, _) = makeService(mode: .disabled)
        await service.bootstrap(now: now)
        XCTAssertNil(trial.startedAt(), "Im Disabled-Modus darf kein Trial starten")
        XCTAssertEqual(service.snapshot.status, .notRequired)
    }

    // MARK: - Beta-Grace

    func test_enforced_withMarkerBeforeCutoff_grantsBetaGrace() async {
        let cutoff = now.addingTimeInterval(30 * day)
        let (service, _, trial, _, _) = makeService(
            mode: .enforced,
            cutoff: cutoff,
            markerInitial: now.addingTimeInterval(-10 * day)
        )
        await service.bootstrap(now: now)
        XCTAssertEqual(service.snapshot.status, .betaGrace)
        XCTAssertNil(trial.startedAt(), "Beta-Grace-User starten kein Trial")
    }

    func test_enforced_withMarkerAfterCutoff_startsTrial() async {
        let cutoff = now.addingTimeInterval(-30 * day)  // Cutoff war vor 30 Tagen
        let markerAt = now.addingTimeInterval(-1 * day) // Marker ist nach Cutoff
        let (service, _, trial, _, _) = makeService(
            mode: .enforced,
            cutoff: cutoff,
            markerInitial: markerAt
        )
        await service.bootstrap(now: now)
        if case .trial(let remaining) = service.snapshot.status {
            XCTAssertEqual(remaining, 14)
        } else {
            XCTFail("Expected .trial, got \(service.snapshot.status)")
        }
        XCTAssertNotNil(trial.startedAt())
    }

    // MARK: - Trial-Verlauf

    func test_trial_continuesFromExistingStart() async {
        // Trial wurde vor 5 Tagen gestartet
        let started = now.addingTimeInterval(-5 * day)
        let (service, _, _, _, _) = makeService(
            mode: .enforced,
            cutoff: now.addingTimeInterval(-100 * day),  // Marker irrelevant
            markerInitial: started,                       // gleichzeitig Marker
            trialInitialStart: started
        )
        await service.bootstrap(now: now)
        if case .trial(let remaining) = service.snapshot.status {
            XCTAssertEqual(remaining, 9, "5 Tage verbraucht, 9 verbleibend")
        } else {
            XCTFail("Expected .trial, got \(service.snapshot.status)")
        }
    }

    func test_trial_expires_after14Days() async {
        let started = now.addingTimeInterval(-20 * day)
        let (service, _, _, _, _) = makeService(
            mode: .enforced,
            cutoff: now.addingTimeInterval(-100 * day),
            markerInitial: started,
            trialInitialStart: started
        )
        await service.bootstrap(now: now)
        XCTAssertEqual(service.snapshot.status, .trialExpired)
    }

    // MARK: - Aktivierte Lizenz

    func test_activatedLicense_isReportedAsActivated_afterRefresh() async throws {
        let existingRecord = ActivationRecord(
            licenseKey: "K", lemonSqueezyInstanceID: "inst-test", tier: .lifetime,
            activatedAt: now.addingTimeInterval(-2 * day),
            lastValidatedAt: now.addingTimeInterval(-2 * day)
        )

        let validResponse = LSValidationResponse(
            valid: true, errorMessage: nil,
            licenseKey: LSLicenseKeyInfo(id: 1, status: "active", key: "K",
                                        activationLimit: 1, activationUsage: 1, expiresAt: nil),
            instance: nil, meta: nil
        )

        let (service, _, _, _, _) = makeService(
            mode: .enforced,
            cutoff: now.addingTimeInterval(-100 * day),
            markerInitial: now.addingTimeInterval(-100 * day),
            recordInitial: existingRecord,
            clientValidate: .success(validResponse)
        )
        await service.bootstrap(now: now)

        if case .activated(let tier, let lastValidatedAt) = service.snapshot.status {
            XCTAssertEqual(tier, .lifetime)
            XCTAssertEqual(lastValidatedAt, now)
        } else {
            XCTFail("Expected .activated, got \(service.snapshot.status)")
        }
    }

    func test_refundedLicense_becomesInvalidated() async {
        let existingRecord = ActivationRecord(
            licenseKey: "K", lemonSqueezyInstanceID: "inst-test", tier: .lifetime,
            activatedAt: now.addingTimeInterval(-10 * day),
            lastValidatedAt: now.addingTimeInterval(-10 * day)
        )
        let refundedResponse = LSValidationResponse(
            valid: false, errorMessage: "Order was refunded",
            licenseKey: nil, instance: nil, meta: nil
        )
        let (service, _, _, _, _) = makeService(
            mode: .enforced,
            cutoff: now.addingTimeInterval(-100 * day),
            markerInitial: now.addingTimeInterval(-100 * day),
            recordInitial: existingRecord,
            clientValidate: .success(refundedResponse)
        )
        await service.bootstrap(now: now)
        XCTAssertEqual(service.snapshot.status, .invalidated(reason: .refunded))
    }

    // MARK: - User-Actions

    func test_activate_persistsAndRefreshesToActivated() async throws {
        let (service, _, _, _, client) = makeService(
            mode: .enforced,
            cutoff: now.addingTimeInterval(-100 * day),
            markerInitial: now.addingTimeInterval(-100 * day),
            clientActivate: .success(successfulActivation(variant: VariantIDMap.team5)),
            clientValidate: .success(LSValidationResponse(
                valid: true, errorMessage: nil,
                licenseKey: LSLicenseKeyInfo(id: 1, status: "active", key: "K",
                                            activationLimit: 5, activationUsage: 1, expiresAt: nil),
                instance: nil, meta: nil
            ))
        )
        await service.bootstrap(now: now)

        let record = try await service.activate(licenseKey: "T-5", machineName: "Mac", now: now)
        XCTAssertEqual(record.tier, .team5)
        XCTAssertEqual(client.lastActivateArgs?.key, "T-5")

        if case .activated(let tier, _) = service.snapshot.status {
            XCTAssertEqual(tier, .team5)
        } else {
            XCTFail("Expected .activated nach activate()")
        }
    }

    func test_deactivate_clearsRecordAndReturnsToTrialOrExpired() async throws {
        let existingRecord = ActivationRecord(
            licenseKey: "K", lemonSqueezyInstanceID: "inst-test", tier: .lifetime,
            activatedAt: now.addingTimeInterval(-100 * day),
            lastValidatedAt: now.addingTimeInterval(-100 * day)
        )
        let (service, _, _, store, _) = makeService(
            mode: .enforced,
            cutoff: now.addingTimeInterval(-200 * day),
            markerInitial: now.addingTimeInterval(-200 * day),
            recordInitial: existingRecord,
            clientValidate: .success(LSValidationResponse(
                valid: true, errorMessage: nil,
                licenseKey: nil, instance: nil, meta: nil
            )),
            clientDeactivate: .success(LSDeactivationResponse(deactivated: true, errorMessage: nil))
        )
        await service.bootstrap(now: now)

        let ok = await service.deactivate(now: now)
        XCTAssertTrue(ok)
        XCTAssertNil(store.loadActivation())
        // Nach Deaktivierung: kein Record → Service startet Trial (oder zeigt expired wenn schon zu alt)
        switch service.snapshot.status {
        case .trial, .trialExpired:
            break  // beide OK
        default:
            XCTFail("Expected trial/expired nach deactivate, got \(service.snapshot.status)")
        }
    }
}
