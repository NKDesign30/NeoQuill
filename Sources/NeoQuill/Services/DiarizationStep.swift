import Foundation

/// Der geteilte Diarization-Sub-Schritt der Persist- und Reprocess-Pipeline:
/// EIN Gate ("darf Diarization laufen?") und EINE Embedding-Sammlung.
///
/// Vorher existierte das Gate als zwei ungleich geformte Kopien in
/// `RecordingController.persistMeeting` und `reprocessMeetingAsync` — exakt die
/// ungetestete Wiring-Schicht, in der die historischen Speaker-Bugs saßen.
/// ADR-0002 bleibt unberührt: die vier Finalize-Schwänze teilen weiterhin kein
/// Skelett; nur dieser in beiden Pfaden wortgleich gemeinte Schritt ist
/// konzentriert. Das Diarisieren selbst (FluidAudio) bleibt beim Aufrufer.
enum DiarizationStep {

    /// Mindestlänge des System-Audio-Streams: 5 Sekunden bei 16 kHz. Kürzere
    /// Aufnahmen liefern keine belastbaren Speaker-Segmente.
    static let minimumSampleCount = 16_000 * 5

    /// Das EINE Diarization-Gate: Setting aktiv, Diarizer vorbereitet und
    /// genug System-Audio (strikt mehr als `minimumSampleCount` Samples).
    static func shouldRun(enabled: Bool, diarizerReady: Bool, sampleCount: Int) -> Bool {
        enabled && diarizerReady && sampleCount > minimumSampleCount
    }

    /// Sammelt pro Speaker-ID das Embedding des ERSTEN Segments — auch wenn es
    /// leer ist. Das ist bewusster Kontrakt: die Konsumenten
    /// (`SpeakerIdentityCoordinator.recordMeetingEmbeddings`, der
    /// `lastEmbeddings`-Cache) filtern leere Embeddings selbst; ein späteres
    /// Segment desselben Sprechers überschreibt das erste nie.
    static func collectEmbeddings(from segments: [DiarizedSpeakerSegment]) -> [String: [Float]] {
        var embeddings: [String: [Float]] = [:]
        for segment in segments where embeddings[segment.speakerId] == nil {
            embeddings[segment.speakerId] = segment.embedding
        }
        return embeddings
    }
}
