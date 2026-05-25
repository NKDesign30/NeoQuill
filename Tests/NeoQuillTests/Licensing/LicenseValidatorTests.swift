import XCTest
@testable import NeoQuill

final class LicenseValidatorTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let day: TimeInterval = 86_400

    private func makeValidator() -> (LicenseValidator, MockLemonSqueezyLicenseClient, InMemoryLicenseSecretStore) {
        let client = MockLemonSqueezyLicenseClient()
        let store = InMemoryLicenseSecretStore()
        let validator = LicenseValidator(client: client, secretStore: store)
        return (validator, client, store)
    }

    private func successfulActivation(variantID: Int = VariantIDMap.lifetime) -> LSActivationResponse {
        LSActivationResponse(
            activated: true,
            errorMessage: nil,
            licenseKey: LSLicenseKeyInfo(
                id: 1, status: "active", key: "ABCD-1234",
                activationLimit: 1, activationUsage: 1, expiresAt: nil
            ),
            instance: LSInstanceInfo(id: "inst-abc", name: "Test Mac", createdAt: nil),
            meta: LSMeta(
                storeID: 386920, orderID: 1, orderItemID: 1,
                productID: 1086348, productName: "NeoQuill",
                variantID: variantID, variantName: "Test",
                customerEmail: "t@e.com"
            )
        )
    }

    // MARK: - Activation

    func test_activate_persistsRecord_andMapsLifetime() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation(variantID: VariantIDMap.lifetime))

        let record = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Test Mac", now: now)

        XCTAssertEqual(record.tier, .lifetime)
        XCTAssertEqual(record.lemonSqueezyInstanceID, "inst-abc")
        XCTAssertEqual(store.loadActivation()?.licenseKey, "ABCD-1234")
        XCTAssertEqual(client.lastActivateArgs?.key, "ABCD-1234")
    }

    func test_activate_mapsTeam5() async throws {
        let (validator, client, _) = makeValidator()
        client.activateResult = .success(successfulActivation(variantID: VariantIDMap.team5))

        let record = try await validator.activate(licenseKey: "T-5", machineName: "Mac", now: now)
        XCTAssertEqual(record.tier, .team5)
    }

    func test_activate_mapsTeam10() async throws {
        let (validator, client, _) = makeValidator()
        client.activateResult = .success(successfulActivation(variantID: VariantIDMap.team10))

        let record = try await validator.activate(licenseKey: "T-10", machineName: "Mac", now: now)
        XCTAssertEqual(record.tier, .team10)
    }

    func test_activate_throws_whenLSReportsFailure() async {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(LSActivationResponse(
            activated: false, errorMessage: "license_key not found",
            licenseKey: nil, instance: nil, meta: nil
        ))

        do {
            _ = try await validator.activate(licenseKey: "X", machineName: "M", now: now)
            XCTFail("Expected throw")
        } catch LicenseValidatorError.activationFailed {
            XCTAssertNil(store.loadActivation())
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    func test_activate_throws_onUnknownVariant() async {
        let (validator, client, _) = makeValidator()
        client.activateResult = .success(successfulActivation(variantID: 9_999_999))

        do {
            _ = try await validator.activate(licenseKey: "X", machineName: "M", now: now)
            XCTFail("Expected throw")
        } catch LicenseValidatorError.unknownVariant(let id) {
            XCTAssertEqual(id, 9_999_999)
        } catch {
            XCTFail("Unexpected: \(error)")
        }
    }

    // MARK: - Validate

    func test_validate_noRecord_returnsNoRecord() async {
        let (validator, _, _) = makeValidator()
        let outcome = await validator.validate(now: now)
        XCTAssertEqual(outcome, .noRecord)
    }

    func test_validate_validResponse_updatesLastValidatedAt() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        let later = now.addingTimeInterval(3 * day)
        client.validateResult = .success(LSValidationResponse(
            valid: true, errorMessage: nil,
            licenseKey: LSLicenseKeyInfo(id: 1, status: "active", key: "ABCD-1234",
                                        activationLimit: 1, activationUsage: 1, expiresAt: nil),
            instance: LSInstanceInfo(id: "inst-abc", name: "Mac", createdAt: nil),
            meta: nil
        ))

        let outcome = await validator.validate(now: later)
        guard case .stillValid(let record) = outcome else {
            return XCTFail("Expected .stillValid, got \(outcome)")
        }
        XCTAssertEqual(record.lastValidatedAt, later)
        XCTAssertEqual(store.loadActivation()?.lastValidatedAt, later)
    }

    func test_validate_invalid_clearsRecordAndReportsReason() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.validateResult = .success(LSValidationResponse(
            valid: false,
            errorMessage: "license_key has been disabled",
            licenseKey: LSLicenseKeyInfo(id: 1, status: "disabled", key: nil,
                                        activationLimit: 1, activationUsage: 1, expiresAt: nil),
            instance: nil, meta: nil
        ))

        let outcome = await validator.validate(now: now.addingTimeInterval(day))
        XCTAssertEqual(outcome, .invalidated(.revokedByOwner))
        XCTAssertNil(store.loadActivation())
    }

    func test_validate_invalidWithRefundMessage_mapsToRefunded() async throws {
        let (validator, client, _) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.validateResult = .success(LSValidationResponse(
            valid: false, errorMessage: "Order was refunded",
            licenseKey: nil, instance: nil, meta: nil
        ))

        let outcome = await validator.validate(now: now.addingTimeInterval(day))
        XCTAssertEqual(outcome, .invalidated(.refunded))
    }

    // MARK: - Offline-Grace

    func test_validate_networkError_withinGrace_returnsOfflineGrace() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.validateResult = .failure(LSLicenseError.transport("offline"))

        let twoDaysLater = now.addingTimeInterval(2 * day)
        let outcome = await validator.validate(now: twoDaysLater)

        guard case .offlineGrace(let record) = outcome else {
            return XCTFail("Expected .offlineGrace, got \(outcome)")
        }
        XCTAssertEqual(record.licenseKey, "ABCD-1234")
        // Record bleibt erhalten — User wird nicht ausgesperrt
        XCTAssertNotNil(store.loadActivation())
    }

    func test_validate_networkError_afterGracePeriod_invalidates() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.validateResult = .failure(LSLicenseError.transport("offline"))

        let eightDaysLater = now.addingTimeInterval(8 * day)
        let outcome = await validator.validate(now: eightDaysLater)

        XCTAssertEqual(outcome, .invalidated(.other))
        XCTAssertNil(store.loadActivation())
    }

    func test_validate_http4xx_doesNotUseOfflineGrace() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.validateResult = .failure(LSLicenseError.httpStatus(404, "{\"error\":\"license_key not found\"}"))

        let twoDaysLater = now.addingTimeInterval(2 * day)
        let outcome = await validator.validate(now: twoDaysLater)

        XCTAssertEqual(outcome, .invalidated(.keyNotFound))
        XCTAssertNil(store.loadActivation())
    }

    // MARK: - Deactivate

    func test_deactivate_callsLSAndClearsRecord() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.deactivateResult = .success(LSDeactivationResponse(deactivated: true, errorMessage: nil))

        let ok = await validator.deactivate()
        XCTAssertTrue(ok)
        XCTAssertNil(store.loadActivation())
        XCTAssertEqual(client.lastDeactivateArgs?.key, "ABCD-1234")
    }

    func test_deactivate_keepsRecord_whenLSFails() async throws {
        let (validator, client, store) = makeValidator()
        client.activateResult = .success(successfulActivation())
        _ = try await validator.activate(licenseKey: "ABCD-1234", machineName: "Mac", now: now)

        client.deactivateResult = .failure(LSLicenseError.transport("network down"))

        let ok = await validator.deactivate()
        XCTAssertFalse(ok)
        // Slot bleibt remote aktiv, also dürfen wir den Instance-Record nicht verlieren.
        XCTAssertNotNil(store.loadActivation())
    }
}
