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
/// Persistiert als `rawValue` in der `lifecycle`-Spalte (siehe `MeetingStore`).
enum MeetingLifecycle: String, Codable, Hashable {
    /// Provisorisch angelegt, Aufnahme läuft noch.
    case recording
    /// Aufnahme beendet, Final-STT läuft.
    case transcribing
    /// Transkript steht, KI-Zusammenfassung läuft.
    case summarizing
    /// Fertig und nutzbar.
    case done

    /// UI-/Gating-Sicht: läuft gerade ein Hintergrundschritt? Ersetzt
    /// `processing == true` an allen alten Lesestellen.
    var isBusy: Bool {
        switch self {
        case .recording, .transcribing, .summarizing: return true
        case .done: return false
        }
    }
}
