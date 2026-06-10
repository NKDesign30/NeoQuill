import Foundation

/// Besitzt die Playback-Auflösungs-Kette: PitchGuard-Entscheidung → korrigierte
/// Kopie rendern → bei Render-Fehlschlag Rate-Fallback mit 0.5-Floor.
///
/// Vorher lebte dieser Entscheidungsbaum view-privat in
/// `AudioPlayer.loadPlayer()` — getestet waren nur die Blätter (PitchGuard,
/// FileCorrector), während genau die Schicht der historischen Playback-Bugs
/// (siehe 0.9.9-Changelog) ungetestet blieb. Der Render-Schritt ist
/// injizierbar, damit Tests die Kette ohne echte Audio-Dateien fahren.
enum PlaybackSource {

    struct Resolved: Equatable {
        /// Abzuspielende Datei — Original oder gerenderte korrigierte Kopie.
        let url: URL
        /// Rate für den AVAudioPlayer (1, wenn die Korrektur über die Kopie lief).
        let rate: Float
        /// Lief eine Dauer-Korrektur (Kopie ODER Rate)? Steuert die "Auto ×"-Pille.
        let corrected: Bool
        /// Anzeigewert der Pille — die echte Korrektur-Rate, nicht der Floor.
        let displayRate: Float
    }

    /// Floor für den Rate-Fallback ohne gerenderte Kopie — `AVAudioPlayer`
    /// unterhalb von 0.5 ist praktisch unverständlich.
    static let minFallbackRate: Float = 0.5

    static func resolve(
        sourceURL: URL,
        fileDuration: TimeInterval,
        expectedDuration: TimeInterval,
        render: (URL, TimeInterval, Float) throws -> URL? = {
            try AudioPlaybackFileCorrector.renderCorrectedCopy(
                from: $0,
                expectedDuration: $1,
                correctionRate: $2
            )
        }
    ) -> Resolved {
        let decision = AudioPlaybackPitchGuard.decide(
            fileDuration: fileDuration,
            expectedDuration: expectedDuration
        )
        guard decision.corrected else {
            return Resolved(url: sourceURL, rate: 1, corrected: false, displayRate: 1)
        }

        do {
            if let correctedURL = try render(sourceURL, expectedDuration, decision.rate) {
                NSLog("[PlaybackSource] rendered playback correction \(decision.rate) for \(sourceURL.path) (\(decision.reason ?? "duration mismatch"))")
                return Resolved(url: correctedURL, rate: 1, corrected: true, displayRate: decision.rate)
            }
            let fallback = max(decision.rate, minFallbackRate)
            NSLog("[PlaybackSource] render correction unavailable; falling back to rate \(fallback) for \(sourceURL.path)")
            return Resolved(url: sourceURL, rate: fallback, corrected: true, displayRate: decision.rate)
        } catch {
            let fallback = max(decision.rate, minFallbackRate)
            NSLog("[PlaybackSource] render correction failed; falling back to rate \(fallback) for \(sourceURL.path): \(error)")
            return Resolved(url: sourceURL, rate: fallback, corrected: true, displayRate: decision.rate)
        }
    }
}
