import Foundation

/// Eine Quelle der Wahrheit für die Dauer-Labels, die NeoQuill als String
/// persistiert (`Participant.spoke`, `Meeting.duration`) und in der
/// Sprecher-Leiste wieder zu Sekunden zurückrechnet.
///
/// Es gibt zwei Anzeige-Varianten: `minutesSeconds` schreibt immer
/// "{m}m {s}s" (Sprechanteile, gerundet), `compact` lässt unter einer Minute
/// die Minuten weg ("45s", trunkiert). `seconds(from:)` ist die gemeinsame
/// Umkehrung und versteht beide Formen plus null-gepaddete Sekunden.
///
/// Vorher lagen die zwei Producer (`formatSpoke`, `MeetingTimeline.durationShort`)
/// und ein dritter Hand-Parser in der View auseinander: der Parser kannte nur
/// "{m}m {s}s" und gab für die "45s"-Form fälschlich 0 zurück — wodurch der
/// Gesamt-Nenner der Prozent-Leiste bei Sub-Minuten-Meetings auf 0 brach.
enum SpokenDuration {
    /// Sekunden → "{m}m {s}s" (gerundet, auf 0 geclampt). Für Sprechanteile.
    static func minutesSeconds(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60)m \(total % 60)s"
    }

    /// Sekunden → "{s}s" unter einer Minute, sonst "{m}m {s}s" (trunkiert).
    /// Kompaktes Dauer-Label.
    static func compact(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let remainder = total % 60
        if minutes == 0 { return "\(remainder)s" }
        return "\(minutes)m \(remainder)s"
    }

    /// "{m}m {s}s", "{s}s" oder null-gepaddete Varianten → Sekunden.
    /// `nil` bei nicht parsebarer Eingabe.
    static func seconds(from label: String) -> Int? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var minutes = 0
        var secondsPart = Substring(trimmed)
        if let mRange = trimmed.range(of: "m") {
            let minutesText = trimmed[trimmed.startIndex..<mRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            guard let m = Int(minutesText) else { return nil }
            minutes = m
            secondsPart = trimmed[mRange.upperBound...]
        }

        let secondsText = secondsPart
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let s = Int(secondsText) else { return nil }
        return minutes * 60 + s
    }
}
