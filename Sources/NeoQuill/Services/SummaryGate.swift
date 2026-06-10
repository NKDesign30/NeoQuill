import Foundation

/// Die EINE Stelle, die entscheidet, ob eine KI-Summary laufen darf.
///
/// Vorher steckten die beiden Defaults-Gates (Local-Only-Modus, KI-Analyse-
/// Toggle) lose im `PostProcessor` — "dürfen wir summarizen?" wurde damit an
/// drei Orten beantwortet (License-Closure, zwei UserDefaults-Reads, Provider-
/// Config). Das Lizenz-Gate bleibt bewusst beim Aufrufer (injizierte Closure);
/// hier leben nur die nutzer-konfigurierten Schalter.
enum SummaryGate {

    /// `nil` = Summary darf laufen. Sonst der konkrete Grund fürs
    /// Überspringen — landet im Log statt eines stummen `return nil`.
    static func skipReason(defaults: UserDefaults = .standard) -> String? {
        if defaults.boolOr(AppSettings.localOnlyMode, default: false) {
            return "Local-Only-Modus aktiv"
        }
        if !defaults.boolOr(AppSettings.claudeAnalysisEnabled, default: true) {
            return "KI-Analyse in den Einstellungen deaktiviert"
        }
        return nil
    }

    static func allowsSummary(defaults: UserDefaults = .standard) -> Bool {
        skipReason(defaults: defaults) == nil
    }
}
