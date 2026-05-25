import XCTest
@testable import NeoQuill

final class LicenseSecretStoreTests: XCTestCase {

    private func makeRecord(
        key: String = "TEST-KEY-1234",
        instance: String = "instance-abc",
        tier: LicenseTier = .lifetime
    ) -> ActivationRecord {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        return ActivationRecord(
            licenseKey: key,
            lemonSqueezyInstanceID: instance,
            tier: tier,
            activatedAt: now,
            lastValidatedAt: now
        )
    }

    func test_inMemory_loadNil_whenEmpty() {
        let store = InMemoryLicenseSecretStore()
        XCTAssertNil(store.loadActivation())
    }

    func test_inMemory_saveAndLoad_returnsSameRecord() throws {
        let store = InMemoryLicenseSecretStore()
        let record = makeRecord()
        try store.saveActivation(record)
        XCTAssertEqual(store.loadActivation(), record)
    }

    func test_inMemory_save_overwritesPrevious() throws {
        let store = InMemoryLicenseSecretStore()
        try store.saveActivation(makeRecord(key: "OLD"))
        try store.saveActivation(makeRecord(key: "NEW"))
        XCTAssertEqual(store.loadActivation()?.licenseKey, "NEW")
    }

    func test_inMemory_clear_removesRecord() throws {
        let store = InMemoryLicenseSecretStore()
        try store.saveActivation(makeRecord())
        store.clearActivation()
        XCTAssertNil(store.loadActivation())
    }

    func test_with_lastValidatedAt_updatesOnlyTimestamp() {
        let original = makeRecord()
        let newDate = original.lastValidatedAt.addingTimeInterval(86_400)
        let updated = original.with(lastValidatedAt: newDate)

        XCTAssertEqual(updated.licenseKey, original.licenseKey)
        XCTAssertEqual(updated.lemonSqueezyInstanceID, original.lemonSqueezyInstanceID)
        XCTAssertEqual(updated.tier, original.tier)
        XCTAssertEqual(updated.activatedAt, original.activatedAt)
        XCTAssertEqual(updated.lastValidatedAt, newDate)
    }

    /// Roundtrip-Smoke gegen die echte Keychain. Aufräumen via clearActivation.
    func test_keychain_roundtrip_smoke() throws {
        let store = KeychainLicenseSecretStore()
        store.clearActivation()
        defer { store.clearActivation() }

        XCTAssertNil(store.loadActivation())

        let record = makeRecord(key: "ROUNDTRIP-KEY", instance: "rt-instance", tier: .team5)
        try store.saveActivation(record)

        let loaded = store.loadActivation()
        XCTAssertEqual(loaded?.licenseKey, "ROUNDTRIP-KEY")
        XCTAssertEqual(loaded?.lemonSqueezyInstanceID, "rt-instance")
        XCTAssertEqual(loaded?.tier, .team5)

        store.clearActivation()
        XCTAssertNil(store.loadActivation())
    }
}
