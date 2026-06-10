import Foundation
import AVFoundation
import FluidAudio

// On-Device Speaker-Diarization via FluidAudio (Pyannote Community-1 + WeSpeaker).
// Phase 1 (heute): Service-Skelett mit Init + Diarize + bekannte Speaker laden.
// Phase 2: Persistenz von Speaker-Embeddings (z.B. "Thorsten") in MeetingStore,
// Auto-Re-Identification bei zukünftigen Calls.
//
// Architektur für Teams-Calls:
//   - Mic-Stream (AVAudioEngine)            → lokale Stimme, kein Diarize nötig.
//   - Teams-Process-Audio (ProcessAudioTap) → Remote-Teilnehmer, hier diarisieren.

@MainActor
final class SpeakerDiarizer: ObservableObject {

    @Published private(set) var isReady: Bool = false
    @Published private(set) var lastError: String?

    private let manager = DiarizerManager()
    private var modelsLoaded = false

    func warmUp() async {
        guard !modelsLoaded else { return }
        do {
            let models = try await DiarizerModels.downloadIfNeeded()
            manager.initialize(models: consume models)
            modelsLoaded = true
            isReady = true
        } catch {
            lastError = "Diarizer-Modelle konnten nicht geladen werden: \(error.localizedDescription)"
            NSLog("[SpeakerDiarizer] download failed: \(error)")
        }
    }

    func loadKnownSpeakers(_ speakers: [Speaker]) async {
        guard modelsLoaded else { return }
        await manager.initializeKnownSpeakers(speakers)
    }

    /// Diarisiert einen Audio-Buffer und gibt die Speaker-Segmente zurück.
    /// `samples` muss 16kHz Mono sein — Resampling übernimmt der Aufrufer (AudioCapture).
    func diarize(_ samples: [Float], at startOffset: TimeInterval = 0) async throws -> DiarizationResult {
        guard modelsLoaded else { throw DiarizerError.notInitialized }
        return try await manager.performCompleteDiarization(samples, sampleRate: 16_000, atTime: startOffset)
    }

    /// Single-Speaker-Embedding extrahieren — z.B. um einen Speaker zu labeln.
    func embedding(for samples: [Float]) throws -> [Float] {
        try manager.extractSpeakerEmbedding(from: samples)
    }

    // MARK: - Resolution (das eigentliche Pipeline-Interface)

    /// Diarisiert und LÖST die Segmente auf: Schnipsel unter
    /// `minSegmentDuration` fliegen raus, bekannte Stimmen werden über den
    /// injizierten `matcher` benannt (Re-ID), anonyme FluidAudio-IDs auf das
    /// S1/S2-Schema der UI normalisiert. Fehler werden geloggt und als leere
    /// Liste gemeldet — Diarization ist Best-Effort, nie Pipeline-Blocker.
    ///
    /// Die Regeln selbst sind pure `static`s — testbar ohne Modelle/Hardware.
    /// Vorher lagen sie als private Methoden im RecordingController und waren
    /// nur mit echten FluidAudio-Modellen erreichbar.
    func resolveSegments(
        _ samples: [Float],
        matcher: ([Float]) -> (id: String, score: Float)?
    ) async -> [DiarizedSpeakerSegment] {
        do {
            let result = try await diarize(samples)
            return result.segments.compactMap { seg in
                Self.resolveSegment(
                    start: TimeInterval(seg.startTimeSeconds),
                    end: TimeInterval(seg.endTimeSeconds),
                    rawSpeakerId: seg.speakerId,
                    embedding: seg.embedding,
                    matcher: matcher
                )
            }
        } catch {
            NSLog("[SpeakerDiarizer] diarize failed: \(error)")
            return []
        }
    }

    /// Minimale Segmentdauer — kürzere Schnipsel sind fast immer Atem,
    /// Übersprechen oder Raumklang und würden Speaker-Wechsel vortäuschen.
    nonisolated static let minSegmentDuration: TimeInterval = 1.2

    /// Konfidenz für anonym aufgelöste Segmente (keine bekannte Stimme).
    nonisolated static let anonymousConfidence: Double = 0.72

    /// Löst EIN Diarization-Segment auf. `nil` = verworfen (zu kurz).
    nonisolated static func resolveSegment(
        start: TimeInterval,
        end: TimeInterval,
        rawSpeakerId: String,
        embedding: [Float],
        matcher: ([Float]) -> (id: String, score: Float)?
    ) -> DiarizedSpeakerSegment? {
        guard end - start >= minSegmentDuration else { return nil }
        if let match = matcher(embedding) {
            return DiarizedSpeakerSegment(
                start: start,
                end: end,
                speakerId: match.id,
                embedding: embedding,
                speakerSource: .knownVoice,
                confidence: Double(match.score)
            )
        }
        return DiarizedSpeakerSegment(
            start: start,
            end: end,
            speakerId: displaySpeakerId(for: rawSpeakerId),
            embedding: embedding,
            speakerSource: .diarization,
            confidence: anonymousConfidence
        )
    }

    /// Normalisiert FluidAudio-Speaker-IDs ("0", "Speaker 1", "spk2") auf das
    /// S1/S2-Schema, das UI und SpeakerPalette sprechen.
    nonisolated static func displaySpeakerId(for rawId: String) -> String {
        let trimmed = rawId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "S1" }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("S"), upper.dropFirst().allSatisfy(\.isNumber) { return upper }
        if let numeric = Int(trimmed) { return "S\(numeric + 1)" }
        let trailingDigits = String(trimmed.reversed().prefix { $0.isNumber }.reversed())
        if let numeric = Int(trailingDigits) { return "S\(numeric + 1)" }
        return upper.count <= 3 ? upper : "S1"
    }
}
