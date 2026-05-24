import Foundation
@preconcurrency import AVFoundation
import Combine

// Einmaliges Voice-ID Onboarding für den lokalen Sprecher (Niko/ME).
// Nimmt 8s Mic-Audio in 16 kHz Mono auf, extrahiert ein WeSpeaker-Embedding
// über FluidAudio und persistiert es im SpeakerStore unter LocalSpeakerProfile.id.
//
// Effekt: Diarizer matched zukünftige Mic-Stimme automatisch auf "ME" → in der
// UI steht direkt der echte Name statt "S1", auch wenn keine Plattform-Captions
// laufen.

@MainActor
final class VoiceIdEnrollmentService: ObservableObject {

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording(secondsRemaining: Double)
        case processing
        case saved
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Kurzes Mikropegel-Signal für eine Live-Anzeige (0...1).
    @Published private(set) var meterLevel: Float = 0

    /// Gesamte Aufnahmedauer in Sekunden.
    static let recordingDuration: TimeInterval = 8

    private let diarizer: SpeakerDiarizer
    private let speakerStore: SpeakerStore

    private var engine: AVAudioEngine?
    private var samples: [Float] = []
    private var countdownTask: Task<Void, Never>?

    init(diarizer: SpeakerDiarizer, speakerStore: SpeakerStore) {
        self.diarizer = diarizer
        self.speakerStore = speakerStore
    }

    /// Startet den Mic-Stream für `recordingDuration` Sekunden. Triggert
    /// Permission-Anfrage falls noetig. Resultat liegt am Ende in `phase`.
    func startEnrollment() async {
        guard phase != .recording(secondsRemaining: Self.recordingDuration), phase != .processing else { return }
        samples.removeAll(keepingCapacity: true)

        phase = .requestingPermission
        let granted = await requestPermission()
        guard granted else {
            phase = .failed("Mikrofon-Zugriff wurde verweigert. Bitte in den macOS-Systemeinstellungen → Datenschutz & Sicherheit → Mikrofon aktivieren.")
            return
        }

        do {
            try beginRecording()
        } catch {
            phase = .failed("Mikrofon konnte nicht gestartet werden: \(error.localizedDescription)")
            return
        }

        await runCountdown()
        stopEngine()

        phase = .processing
        await finalize()
    }

    /// Bricht eine laufende Aufnahme ab. Daten werden verworfen.
    func cancelEnrollment() {
        countdownTask?.cancel()
        countdownTask = nil
        stopEngine()
        samples.removeAll()
        if case .processing = phase { return } // processing nicht abreissen
        phase = .idle
    }

    // MARK: - Internal

    private func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { ok in cont.resume(returning: ok) }
            }
        @unknown default: return false
        }
    }

    private func beginRecording() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "VoiceIdEnrollment", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Ungültiges Audio-Format"])
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let chunk = Self.convertTo16kMono(buffer) else { return }
            let level = Self.peakLevel(chunk)
            Task { @MainActor [weak self] in
                self?.samples.append(contentsOf: chunk)
                self?.meterLevel = level
            }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func runCountdown() async {
        let total = Self.recordingDuration
        let started = Date()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started)
                let remaining = max(0, total - elapsed)
                await MainActor.run { self?.phase = .recording(secondsRemaining: remaining) }
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        await countdownTask?.value
        countdownTask = nil
    }

    private func stopEngine() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        meterLevel = 0
    }

    private func finalize() async {
        let captured = samples
        samples.removeAll()
        guard captured.count >= 16_000 * 3 else {
            phase = .failed("Aufnahme war zu kurz. Bitte sprich beim nächsten Versuch länger und lauter.")
            return
        }
        guard !diarizer.isReady ? await ensureDiarizerReady() : true else {
            phase = .failed("Sprach-Modelle konnten nicht geladen werden.")
            return
        }
        do {
            let embedding = try diarizer.embedding(for: captured)
            guard !embedding.isEmpty else {
                phase = .failed("Embedding-Extraktion lieferte leere Daten.")
                return
            }
            let name = LocalSpeakerProfile.displayName
            speakerStore.upsert(
                id: LocalSpeakerProfile.id,
                name: name,
                embedding: embedding,
                colorHex: LocalSpeakerProfile.colorHex
            )
            UserDefaults.standard.set(true, forKey: AppSettings.voiceIdEnrolled)
            phase = .saved
        } catch {
            phase = .failed("Embedding konnte nicht berechnet werden: \(error.localizedDescription)")
        }
    }

    private func ensureDiarizerReady() async -> Bool {
        await diarizer.warmUp()
        return diarizer.isReady
    }

    nonisolated private static func convertTo16kMono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        guard buffer.frameLength > 0,
              let converter = AVAudioConverter(from: buffer.format, to: target) else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outFrames > 0,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return nil }

        var hasData = true
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if hasData {
                hasData = false
                status.pointee = .haveData
                return buffer
            }
            status.pointee = .noDataNow
            return nil
        }
        guard error == nil, let channel = outBuffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
    }

    nonisolated private static func peakLevel(_ samples: [Float]) -> Float {
        var peak: Float = 0
        for s in samples {
            let abs = Swift.abs(s)
            if abs > peak { peak = abs }
        }
        return min(1, peak * 1.5)
    }
}

extension VoiceIdEnrollmentService {
    static var isEnrolled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.voiceIdEnrolled)
    }
}
