import Foundation

/// Orchestriert die Lemon-Squeezy-Lizenz-Flows + persistiert das Ergebnis lokal.
///
/// Nutzt `LemonSqueezyLicensing` für HTTP und `LicenseSecretStoring` für Keychain.
/// Stellt Offline-Grace-Period bereit: solange die letzte erfolgreiche
/// Validation < 7 Tage zurückliegt, bleibt der User aktiviert auch wenn
/// `validate()` jetzt am Netz scheitert.
protocol LicenseValidating {
    func activate(licenseKey: String, machineName: String, now: Date) async throws -> ActivationRecord
    func validate(now: Date) async -> ValidationOutcome
    func deactivate() async -> Bool
    func currentRecord() -> ActivationRecord?
}

/// Ergebnis eines `validate()`-Calls. Verarbeitet vom `LicenseService` zu
/// `LicenseStatus`.
enum ValidationOutcome: Equatable {
    case noRecord                               // Keine Lizenz lokal vorhanden
    case stillValid(ActivationRecord)           // Online validiert + Record aktualisiert
    case offlineGrace(ActivationRecord)         // Netz-Fehler, aber letzte Validation < 7 Tage
    case invalidated(InvalidationReason)        // LS sagt: ungültig — oder Offline-Grace abgelaufen
}

enum LicenseValidatorError: Error, Equatable {
    case unknownVariant(Int)
    case activationFailed(String)
    case activationMissingInstanceID
}

/// Mapping der produktiven LS-Variant-IDs auf `LicenseTier`.
/// Quelle: `Tools/LSAdmin/state.json` aus Slice 2 des LS-Setups.
enum VariantIDMap {
    static let lifetime: Int        = 1702242
    static let majorUpgrade: Int    = 1702265
    static let team5: Int           = 1702269
    static let team10: Int          = 1702271

    static func tier(forVariantID id: Int) -> LicenseTier? {
        switch id {
        case lifetime:      return .lifetime
        case majorUpgrade:  return .majorUpgrade
        case team5:         return .team5
        case team10:        return .team10
        default:            return nil
        }
    }
}

/// Wie lange wir Offline-Grace gewähren bevor wir einen User aussperren.
private let offlineGracePeriod: TimeInterval = 7 * 24 * 60 * 60

final class LicenseValidator: LicenseValidating {
    private let client: LemonSqueezyLicensing
    private let secretStore: LicenseSecretStoring

    init(
        client: LemonSqueezyLicensing,
        secretStore: LicenseSecretStoring
    ) {
        self.client = client
        self.secretStore = secretStore
    }

    // MARK: - Public

    func activate(licenseKey: String, machineName: String, now: Date) async throws -> ActivationRecord {
        let response = try await client.activate(licenseKey: licenseKey, instanceName: machineName)

        guard response.activated else {
            throw LicenseValidatorError.activationFailed(response.errorMessage ?? "Unbekannter Fehler")
        }
        guard let instanceID = response.instance?.id else {
            throw LicenseValidatorError.activationMissingInstanceID
        }
        guard let variantID = response.meta?.variantID,
              let tier = VariantIDMap.tier(forVariantID: variantID) else {
            throw LicenseValidatorError.unknownVariant(response.meta?.variantID ?? -1)
        }

        let record = ActivationRecord(
            licenseKey: licenseKey,
            lemonSqueezyInstanceID: instanceID,
            tier: tier,
            activatedAt: now,
            lastValidatedAt: now
        )
        try secretStore.saveActivation(record)
        return record
    }

    func validate(now: Date) async -> ValidationOutcome {
        guard let record = secretStore.loadActivation() else {
            return .noRecord
        }

        do {
            let response = try await client.validate(
                licenseKey: record.licenseKey,
                instanceID: record.lemonSqueezyInstanceID
            )
            if response.valid {
                let updated = record.with(lastValidatedAt: now)
                try? secretStore.saveActivation(updated)
                return .stillValid(updated)
            } else {
                let reason = Self.mapInvalidation(response: response)
                secretStore.clearActivation()
                return .invalidated(reason)
            }
        } catch {
            // Netz-Fehler oder LS down → Offline-Grace prüfen.
            // LS-4XX ist dagegen eine autoritative API-Ablehnung und darf
            // nicht als "offline" weitergewunken werden.
            if Self.allowsOfflineGrace(for: error),
               now.timeIntervalSince(record.lastValidatedAt) <= offlineGracePeriod {
                return .offlineGrace(record)
            }
            secretStore.clearActivation()
            return .invalidated(Self.mapInvalidation(error: error))
        }
    }

    func deactivate() async -> Bool {
        guard let record = secretStore.loadActivation() else { return true }
        do {
            let response = try await client.deactivate(
                licenseKey: record.licenseKey,
                instanceID: record.lemonSqueezyInstanceID
            )
            guard response.deactivated else { return false }
            secretStore.clearActivation()
            return true
        } catch {
            return false
        }
    }

    func currentRecord() -> ActivationRecord? {
        secretStore.loadActivation()
    }

    // MARK: - Mapping

    private static func mapInvalidation(response: LSValidationResponse) -> InvalidationReason {
        if let status = response.licenseKey?.status {
            switch status {
            case "disabled":    return .revokedByOwner
            case "expired":     return .other
            case "inactive":    return .revokedByOwner
            default: break
            }
        }
        if let msg = response.errorMessage?.lowercased() {
            if msg.contains("refund") { return .refunded }
            if msg.contains("activation") && msg.contains("limit") { return .activationLimitExceeded }
            if msg.contains("not found") { return .keyNotFound }
        }
        return .other
    }

    private static func allowsOfflineGrace(for error: Error) -> Bool {
        guard let licenseError = error as? LSLicenseError else { return true }
        switch licenseError {
        case .httpStatus(let code, _):
            return !(400..<500).contains(code)
        case .transport, .nonHTTPResponse, .invalidJSON:
            return true
        case .malformedURL:
            return false
        }
    }

    private static func mapInvalidation(error: Error) -> InvalidationReason {
        guard let licenseError = error as? LSLicenseError else { return .other }
        switch licenseError {
        case .httpStatus(let code, let body):
            let message = body?.lowercased() ?? ""
            if code == 404 || message.contains("not found") { return .keyNotFound }
            if message.contains("refund") { return .refunded }
            if message.contains("disabled") || message.contains("revoked") { return .revokedByOwner }
            if message.contains("activation") && message.contains("limit") {
                return .activationLimitExceeded
            }
            return .other
        case .malformedURL, .transport, .nonHTTPResponse, .invalidJSON:
            return .other
        }
    }
}
