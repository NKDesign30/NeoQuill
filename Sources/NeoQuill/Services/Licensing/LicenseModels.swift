import Foundation

/// Master-Switch der entscheidet ob die Lizenz-Pflicht aktiv ist.
///
/// `disabled`: Beta-Phase. Kein Gate, kein Trial, keine UI. Build ist gratis nutzbar.
/// `enforced`: Lizenz-Pflicht aktiv. Trial/License/Grace greifen.
///
/// Quelle in dieser Reihenfolge: kompilierter Build-Default → UserDefaults-Override → später Remote-Config.
enum LicenseEnforcementMode: String, Codable, Equatable {
    case disabled
    case enforced
}

/// Was der Käufer erworben hat (oder als Beta-User geschenkt bekam).
///
/// Mapping zu Lemon-Squeezy-Variant-IDs lebt in `LicenseValidator`, nicht hier.
enum LicenseTier: String, Codable, Equatable {
    case betaGrace          // Beta-User vor Cutoff. Lifetime, kostenlos.
    case lifetime           // NeoQuill 1.x Lifetime, 89 EUR.
    case majorUpgrade       // 1.x → 2.0 Loyalty-Upgrade, 39 EUR.
    case team5              // Team 5 Seats, 349 EUR.
    case team10             // Team 10 Seats, 599 EUR.

    /// Wie viele Geräte diese Tier-Stufe gleichzeitig aktivieren darf.
    /// Authoritative Quelle ist Lemon Squeezy; hier nur für Anzeige.
    var nominalActivationLimit: Int {
        switch self {
        case .betaGrace, .lifetime, .majorUpgrade: return 1
        case .team5: return 5
        case .team10: return 10
        }
    }

    var displayName: String {
        switch self {
        case .betaGrace: return "Beta Lifetime"
        case .lifetime: return "Lifetime (1.x)"
        case .majorUpgrade: return "Major Upgrade to 2.0"
        case .team5: return "Team 5 Seats"
        case .team10: return "Team 10 Seats"
        }
    }
}

/// Aktueller Lizenz-Status der App. Single Source of Truth für
/// `LicenseEnforcement.canX()`-Gates.
enum LicenseStatus: Equatable {
    /// Master-Switch ist `disabled`. Alle Features frei, keine Prüfung.
    case notRequired

    /// Beta-User vor Cutoff. Frei wie `notRequired`, aber explizit gemerkt
    /// damit Settings-UI "Danke fürs Testen"-Sektion zeigt.
    case betaGrace

    /// Kein Key, Trial läuft. `daysRemaining` ist auf 0 geklemmt.
    case trial(daysRemaining: Int)

    /// 14 Tage rum, kein Key aktiviert. Pro-Features geblockt.
    case trialExpired

    /// Key aktiviert und zuletzt erfolgreich validiert.
    /// `lastValidatedAt` erlaubt Offline-Grace-Period in `LicenseValidator`.
    case activated(tier: LicenseTier, lastValidatedAt: Date)

    /// LS hat die Lizenz zurückgezogen (Refund, Chargeback, manuelle Deaktivierung).
    /// Pro-Features geblockt, User muss neu kaufen oder Key wechseln.
    case invalidated(reason: InvalidationReason)
}

/// Warum eine vorher aktive Lizenz jetzt ungültig ist.
enum InvalidationReason: String, Codable, Equatable {
    case refunded
    case revokedByOwner
    case activationLimitExceeded
    case keyNotFound          // LS antwortet 404 — Key existiert nicht (mehr).
    case other
}

/// Persistierte Aktivierungs-Daten. Wird in Keychain abgelegt.
/// `lemonSqueezyInstanceID` ist der Token den LS bei `/licenses/activate` zurückgibt
/// und der bei `/licenses/validate` mitgesendet werden muss.
struct ActivationRecord: Codable, Equatable {
    let licenseKey: String
    let lemonSqueezyInstanceID: String
    let tier: LicenseTier
    let activatedAt: Date
    let lastValidatedAt: Date

    func with(lastValidatedAt newDate: Date) -> ActivationRecord {
        ActivationRecord(
            licenseKey: licenseKey,
            lemonSqueezyInstanceID: lemonSqueezyInstanceID,
            tier: tier,
            activatedAt: activatedAt,
            lastValidatedAt: newDate
        )
    }
}

/// Snapshot der Lizenz-Daten zum Auslesen aus dem `LicenseService`.
/// Read-only für UI/Gates. Änderungen laufen über `LicenseService`-Methoden.
struct LicenseSnapshot: Equatable {
    let status: LicenseStatus
    let mode: LicenseEnforcementMode
    let firstLaunchDate: Date?
    let cutoffDate: Date?
    let activation: ActivationRecord?

    /// Convenience: hat der User irgendeine Form aktiver Berechtigung?
    /// Wird von `LicenseEnforcement.canUseSummary()` etc. konsumiert.
    var hasActiveEntitlement: Bool {
        switch status {
        case .notRequired, .betaGrace, .activated:
            return true
        case .trial(let remaining) where remaining > 0:
            return true
        case .trial, .trialExpired, .invalidated:
            return false
        }
    }
}
