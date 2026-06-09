import Foundation

/// Besitzt die Spur-Dateien (Stems) eines Meetings an einem Ort: alle URLs, die
/// Playback-Auswahl und das vollständige Löschen.
///
/// Vorher war die Spur-Struktur verstreut: `PrivacyDataService` baute die
/// Dateinamen per String zusammen und vergaß dabei die `.hq`-Spur beim Löschen —
/// ein echtes Datenschutz-Leck, weil die größte Datei (das 48-kHz-Archiv) ein
/// "Audio löschen" überlebte. Dieses Modul ist die Single Source of Truth dafür,
/// welche Dateien zu einem Meeting gehören.
struct RecordingArtifacts {
    let meetingId: String
    let directory: URL

    init(meetingId: String, directory: URL = AudioWriter.recordingsDirectory()) {
        self.meetingId = meetingId
        self.directory = directory
    }

    func url(_ stem: RecordingAudioStem) -> URL {
        directory.appendingPathComponent("\(meetingId)\(stem.suffix).wav")
    }

    var micURL: URL { url(.mic) }
    var systemURL: URL { url(.system) }
    var mixURL: URL { url(.mix) }
    var hqURL: URL { url(.hq) }

    /// Alle Spur-Dateien dieses Meetings — inklusive `.hq`.
    var allURLs: [URL] { [RecordingAudioStem.mix, .mic, .system, .hq].map(url) }

    /// Playback bevorzugt das 48-kHz-Stereo-Archiv (`.hq`), wenn es auf der
    /// Platte liegt; sonst die übergebene Mono-Mix-Datei. So wird ein Meeting mit
    /// gutem Archiv bei Re-Transkription/Recovery nie auf den Mono-Mix degradiert.
    func preferredPlaybackURL(mixFallback: URL?, fileManager: FileManager = .default) -> URL? {
        if fileManager.fileExists(atPath: hqURL.path) { return hqURL }
        return mixFallback
    }

    /// Löscht alle vorhandenen Spur-Dateien (inkl. `.hq`) und gibt die Anzahl
    /// gelöschter Dateien zurück.
    @discardableResult
    func deleteAll(fileManager: FileManager = .default) throws -> Int {
        var deleted = 0
        for url in allURLs where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
            deleted += 1
        }
        return deleted
    }
}
