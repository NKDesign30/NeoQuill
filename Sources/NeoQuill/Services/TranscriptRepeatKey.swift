import Foundation

/// Eine Quelle der Wahrheit dafür, wann zwei Transkript-Zeilen denselben
/// Körper haben. Der Rauschfilter (Summary-Eingang) und die kollabierte
/// Anzeige müssen diese Frage exakt gleich beantworten, sonst weicht die UI
/// von dem ab, was die Zusammenfassung als Wiederholung verworfen hat.
///
/// `normalized` macht Trim plus eine diakritik- und schreibungs-insensitive
/// Faltung und behält Satzzeichen — der reine Vergleich auf gleiche Bodies.
/// Der `TranscriptQualityScorer` baut für sein Scoring darauf auf und strippt
/// zusätzlich Satzzeichen; diese Divergenz ist dort bewusst und lokal sichtbar.
enum TranscriptRepeatKey {
    static func normalized(_ body: String) -> String {
        body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
