import Foundation
import Combine
import AVFoundation

// Orchestrator für eine Live-Aufnahme:
// - PermissionGate prüft Mic/Audio.
// - AudioCapture liefert dual-stream Float-Chunks (Mic + System-Audio via ProcessTap).
// - LiveTranscriber (WhisperKit) verarbeitet Chunks → TranscriptSegments.
// - SpeakerDiarizer (FluidAudio) labelt Speaker auf dem System-Audio-Stream (Phase 4b).
// - LiveLines werden gepublished für RecordingView.
// - Auf Stop: finales Transcript wird in MeetingStore persistiert (Phase 4b).

@MainActor
final class RecordingController: ObservableObject {

    // MARK: - Published state für UI

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var liveLines: [TranscriptLine] = []
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var device: String = "Built-in Mic"
    @Published private(set) var modelLabel: String = "WhisperKit ANE"
    @Published private(set) var statusText: String = "Bereit"
    @Published private(set) var hasMicPermission: Bool = false

    // MARK: - Dependencies

    private let audioCapture = AudioCapture()
    private let transcriber = LiveTranscriber(modelName: "openai_whisper-tiny")
    private let permissions = PermissionGate()

    private var elapsedTimer: AnyCancellable?
    private var startedAt: Date?
    private var chunkOffset: TimeInterval = 0

    // MARK: - Lifecycle

    init() {
        wireTranscriber()
        wireAudioCapture()
        refreshPermissions()
    }

    func refreshPermissions() {
        permissions.refreshAll()
        hasMicPermission = permissions.canRecord
    }

    private func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        permissions.refreshMicrophone()
        hasMicPermission = granted
    }

    // MARK: - Public API

    func toggle() async {
        switch state {
        case .idle, .error:
            await start()
        case .recording:
            await stop()
        default:
            break
        }
    }

    func start() async {
        guard !state.isActive else { return }
        state = .preparing
        statusText = "Vorbereiten"

        refreshPermissions()
        if !hasMicPermission {
            await requestMicrophone()
            guard hasMicPermission else {
                state = .error(message: "Mikrofon-Zugriff fehlt — bitte in Systemeinstellungen erlauben.")
                statusText = "Permission fehlt"
                return
            }
        }

        // Modell laden — beim ersten Start lädt WhisperKit ggf. das CoreML-Modell.
        let loaded = await transcriber.loadModel()
        guard loaded else {
            state = .error(message: "WhisperKit-Modell konnte nicht geladen werden.")
            statusText = "Fehler"
            return
        }

        do {
            try await audioCapture.start()
            liveLines.removeAll()
            chunkOffset = 0
            startedAt = Date()
            state = .recording(startedAt: startedAt!)
            statusText = "Aufnahme läuft"
            startElapsedTimer()
        } catch {
            state = .error(message: "Audio-Capture fehlgeschlagen: \(error.localizedDescription)")
            statusText = "Fehler"
        }
    }

    func stop() async {
        guard state.isRecording else { return }
        state = .processing
        statusText = "Verarbeiten"
        stopElapsedTimer()
        await audioCapture.stop()

        // Phase 4b: finalen Mix → PostProcessor → MeetingStore.upsertDetail.
        // Erst mal nur sauberer Idle-Übergang.
        try? await Task.sleep(nanoseconds: 200_000_000)
        state = .idle
        statusText = "Bereit"
    }

    // MARK: - Internal wiring

    private func wireTranscriber() {
        transcriber.onSegment = { [weak self] segment in
            Task { @MainActor in
                guard let self else { return }
                let line = TranscriptLine(
                    who: "NK",
                    timestamp: Self.formatTimestamp(segment.start),
                    body: segment.text,
                    highlight: false
                )
                self.liveLines.append(line)
                if self.liveLines.count > 200 {
                    self.liveLines.removeFirst(self.liveLines.count - 200)
                }
            }
        }
    }

    private func wireAudioCapture() {
        audioCapture.onAudioChunk = { [weak self] samples in
            Task { @MainActor in
                guard let self, self.state.isRecording else { return }
                let offset = self.chunkOffset
                self.chunkOffset += Double(samples.count) / 16000.0
                self.transcriber.transcribe(audioData: samples, offset: offset)
            }
        }
    }

    private func startElapsedTimer() {
        elapsed = 0
        elapsedTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }

    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
