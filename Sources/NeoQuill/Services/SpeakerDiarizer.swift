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
}
