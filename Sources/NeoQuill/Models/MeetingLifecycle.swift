import Foundation

/// Der persistente Lebenszyklus eines Meetings — die Single Source of Truth für
/// die Frage "wo steht dieses Meeting gerade?".
///
/// Ersetzt das frühere `processing: Bool`, das Aufnahme, Transkription,
/// Zusammenfassung und "fertig" auf einen einzigen Wahrheitswert kollabierte.
/// Weil ein Bool diese Phasen nicht auseinanderhalten konnte, musste die
/// Crash-Recovery raten (`processing && transcript.isEmpty`). Mit einem
/// typisierten Zustand ist diese Heuristik nicht mehr nötig.
///
/// Persistiert als `serialized`-String in der `lifecycle`-Spalte (siehe `MeetingStore`).
enum MeetingLifecycle: Codable, Hashable {
    /// Provisorisch angelegt, Aufnahme läuft noch.
    case recording
    /// Aufnahme beendet, Final-STT läuft.
    case transcribing
    /// Transkript steht, KI-Zusammenfassung läuft.
    case summarizing
    /// Fertig und nutzbar.
    case done
    /// Verarbeitung endgültig gescheitert (z.B. mehrfach unterbrochen). Trägt
    /// Grund und Versuchszahl, damit "hängt seit / N-mal versucht" ausdrückbar
    /// ist — genau das, was der frühere `processing: Bool` nicht konnte.
    case failed(reason: String, attempts: Int)

    /// UI-/Gating-Sicht: läuft gerade ein Hintergrundschritt? Ersetzt
    /// `processing == true` an allen alten Lesestellen. `failed` ist NICHT busy
    /// (kein laufender Job, kein Auto-Recovery-Loop).
    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .summarizing: return true
        case .done, .failed: return false
        }
    }

    /// Stabile, kollisionsfreie String-Form für die SQLite-`lifecycle`-Spalte.
    /// `failed:<attempts>:<reason>` — der Grund darf Doppelpunkte enthalten,
    /// weil nur der erste Trenner gesplittet wird.
    var serialized: String {
        switch self {
        case .recording:    return "recording"
        case .transcribing: return "transcribing"
        case .summarizing:  return "summarizing"
        case .done:         return "done"
        case .failed(let reason, let attempts): return "failed:\(attempts):\(reason)"
        }
    }

    /// Liest die `serialized`-Form. Unbekannte/leere Werte werden defensiv als
    /// `.done` interpretiert (kein versehentliches Hängenbleiben).
    init(serialized: String) {
        switch serialized {
        case "recording":    self = .recording
        case "transcribing": self = .transcribing
        case "summarizing":  self = .summarizing
        case "done":         self = .done
        default:
            guard serialized.hasPrefix("failed:") else { self = .done; return }
            let rest = serialized.dropFirst("failed:".count)
            let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let attempts = parts.first.flatMap { Int($0) } ?? 0
            let reason = parts.count > 1 ? String(parts[1]) : ""
            self = .failed(reason: reason, attempts: attempts)
        }
    }
}
