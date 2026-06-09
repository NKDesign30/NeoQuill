import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// ScreenCaptureKit-basierter Audio-Capture fuer Remote-Teilnehmer.
/// Greift den Audio-Output einer bestimmten App ab (Teams, Zoom, etc.).
///
/// Vorteile gegenueber CoreAudio Process Tap:
/// - Kein spezielles Code-Signing/Entitlement noetig
/// - Audio wird NICHT gemutet (Loopback-Capture)
/// - Bluetooth bleibt in A2DP (kein Mic-Zugriff)
///
/// Nachteile:
/// - Braucht minimalen Video-Stream (2x2px, ~0fps) — ScreenCaptureKit erzwingt das
/// - "Screen Recording" Permission noetig (lila Punkt in Menueleiste)
@available(macOS 13.0, *)
final class SCKAudioCapture: NSObject, SystemAudioSource, @unchecked Sendable {

    /// Called with 16kHz mono Float32 samples
    var onSamples: (([Float]) -> Void)?

    /// Called with 48kHz mono Float32 samples for the high-resolution archive.
    var onSamplesHQ: (([Float]) -> Void)?

    private var stream: SCStream?
    private var isRunning = false

    private let audioQueue = DispatchQueue(label: "com.quill.sck-audio", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.quill.sck-video-discard", qos: .background)

    private lazy var asrConverter = PCMStreamConverter(targetSampleRate: 16_000)
    private lazy var hqConverter = PCMStreamConverter(targetSampleRate: 48_000)
    private var sckCallbackCount = 0

    /// Startet Audio-Capture fuer die App mit dem gegebenen Bundle Identifier.
    func start(bundleIdentifiers: [String]) async throws {
        guard !isRunning else { return }

        // 1. Verfuegbare Apps und Displays holen
        let content = try await SCShareableContent.current

        // 2. Display (Pflicht bei ScreenCaptureKit)
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        // 3. Ziel-App finden — Teams nutzt mehrere Helper-Prozesse, daher Fallback auf alle Apps
        //    Strategie A: exakter Bundle-ID Match
        //    Strategie B: Name-Match für Teams-Helper (com.microsoft.teams2.*)
        //    Strategie C: gesamtes System-Audio (wenn App nicht eindeutig findbar)
        var matchedApps: [SCRunningApplication] = []
        for bundleId in bundleIdentifiers {
            let direct = content.applications.filter { $0.bundleIdentifier == bundleId }
            matchedApps.append(contentsOf: direct)
            // Teams Helper-Prozesse (com.microsoft.teams2.notificationcenter etc.)
            let helpers = content.applications.filter {
                $0.bundleIdentifier.hasPrefix(bundleId + ".")
            }
            matchedApps.append(contentsOf: helpers)
        }

        // 4. Content Filter
        let filter: SCContentFilter
        if matchedApps.isEmpty {
            // Fallback: gesamtes System-Audio (alle Apps auf dem Display)
            print("[Quill] SCK: Keine App-Match, capture gesamtes System-Audio")
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        } else {
            print("[Quill] SCK: capture \(matchedApps.map { $0.bundleIdentifier })")
            filter = SCContentFilter(display: display, including: matchedApps, exceptingWindows: [])
        }

        // 5. Stream-Config: Audio-fokussiert, minimaler Video-Overhead
        let config = SCStreamConfiguration()

        // Audio
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 2

        // Video minimieren (ScreenCaptureKit erzwingt Video-Stream)
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale.max)
        config.queueDepth = 1
        config.showsCursor = false

        // 6. Stream erstellen
        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        // Beide Outputs registrieren (ohne .screen gibt es Fehler-Logs)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        // 7. Starten
        try await stream.startCapture()

        self.stream = stream
        self.isRunning = true
        print("[Quill] SCK Audio-Capture gestartet (\(matchedApps.isEmpty ? "System-Audio" : matchedApps.map { $0.bundleIdentifier }.joined(separator: ",")))")
    }

    func stop() async {
        guard isRunning, let stream = stream else { return }
        isRunning = false

        do {
            try await stream.stopCapture()
        } catch {
            print("[Quill] SCK Stop-Fehler: \(error)")
        }

        self.stream = nil
        print("[Quill] SCK Audio-Capture gestoppt")
    }

    // MARK: - Audio Processing

    private func extractPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = formatDesc.audioStreamBasicDescription else {
            return nil
        }

        guard asbd.mSampleRate > 0 else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDesc)

        return try? sampleBuffer.withAudioBufferList { audioBufferList, _ -> AVAudioPCMBuffer? in
            return AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: audioBufferList.unsafePointer
            )
        }
    }

    private func resampleTo16kHzMono(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        // Drain-correct streaming conversion, same path as the process tap. The
        // old floor()-sized one-shot path lost the fractional frame per buffer.
        asrConverter?.convert(buffer)
    }
}

// MARK: - SCStreamOutput

@available(macOS 13.0, *)
extension SCKAudioCapture: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else { return }

        switch outputType {
        case .screen, .microphone:
            break  // Video/Mic-Frames verwerfen — wir wollen nur App-Audio
        case .audio:
            guard let pcmBuffer = extractPCMBuffer(from: sampleBuffer) else { return }
            // High-resolution archive path: 48 kHz mono from the same native buffer.
            if let onSamplesHQ, let hq = hqConverter?.convert(pcmBuffer), !hq.isEmpty {
                onSamplesHQ(hq)
            }

            guard let samples = resampleTo16kHzMono(pcmBuffer) else { return }
            if !samples.isEmpty {
                sckCallbackCount += 1
                if sckCallbackCount <= 3 {
                    let maxVal = samples.map { abs($0) }.max() ?? 0
                    let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(max(samples.count, 1)))
                    print("[Quill] SCK Audio Callback #\(sckCallbackCount): \(samples.count) samples, max=\(maxVal), rms=\(rms), format=\(pcmBuffer.format)")
                }
                onSamples?(samples)
            }
        @unknown default:
            break
        }
    }
}

// MARK: - SCStreamDelegate

@available(macOS 13.0, *)
extension SCKAudioCapture: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[Quill] SCK Stream-Fehler: \(error.localizedDescription)")
    }
}
