import Foundation

/// Eine Quelle der Wahrheit für den `MM:SS`-Zeitstempel, den NeoQuill auf jede
/// `TranscriptLine` schreibt und beim Sortieren und Kapitel-Springen zurückliest.
///
/// `stamp` erzeugt exakt das Format, das die Recording-Pipeline seit jeher
/// persistiert: zwei-stellige Minuten ohne Stundenrollung (`90:00`, nicht
/// `1:30:00`). `parse` ist die Umkehrung und versteht zusätzlich die
/// drei-teilige Form `H:MM:SS`, wie sie der Zusammenfassungs-Layer in
/// Kapitel-Stempeln liefern kann. Producer und Consumer teilen sich damit
/// einen einzigen Format-Vertrag statt je eigener handgepflegter Kopien.
enum TranscriptTimecode {
    /// Sekunden → `MM:SS` (zwei-stellige Minuten, ohne Stundenrollung).
    static func stamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// `MM:SS` oder `H:MM:SS` → Sekunden. `nil` bei nicht parsebarer Eingabe.
    static func parse(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":")
        switch parts.count {
        case 2:
            guard let m = Int(parts[0]), let s = Int(parts[1]) else { return nil }
            return TimeInterval(m * 60 + s)
        case 3:
            guard let h = Int(parts[0]), let m = Int(parts[1]), let s = Int(parts[2]) else { return nil }
            return TimeInterval(h * 3600 + m * 60 + s)
        default:
            return nil
        }
    }
}
