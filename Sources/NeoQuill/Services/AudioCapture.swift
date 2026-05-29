import Foundation
@preconcurrency import AVFoundation
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
    /// Echter Name des Mics das gerade läuft — für UI-Header (`Built-in Mic` ist hardcoded raus).
    @Published var currentMicName: String = ""

    // Mic Capture
    private var micSession: AVCaptureSession?
    private var micOutput: AVCaptureAudioDataOutput?
    private var micEngine: AVAudioEngine?
    private var micFallbackTimer: Timer?
    private let micOutputQueue = DispatchQueue(label: "com.quill.mic-capture", qos: .userInitiated)
    nonisolated(unsafe) var micCallbackCount: Int = 0
    nonisolated(unsafe) var micConverter: AVAudioConverter?
    /// 48 kHz mono converter for the high-resolution archive path. The AVCapture
    /// delegate and the AVAudioEngine fallback never run at the same time (the
    /// fallback replaces the delegate), so one shared converter is safe.
    nonisolated(unsafe) var micHQConverter = PCMStreamConverter(targetSampleRate: 48_000)
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
    // High-resolution 48 kHz mono stems for the playback/export archive.
    // Kept separate from the 16 kHz ASR buffers above so the ASR/diarization
    // input stays byte-identical to before.
    private var micRecordingHQ: [Float] = []
    private var sysRecordingHQ: [Float] = []
    // Start time of the recording and the per-source offset of the first HQ
    // sample. The mic and system sources start at different times (the mic often
    // falls back to AVAudioEngine a few seconds in), so without this the later
    // source would be aligned to index 0 and play time-shifted. We pad each HQ
    // stem at the front by its offset to keep mic and system in sync.
    private var hqStartTime: Date?
    private var micHQStartOffset: TimeInterval?
    private var sysHQStartOffset: TimeInterval?
    private let hqSampleRate: Double = 48_000
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

    /// Callback fuer Mic-Chunks (eigene Stimme → lokaler Speaker).
    var onMicChunk: (([Float]) -> Void)?
    /// Callback fuer System-Audio-Chunks (Remote-Teilnehmer via ProcessTap → Speaker S1).
    /// Vorher: System-Audio wurde nur akkumuliert und beim Stop gemixt — Live-Transkript
    /// hatte deshalb nie die Teams-Stimme.
    var onSysChunk: (([Float]) -> Void)?

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
        micRecordingHQ = []
        sysRecordingHQ = []
        hqStartTime = Date()
        micHQStartOffset = nil
        sysHQStartOffset = nil
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
        if micGranted {
            micFallbackTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.checkMicFallback()
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
            sck.onSamplesHQ = { [weak self] hq in
                Task { @MainActor in
                    self?.appendAudioHQ(hq, source: "Tap")
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

    /// AVCapture liefert bei manchen Teams/RØDE-Konstellationen nur die ersten
    /// Frames und verstummt dann. Dann greifen wir auf AVAudioEngine Default-Input
    /// zurück, statt am Ende einen leeren Mic-Stem zu speichern.
    private func checkMicFallback() {
        guard isCapturing else { return }
        let micSamples = micRecording.count
        diagLog("MIC FALLBACK CHECK: mic=\(micSamples) samples after 4s")
        guard micSamples < 8_000 else {
            diagLog("MIC OK: \(micSamples) samples after 4s — keeping AVCapture")
            return
        }

        logger.warning("Mic-Capture liefert kaum Daten — Fallback auf AVAudioEngine")
        diagLog("MIC DEAD — switching to AVAudioEngine fallback")
        micSession?.stopRunning()
        micSession = nil
        micOutput = nil
        micConverter = nil

        do {
            try startMicEngineFallback()
        } catch {
            logger.error("AVAudioEngine Mic-Fallback fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            diagLog("MIC ENGINE FAILED: \(error.localizedDescription)")
        }
    }

    func stop() async {
        chunkTimer?.invalidate()
        chunkTimer = nil
        tapFallbackTimer?.invalidate()
        tapFallbackTimer = nil
        micFallbackTimer?.invalidate()
        micFallbackTimer = nil

        processTap?.stop()
        processTap = nil

        if let sck = sckCapture {
            await sck.stop()
            sckCapture = nil
        }

        micSession?.stopRunning()
        micSession = nil
        micOutput = nil
        micConverter = nil
        micEngine?.inputNode.removeTap(onBus: 0)
        micEngine?.stop()
        micEngine = nil

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
        tap.onSamplesHQ = { [weak self] hq in
            Task { @MainActor in
                self?.appendAudioHQ(hq, source: "Tap")
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

        // 1. Bevorzugt: User-Wahl aus Settings (UniqueID)
        let preferredId = UserDefaults.standard.string(forKey: "mic_device_id") ?? ""
        let userChoice = preferredId.isEmpty ? nil : allMics.first { $0.uniqueID == preferredId }

        // 2. USB-Mic > Built-in > Default (BlackHole/Virtual NICHT als Mic!)
        let mic = userChoice
            ?? allMics.first {
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

        currentMicName = mic.localizedName

        let audioOutput = AVCaptureAudioDataOutput()
        guard session.canAddOutput(audioOutput) else { throw CaptureError.formatError }
        session.addOutput(audioOutput)

        micCallbackCount = 0
        audioOutput.setSampleBufferDelegate(self, queue: micOutputQueue)

        session.startRunning()
        micSession = session
        micOutput = audioOutput
        logger.warning("Mic-Capture gestartet (\(mic.localizedName, privacy: .public))")
    }

    private func startMicEngineFallback() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw CaptureError.formatError
        }

        input.installTap(onBus: 0, bufferSize: 2048, format: sourceFormat) { buffer, _ in
            if let samples = Self.convertTo16kMono(buffer) {
                Task { @MainActor in
                    self.appendAudio(samples, source: "Mic")
                }
            }
            if let hq = self.micHQConverter?.convert(buffer), !hq.isEmpty {
                Task { @MainActor in
                    self.appendAudioHQ(hq, source: "Mic")
                }
            }
        }
        engine.prepare()
        try engine.start()
        micEngine = engine
        currentMicName = currentMicName.isEmpty ? "System-Mikrofon" : "\(currentMicName) · Engine"
        logger.warning("Mic-Fallback AVAudioEngine gestartet: \(sourceFormat, privacy: .public)")
        diagLog("MIC ENGINE STARTED: format=\(sourceFormat)")
    }

    nonisolated private static func convertTo16kMono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        guard buffer.frameLength > 0,
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0,
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount)
        else { return nil }

        var error: NSError?
        var hasData = true
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                hasData = false
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        guard error == nil,
              let channel = outputBuffer.floatChannelData?[0],
              outputBuffer.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
    }

    // MARK: - Buffer Management

    fileprivate func appendAudio(_ samples: [Float], source: String) {
        guard !samples.isEmpty else { return }

        // NaN/Inf rauswerfen — sonst bricht der RMS-Akkumulator (Mic=NaN im Diag-Log)
        // und WhisperKit kriegt vergiftete Buffer.
        let cleaned: [Float] = samples.map { sample in
            guard sample.isFinite else { return 0 }
            return min(max(sample, -1), 1)
        }

        let nonZero = cleaned.contains { $0 != 0.0 }
        if source == "Tap" {
            sysBuffer.append(contentsOf: cleaned)
            sysRecording.append(contentsOf: cleaned)
        } else {
            micBuffer.append(contentsOf: cleaned)
            micRecording.append(contentsOf: cleaned)
        }
        if nonZero { nonZeroSamplesTotal += cleaned.count }

        // RMS-Akkumulation für Level-Guard — auf cleaned[] damit NaN den Akku nicht killt.
        let sumSquares = cleaned.reduce(Float(0)) { $0 + $1 * $1 }
        if source == "Tap" {
            tapRmsAccum += sumSquares
            tapRmsSampleCount += cleaned.count
        } else {
            micRmsAccum += sumSquares
            micRmsSampleCount += cleaned.count
        }

        let now = Date()
        if now.timeIntervalSince(lastDebugLog) > 5.0 {
            lastDebugLog = now
            let micSec = micRecording.count / 16000
            let sysSec = sysRecording.count / 16000
            let rms = sqrt(sumSquares / Float(max(cleaned.count, 1)))
            let maxVal = cleaned.map { abs($0) }.max() ?? 0
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
        audioLevel = sqrt(sumSquares / Float(max(cleaned.count, 1)))
    }

    /// Appends 48 kHz mono samples to the high-resolution archive stems. Separate
    /// from `appendAudio` so the 16 kHz ASR buffers are never touched by this path.
    /// Records each source's first-sample offset so the stems can be time-aligned.
    fileprivate func appendAudioHQ(_ samples: [Float], source: String) {
        guard !samples.isEmpty else { return }
        let cleaned: [Float] = samples.map { $0.isFinite ? min(max($0, -1), 1) : 0 }
        let offset = hqStartTime.map { Date().timeIntervalSince($0) }
        if source == "Tap" {
            if sysHQStartOffset == nil { sysHQStartOffset = offset }
            sysRecordingHQ.append(contentsOf: cleaned)
        } else {
            if micHQStartOffset == nil { micHQStartOffset = offset }
            micRecordingHQ.append(contentsOf: cleaned)
        }
    }

    /// Snapshot der bisherigen Recording-Buffer ohne sie zu leeren.
    /// Nach `stop()` aufrufen, um finales Transkript + Diarization zu bauen.
    func collectFinalAudio() -> (mic: [Float], sys: [Float], mixed: [Float]) {
        let mic = micRecording
        let sys = sysRecording
        let mixed = getMixedAudio()
        return (mic, sys, mixed)
    }

    /// Snapshot of the high-resolution 48 kHz mono stems (mic + system) for the
    /// stereo playback/export archive, time-aligned so both start at the recording
    /// start. Each stem is front-padded with silence by its own first-sample
    /// offset, so a source that started late (e.g. the mic falling back to
    /// AVAudioEngine a few seconds in) no longer plays time-shifted against the
    /// other. Empty arrays if no HQ samples were produced (caller falls back to
    /// the 16 kHz mix).
    func collectFinalAudioHQ() -> (micHQ: [Float], sysHQ: [Float]) {
        let mic = Self.frontPadded(micRecordingHQ, offset: micHQStartOffset, sampleRate: hqSampleRate)
        let sys = Self.frontPadded(sysRecordingHQ, offset: sysHQStartOffset, sampleRate: hqSampleRate)
        return (mic, sys)
    }

    /// Prepends `offset` seconds of silence so stems captured with different start
    /// times line up on a common timeline. Caps the padding defensively so a
    /// clock glitch can never allocate an absurd buffer. Internal for testing.
    nonisolated static func frontPadded(_ samples: [Float], offset: TimeInterval?, sampleRate: Double) -> [Float] {
        guard !samples.isEmpty, let offset, offset > 0.01, offset.isFinite else { return samples }
        let padFrames = min(Int(offset * sampleRate), Int(sampleRate * 600))  // <= 10 min guard
        guard padFrames > 0 else { return samples }
        return [Float](repeating: 0, count: padFrames) + samples
    }

    /// Buffer leeren (vor neuer Aufnahme).
    func clearRecording() {
        micRecording.removeAll()
        sysRecording.removeAll()
        micRecordingHQ.removeAll()
        sysRecordingHQ.removeAll()
        micHQStartOffset = nil
        sysHQStartOffset = nil
        micBuffer.removeAll()
        sysBuffer.removeAll()
    }

    private func getMixedAudio() -> [Float] {
        // Use the same first-sample offsets the HQ archive uses, so the mono mix
        // is aligned on the shared timeline too. Without this the mic (which often
        // starts a few seconds late on AVAudioEngine fallback) was mixed from
        // index 0 and played time-shifted against the system audio.
        Self.alignedMix(
            mic: micRecording,
            micOffset: micHQStartOffset,
            system: sysRecording,
            systemOffset: sysHQStartOffset,
            sampleRate: 16_000
        )
    }

    /// Mixes mic + system into one mono track, each front-padded by its own
    /// first-sample offset so a late-starting source lines up on the shared
    /// timeline instead of being pulled to the front. Peaks are hard-clipped
    /// (no global normalisation, which used to crush quiet meetings). Internal
    /// for testing.
    nonisolated static func alignedMix(
        mic: [Float],
        micOffset: TimeInterval?,
        system: [Float],
        systemOffset: TimeInterval?,
        sampleRate: Double
    ) -> [Float] {
        let m = frontPadded(mic, offset: micOffset, sampleRate: sampleRate)
        let s = frontPadded(system, offset: systemOffset, sampleRate: sampleRate)
        let length = max(m.count, s.count)
        guard length > 0 else { return [] }

        var mixed = [Float](repeating: 0, count: length)
        for i in 0..<m.count { mixed[i] = m[i] }
        for i in 0..<s.count { mixed[i] += s[i] }
        for i in 0..<mixed.count {
            mixed[i] = min(max(mixed[i], -0.95), 0.95)
        }
        return mixed
    }

    private func flushChunk(force: Bool = false) {
        // Mic-Stream
        let micCount = micBuffer.count
        if micCount >= minChunkSamples || (force && micCount > 0) {
            let chunkSize = min(micCount, maxChunkSamples)
            let chunk = Array(micBuffer.prefix(chunkSize))
            micBuffer.removeFirst(chunkSize)
            onMicChunk?(chunk)
        }

        // Sys-Stream (Teams/Zoom-Remote-Stimme) — eigener Push, damit Whisper ihn
        // ueberhaupt sieht. Vorher wurde `sysBuffer` nur stillschweigend geleert.
        let sysCount = sysBuffer.count
        if sysCount >= minChunkSamples || (force && sysCount > 0) {
            let chunkSize = min(sysCount, maxChunkSamples)
            let chunk = Array(sysBuffer.prefix(chunkSize))
            sysBuffer.removeFirst(chunkSize)
            onSysChunk?(chunk)
        }
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

        let sourceFormat = AVAudioFormat(cmAudioFormatDescription: formatDesc)

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

        // High-resolution archive path: 48 kHz mono from the same native buffer.
        if let hq = self.micHQConverter?.convert(pcmBuffer), !hq.isEmpty {
            Task { @MainActor in
                self.appendAudioHQ(hq, source: "Mic")
            }
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
