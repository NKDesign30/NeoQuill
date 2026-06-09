import Foundation

/// Eine Quelle für das ID-Format eines Meetings. Producer (RecordingController)
/// und Parser (TranscriptDownloadWatcher) teilen sich damit einen sichtbaren
/// Kontrakt statt je eigener String-Bastelei mit Präfix und Timestamp.
///
/// Zwei Quellen-Präfixe: `rec-<unixTimestamp>` für lokal aufgenommene Meetings,
/// `import-<unixTimestamp>` für importierte. Nur Recordings tragen einen
/// Timestamp, den der Download-Watcher im Zeitfenster zurückrechnet — Importe
/// haben bereits ihre eigene Transkript-Quelle und werden bewusst nicht gematcht.
enum MeetingID {
    static func recording(at start: Date) -> String {
        "rec-\(Int(start.timeIntervalSince1970))"
    }

    static func imported(at start: Date) -> String {
        "import-\(Int(start.timeIntervalSince1970))"
    }

    /// Der Recording-Start aus einer `rec-<ts>`-ID. Ein nackter Timestamp ohne
    /// Präfix wird ebenfalls akzeptiert; andere Formen (z.B. `import-…`,
    /// `manual-…`) liefern `nil` — die matcht der Download-Watcher bewusst nicht.
    static func recordingStart(from id: String) -> TimeInterval? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("rec-") ? String(trimmed.dropFirst(4)) : trimmed
        return TimeInterval(stripped)
    }
}
