import Foundation
import AVFoundation
import CoreAudio
import CoreMedia
import Combine
import os.log

private let logger = Logger(subsystem: "com.neon.neoquill", category: "AudioCapture")

/// Persistentes File-Log (macOS filtert os_log weg)
private func diagLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/meeting-scribe/meetings/quill-diag.log")
    if let handle = try? FileHandle(forWritingTo: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath.path, contents: line.data(using: .utf8))
    }
}

/// Dual-Stream Audio-Capture: Process Tap (Remote-Teilnehmer) + Mic (eigene Stimme)
///
/// Architektur:
/// - CoreAudio Process Tap → Audio direkt vom Output-Stream der Call-App (Teams/Zoom/etc.)
/// - AVCaptureSession → USB/Built-in Mic (eigene Stimme)
/// - Keine ScreenCaptureKit, kein BlackHole, keine Bildschirmaufnahme-Berechtigung
/// - Einmalige "System Audio Recording" Permission, resettet nicht
@MainActor
final class AudioCapture: NSObject, ObservableObject {
    @Published var isCapturing = false
    @Published var audioLevel: Float = 0
    @Published var hasSystemAudio = false
    @Published var audioTooQuiet: Bool = false
    @Published var systemAudioTooQuiet: Bool = false

    // Mic Capture
    private var micSession: AVCaptureSession?
    private let micOutputQueue = DispatchQueue(label: "com.quill.mic-capture", qos: .userInitiated)
    nonisolated(unsafe) var micCallbackCount: Int = 0
    nonisolated(unsafe) var micConverter: AVAudioConverter?
    private let micTargetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    // Process Tap (System Audio) — Primary
    private var processTap: ProcessAudioTap?
    // SCK Fallback (System Audio) — wenn Process Tap keine Samples liefert
    private var sckCapture: SCKAudioCapture?
    private var tapFallbackTimer: Timer?
    @Published var captureMode: String = ""  // "ProcessTap", "SCK", "Mic-only"

    // Chunk-Buffer fuer Live-Transcription (werden periodisch geleert)
    private var micBuffer: [Float] = []
    private var sysBuffer: [Float] = []
    // Vollstaendige Aufnahme-Buffer (werden NIE geleert, nur beim Mix am Ende)
    private var micRecording: [Float] = []
    private var sysRecording: [Float] = []
    private var lastLevelUpdate: Date = .distantPast
    private var lastDebugLog: Date = .distantPast
    private var nonZeroSamplesTotal = 0

    // RMS-Akkumulatoren für Level-Guard (Evaluierung alle 5 Sekunden)
    private var micRmsAccum: Float = 0
    private var micRmsSampleCount: Int = 0
    private var tapRmsAccum: Float = 0
    private var tapRmsSampleCount: Int = 0
    private var lastLevelGuardCheck: Date = .distantPast
    private let levelGuardInterval: TimeInterval = 5.0
    private let levelGuardWarmupSamples = 3 * 16000  // 3 Sekunden bei 16kHz
    private let quietThreshold: Float = 0.001

    /// Callback wenn genuegend Audio fuer Transkription gesammelt
    var onAudioChunk: (([Float]) -> Void)?

    private let minChunkSamples = 2 * 16000
    private let maxChunkSamples = 8 * 16000
    private var chunkTimer: Timer?

    /// Bundle IDs der aktiven Call-App
    var targetBundleIds: [String] = []

    // MARK: - Permission

    private func requestMicPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            logger.warning("Mic Permission: \(granted ? "GRANTED" : "DENIED", privacy: .public)")
            return granted
        case .denied, .restricted:
            logger.error("Mic Permission DENIED")
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Start / Stop

    func start() async throws {
        guard !isCapturing else { return }

        micBuffer = []
        sysBuffer = []
        micRecording = []
        sysRecording = []
        micRmsAccum = 0
        micRmsSampleCount = 0
        tapRmsAccum = 0
        tapRmsSampleCount = 0
        lastLevelGuardCheck = .distantPast
        audioTooQuiet = false
        systemAudioTooQuiet = false

        let micGranted = await requestMicPermission()

        // 1. System Audio via CoreAudio Process Tap
        do {
            try startProcessTap()
        } catch {
            logger.error("ProcessTap fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }

        // 2. Mikrofon (eigene Stimme)
        if micGranted {
            try startMicCapture()
        } else {
            logger.error("Mikrofon verweigert")
        }

        isCapturing = true

        chunkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushChunk()
            }
        }

        let mode = hasSystemAudio && micGranted ? "Dual-Stream (ProcessTap + Mic)" :
                   hasSystemAudio ? "Nur System-Audio" :
                   micGranted ? "Nur Mikrofon" : "KEIN Audio!"
        captureMode = hasSystemAudio ? "ProcessTap" : "Mic-only"
        logger.warning("Audio-Capture gestartet: \(mode, privacy: .public)")
        diagLog("START: \(mode), bundleIds=\(targetBundleIds), hasSystemAudio=\(hasSystemAudio)")

        // Fallback-Check: Wenn Process Tap nach 5s keine Samples → SCK starten
        if hasSystemAudio {
            tapFallbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.checkTapFallback()
                }
            }
        }
    }

    func startSystemAudioLate() async {
        guard isCapturing, !hasSystemAudio else { return }
        do {
            try startProcessTap()
        } catch {
            logger.error("ProcessTap Late-Start fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Prüft ob Process Tap Samples liefert, sonst Fallback auf SCK
    private func checkTapFallback() {
        let tapSamples = sysRecording.count
        diagLog("FALLBACK CHECK: tap=\(tapSamples) samples after 5s")

        if tapSamples == 0 {
            diagLog("TAP DEAD — 0 samples after 5s, switching to SCK fallback")
            logger.warning("ProcessTap liefert keine Daten — Fallback auf ScreenCaptureKit")

            // Process Tap stoppen
            processTap?.stop()
            processTap = nil

            // SCK starten
            let sck = SCKAudioCapture()
            sck.onSamples = { [weak self] samples in
                Task { @MainActor in
                    self?.appendAudio(samples, source: "Tap")
                }
            }
            sckCapture = sck
            Task {
                do {
                    try await sck.start(bundleIdentifiers: targetBundleIds)
                    await MainActor.run {
                        self.hasSystemAudio = true
                        self.captureMode = "SCK"
                        diagLog("SCK STARTED: bundleIds=\(self.targetBundleIds)")
                    }
                } catch {
                    await MainActor.run {
                        self.hasSystemAudio = false
                        self.captureMode = "Mic-only"
                        diagLog("SCK FAILED: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            diagLog("TAP OK: \(tapSamples) samples after 5s — keeping ProcessTap")
        }
    }

    func stop() async {
        chunkTimer?.invalidate()
        chunkTimer = nil
        tapFallbackTimer?.invalidate()
        tapFallbackTimer = nil

        processTap?.stop()
        processTap = nil

        if let sck = sckCapture {
            await sck.stop()
            sckCapture = nil
        }

        micSession?.stopRunning()
        micSession = nil
        micConverter = nil

        flushChunk(force: true)

        let micSec = micRecording.count / 16000
        let sysSec = sysRecording.count / 16000
        let micRmsTotal = micRecording.isEmpty ? Float(0) : sqrt(micRecording.reduce(Float(0)) { $0 + $1 * $1 } / Float(micRecording.count))
        let tapRmsTotal = sysRecording.isEmpty ? Float(0) : sqrt(sysRecording.reduce(Float(0)) { $0 + $1 * $1 } / Float(sysRecording.count))
        logger.warning("Audio-Capture gestoppt. Mic: \(self.micRecording.count, privacy: .public) (\(micSec, privacy: .public)s), Tap: \(self.sysRecording.count, privacy: .public) (\(sysSec, privacy: .public)s), nonZero: \(self.nonZeroSamplesTotal, privacy: .public)")
        diagLog("STOP: Mic=\(micRecording.count) samples (\(micSec)s, rms=\(String(format: "%.6f", micRmsTotal))), Tap=\(sysRecording.count) samples (\(sysSec)s, rms=\(String(format: "%.6f", tapRmsTotal))), nonZero=\(nonZeroSamplesTotal)")
        isCapturing = false
        hasSystemAudio = false
        nonZeroSamplesTotal = 0
        audioTooQuiet = false
        systemAudioTooQuiet = false
    }

    func getRecordedAudio() -> [Float] {
        return getMixedAudio()
    }

    // MARK: - Process Tap (System Audio)

    private func startProcessTap() throws {
        let tap = ProcessAudioTap()
        tap.onSamples = { [weak self] samples in
            Task { @MainActor in
                self?.appendAudio(samples, source: "Tap")
            }
        }

        try tap.start(bundleIdentifiers: targetBundleIds)
        processTap = tap
        hasSystemAudio = true
    }

    // MARK: - Mikrofon (AVFoundation)

    private func startMicCapture() throws {
        let session = AVCaptureSession()

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        let allMics = discoverySession.devices
        logger.warning("Verfuegbare Mics: \(allMics.map { "\($0.localizedName)" }, privacy: .public)")

        // USB-Mic > Built-in > Default (BlackHole/Virtual NICHT als Mic!)
        let mic = allMics.first {
            ($0.localizedName.contains("USB") || $0.localizedName.contains("PodMic")
             || $0.localizedName.contains("Yeti") || $0.localizedName.contains("Scarlett")
             || $0.localizedName.contains("Focusrite") || $0.localizedName.contains("NT-USB"))
            && !$0.localizedName.contains("BlackHole")
            && !$0.localizedName.contains("Virtual")
        }
        ?? allMics.first { $0.localizedName.contains("MacBook") || $0.localizedName.contains("Built") }
        ?? allMics.first { !$0.localizedName.contains("BlackHole") && !$0.localizedName.contains("Virtual") }

        guard let mic = mic else {
            logger.error("Kein Mikrofon gefunden!")
            throw CaptureError.formatError
        }

        logger.warning("Mic gewaehlt: \(mic.localizedName, privacy: .public)")

        let input = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(input) else { throw CaptureError.formatError }
        session.addInput(input)

        let audioOutput = AVCaptureAudioDataOutput()
        guard session.canAddOutput(audioOutput) else { throw CaptureError.formatError }
        session.addOutput(audioOutput)

        micCallbackCount = 0
        audioOutput.setSampleBufferDelegate(self, queue: micOutputQueue)

        session.startRunning()
        micSession = session
        logger.warning("Mic-Capture gestartet (\(mic.localizedName, privacy: .public))")
    }

    // MARK: - Buffer Management

    fileprivate func appendAudio(_ samples: [Float], source: String) {
        guard !samples.isEmpty else { return }

        let nonZero = samples.contains { $0 != 0.0 }
        if source == "Tap" {
            sysBuffer.append(contentsOf: samples)
            sysRecording.append(contentsOf: samples)
        } else {
            micBuffer.append(contentsOf: samples)
            micRecording.append(contentsOf: samples)
        }
        if nonZero { nonZeroSamplesTotal += samples.count }

        // RMS-Akkumulation für Level-Guard
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        if source == "Tap" {
            tapRmsAccum += sumSquares
            tapRmsSampleCount += samples.count
        } else {
            micRmsAccum += sumSquares
            micRmsSampleCount += samples.count
        }

        let now = Date()
        if now.timeIntervalSince(lastDebugLog) > 5.0 {
            lastDebugLog = now
            let micSec = micRecording.count / 16000
            let sysSec = sysRecording.count / 16000
            let rms = sqrt(sumSquares / Float(max(samples.count, 1)))
            let maxVal = samples.map { abs($0) }.max() ?? 0
            logger.warning("Mic: \(self.micRecording.count, privacy: .public) (\(micSec, privacy: .public)s), Tap: \(self.sysRecording.count, privacy: .public) (\(sysSec, privacy: .public)s), src=\(source, privacy: .public), rms=\(String(format: "%.6f", rms), privacy: .public), max=\(String(format: "%.6f", maxVal), privacy: .public)")
            // File-Log alle 30s für Diagnose
            if (micSec + sysSec) % 30 < 6 {
                diagLog("LIVE [\(micSec + sysSec)s]: src=\(source), rms=\(String(format: "%.6f", rms)), max=\(String(format: "%.6f", maxVal)), mic=\(micSec)s, tap=\(sysSec)s, quiet=\(audioTooQuiet)/\(systemAudioTooQuiet)")
            }
        }

        // Level-Guard: alle 5 Sekunden auswerten (erst nach Warmup-Phase)
        if now.timeIntervalSince(lastLevelGuardCheck) >= levelGuardInterval {
            lastLevelGuardCheck = now

            if micRmsSampleCount >= levelGuardWarmupSamples {
                let micRms = sqrt(micRmsAccum / Float(micRmsSampleCount))
                audioTooQuiet = micRms < quietThreshold
            }

            if tapRmsSampleCount >= levelGuardWarmupSamples {
                let tapRms = sqrt(tapRmsAccum / Float(tapRmsSampleCount))
                systemAudioTooQuiet = tapRms < quietThreshold
            }

            // Akkumulatoren für nächstes Fenster zurücksetzen
            micRmsAccum = 0
            micRmsSampleCount = 0
            tapRmsAccum = 0
            tapRmsSampleCount = 0
        }

        guard now.timeIntervalSince(lastLevelUpdate) > 0.1 else { return }
        lastLevelUpdate = now
        audioLevel = sqrt(sumSquares / Float(max(samples.count, 1)))
    }

    /// Snapshot der bisherigen Recording-Buffer ohne sie zu leeren.
    /// Nach `stop()` aufrufen, um finales Transkript + Diarization zu bauen.
    func collectFinalAudio() -> (mic: [Float], sys: [Float], mixed: [Float]) {
        let mic = micRecording
        let sys = sysRecording
        let mixed = getMixedAudio()
        return (mic, sys, mixed)
    }

    /// Buffer leeren (vor neuer Aufnahme).
    func clearRecording() {
        micRecording.removeAll()
        sysRecording.removeAll()
        micBuffer.removeAll()
        sysBuffer.removeAll()
    }

    private func getMixedAudio() -> [Float] {
        let length = max(micRecording.count, sysRecording.count)
        guard length > 0 else { return [] }

        var mixed = [Float](repeating: 0, count: length)
        for i in 0..<micRecording.count { mixed[i] = micRecording[i] }
        for i in 0..<sysRecording.count { mixed[i] += sysRecording[i] }

        // Peak-Limiter: Spikes hart clippen statt globale Normalisierung.
        // Alte Methode skalierte ALLES runter wenn ein einziger Spike existierte,
        // was Meetings auf -50 dB drückte und Transkription unmöglich machte.
        for i in 0..<mixed.count {
            mixed[i] = min(max(mixed[i], -0.95), 0.95)
        }

        return mixed
    }

    private func flushChunk(force: Bool = false) {
        let count = micBuffer.count
        guard count >= minChunkSamples || (force && count > 0) else { return }

        let chunkSize = min(count, maxChunkSamples)
        let chunk = Array(micBuffer.prefix(chunkSize))
        micBuffer.removeFirst(chunkSize)
        let sysRemove = min(chunkSize, sysBuffer.count)
        if sysRemove > 0 { sysBuffer.removeFirst(sysRemove) }

        onAudioChunk?(chunk)
    }
}

// MARK: - AVCaptureAudioDataOutput Delegate (Mikrofon)

extension AudioCapture: AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard sampleBuffer.isValid else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = formatDesc.audioStreamBasicDescription else { return }
        guard asbd.mSampleRate > 0 else { return }

        guard let sourceFormat = AVAudioFormat(
            standardFormatWithSampleRate: asbd.mSampleRate,
            channels: asbd.mChannelsPerFrame
        ) else { return }

        var pcmBuffer: AVAudioPCMBuffer?
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                bufferListNoCopy: audioBufferList.unsafePointer
            )
        }
        guard let pcmBuffer = pcmBuffer else { return }

        if self.micConverter == nil {
            self.micConverter = AVAudioConverter(from: sourceFormat, to: self.micTargetFormat)
        }
        guard let converter = self.micConverter else { return }

        let ratio = self.micTargetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: self.micTargetFormat,
            frameCapacity: outputFrameCount
        ) else { return }

        var error: NSError?
        var hasData = true
        converter.reset()

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return pcmBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        guard error == nil,
              let channelData = outputBuffer.floatChannelData,
              outputBuffer.frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
        guard !samples.isEmpty else { return }

        self.micCallbackCount += 1
        if self.micCallbackCount <= 5 {
            let maxVal = samples.map { abs($0) }.max() ?? 0
            let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
            logger.warning("Mic #\(self.micCallbackCount): \(samples.count) samples, max=\(String(format: "%.6f", maxVal), privacy: .public), rms=\(String(format: "%.6f", rms), privacy: .public)")
        }

        Task { @MainActor in
            self.appendAudio(samples, source: "Mic")
        }
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplay
    case noOutputDevice
    case formatError
    case permissionDenied
    case processNotFound

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Kein Display gefunden"
        case .noOutputDevice: return "Kein Audio-Output-Device gefunden"
        case .formatError: return "Audio-Format Fehler"
        case .permissionDenied: return "Audio-Berechtigung fehlt"
        case .processNotFound: return "Call-App Prozess nicht gefunden"
        }
    }
}
