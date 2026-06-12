import Foundation

/// Entscheidet ob ein User automatisch die kostenlose `betaGrace`-Lizenz erhält.
///
/// Eingabe: `firstLaunchDate` aus `FirstLaunchMarker` + `cutoffDate` aus
/// `LicenseEnforcement`-Config. Reine Logik, keine Seiteneffekte.
///
/// Regel:
///   - Marker existiert UND Marker < Cutoff → grace
///   - sonst (kein Marker, kein Cutoff oder Marker ≥ Cutoff) → keine Grace
///
/// Wenn `cutoffDate == nil` wird bewusst KEINE Grace gegeben — der Release
/// muss das Cutoff-Datum explizit setzen damit der Switch wirkt. Schutz gegen
/// versehentliches "Alle kriegen alles gratis".
enum BetaGraceResolver {

    enum Decision: Equatable {
        case grace                  // User qualifiziert → automatische Beta-Lizenz
        case notEligible(reason: NotEligibleReason)
    }

    enum NotEligibleReason: String, Equatable {
        case noFirstLaunchMarker
        case noCutoffDate
        case launchedAfterCutoff
    }

    static func resolve(
        firstLaunchDate: Date?,
        cutoffDate: Date?
    ) -> Decision {
        guard let firstLaunchDate else {
            return .notEligible(reason: .noFirstLaunchMarker)
        }
        guard let cutoffDate else {
            return .notEligible(reason: .noCutoffDate)
        }
        if firstLaunchDate < cutoffDate {
            return .grace
        } else {
            return .notEligible(reason: .launchedAfterCutoff)
        }
    }
}
