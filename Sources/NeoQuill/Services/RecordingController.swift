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
    private let transcriber = LiveTranscriber()
    private let permissions = PermissionGate()
    private let diarizer = SpeakerDiarizer()
    weak var store: MeetingStore?

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

        // Modell + Sprache aus Settings, sonst Defaults.
        let model = UserDefaults.standard.stringOr(AppSettings.whisperModel, default: "openai_whisper-tiny")
        let lang  = UserDefaults.standard.stringOr(AppSettings.language,     default: "de")
        let loaded = await transcriber.loadModel(model: model, language: lang)
        guard loaded else {
            state = .error(message: "WhisperKit-Modell konnte nicht geladen werden.")
            statusText = "Fehler"
            return
        }
        modelLabel = friendlyModelLabel(model)

        // Diarization warm-up nur wenn aktiviert (lädt ~140 MB beim ersten Mal)
        if UserDefaults.standard.boolOr(AppSettings.speakerDiarization, default: false) {
            await diarizer.warmUp()
        }

        do {
            audioCapture.clearRecording()
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

        let snapshot = liveLines
        let runtime = elapsed
        let started = startedAt ?? Date()
        await persistMeeting(lines: snapshot, runtime: runtime, started: started)

        state = .idle
        statusText = "Bereit"
    }

    private func persistMeeting(lines: [TranscriptLine], runtime: TimeInterval, started: Date) async {
        guard let store else { return }
        let title = generateTitle(from: lines, started: started)
        let id = "rec-\(Int(started.timeIntervalSince1970))"
        let durationShort = formatDurationShort(runtime)
        let timeShort = Self.timeFormatter.string(from: started)
        let dateShort = Self.dateShortFormatter.string(from: started)
        let dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        let timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"
        let wordCount = lines.reduce(0) { $0 + $1.body.split(separator: " ").count }
        let group = "Diesen Monat"

        let participants: [Participant] = [
            .init(id: "NK", name: "Niko Knez", role: "NK Design", colorHex: 0x2EAB73, spoke: durationShort)
        ]

        let summary = MeetingSummary(
            id: id, title: title, date: dateShort, time: timeShort,
            duration: durationShort, platform: .call, wordCount: wordCount,
            group: group, participantIds: ["NK"], unread: true
        )

        let detail = MeetingDetail(
            id: id,
            title: title,
            dateLong: dateLong,
            timeRange: timeRange,
            duration: durationShort,
            platform: .call,
            wordCount: wordCount,
            participants: participants,
            tldr: lines.first.map { String($0.body.prefix(220)) }
                ?? "Aufnahme ohne erkanntes Sprach-Material.",
            highlights: [],
            tasks: [],
            chapters: [],
            transcript: lines
        )

        store.insert(summary: summary, detail: detail)
    }

    private func generateTitle(from lines: [TranscriptLine], started: Date) -> String {
        if let first = lines.first?.body, !first.isEmpty {
            let prefix = first.split(separator: " ").prefix(7).joined(separator: " ")
            return prefix
        }
        return "Aufnahme \(Self.timeFormatter.string(from: started))"
    }

    private func formatDurationShort(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        if minutes == 0 { return "\(remainder)s" }
        return "\(minutes)m \(remainder)s"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd. MMM."
        return f
    }()

    private static let dateLongFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd. MMMM"
        return f
    }()

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

    private func friendlyModelLabel(_ raw: String) -> String {
        switch raw {
        case "openai_whisper-tiny":   return "Whisper Tiny"
        case "openai_whisper-base":   return "Whisper Base"
        case "openai_whisper-small":  return "Whisper Small"
        case "openai_whisper-medium": return "Whisper Medium"
        default: return raw
        }
    }
}
