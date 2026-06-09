import Foundation

/// Dekodiert eine (oft sandbox-externe) Audiodatei zu 16-kHz-Mono-Samples.
///
/// Kapselt den Boilerplate-Vorspann, der vorher in `importAudioFile` und
/// `mergeAudioIntoMeeting` wortgleich lag: den Security-Scope der Datei öffnen,
/// off-main dekodieren und den Scope wieder schließen. Die fachliche Differenz
/// der beiden Pfade (Status-Text, Log-Prefix, Fehlermeldung) bleibt beim Aufrufer.
enum AudioIngestService {
    /// Öffnet den Security-Scope, dekodiert off-main und schließt den Scope
    /// wieder. Wirft die Decode-Fehler unverändert weiter — der Aufrufer
    /// übersetzt sie in seine eigene Status-/Fehler-Darstellung.
    static func decode(url: URL) async throws -> [Float] {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) {
            try AudioImporter.decodeToWhisperSamples(url: url)
        }.value
    }
}
