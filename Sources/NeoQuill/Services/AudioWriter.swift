import AVFoundation
import Foundation

// Schreibt Audio-Chunks live in eine WAV-Datei während der Aufnahme.
// 16kHz Mono Float32 — gleiche Format wie WhisperKit erwartet.
// File-Pfad: ~/Library/Application Support/NeoQuill/recordings/<id>.wav

enum RecordingAudioStem {
    case mix
    case mic
    case system
    /// High-resolution stereo archive (mic = left, system = right) at 48 kHz.
    /// This is the user-facing playback/export file; `.mix`/`.mic`/`.system`
    /// stay 16 kHz mono and remain the ASR/diarization sources.
    case hq

    var suffix: String {
        switch self {
        case .mix:    return ""
        case .mic:    return ".mic"
        case .system: return ".system"
        case .hq:     return ".hq"
        }
    }
}

final class AudioWriter {

    private static var playbackCompatibleWavSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private var file: AVAudioFile?
    private(set) var url: URL?
    private let format: AVAudioFormat

    init() {
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    static func recordingsDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("NeoQuill/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(id: String, stem: RecordingAudioStem = .mix) -> URL {
        recordingsDirectory().appendingPathComponent("\(id)\(stem.suffix).wav")
    }

    static func persist(id: String, stem: RecordingAudioStem = .mix, samples: [Float]) throws -> URL? {
        guard !samples.isEmpty else { return nil }
        let writer = AudioWriter()
        try writer.start(id: id, stem: stem)
        writer.write(samples: samples)
        return writer.close()
    }

    /// Writes a stereo high-resolution WAV (left = mic, right = system) used for
    /// playback and export. Channels are padded to equal length; samples are only
    /// guarded against NaN/Inf and the ±1.0 ceiling — there is no destructive
    /// mixdown, so there is no double-talk clipping to clamp away.
    static func persistStereo(
        id: String,
        stem: RecordingAudioStem = .hq,
        left: [Float],
        right: [Float],
        sampleRate: Double = 48_000
    ) throws -> URL? {
        let frameCount = max(left.count, right.count)
        guard frameCount > 0 else { return nil }

        let url = Self.url(id: id, stem: stem)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        if let channels = buffer.floatChannelData {
            let l = channels[0]
            let r = channels[1]
            for i in 0..<frameCount {
                let lv = i < left.count ? left[i] : 0
                let rv = i < right.count ? right[i] : 0
                l[i] = lv.isFinite ? min(max(lv, -1), 1) : 0
                r[i] = rv.isFinite ? min(max(rv, -1), 1) : 0
            }
        }
        try file.write(from: buffer)
        return url
    }

    static func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func writePlaybackCompatibleWav(samples: [Float], to url: URL) throws {
        guard !samples.isEmpty else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let writer = AudioWriter()
        let file = try AVAudioFile(
            forWriting: url,
            settings: playbackCompatibleWavSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try writer.write(samples: samples, to: file)
    }

    func start(id: String, stem: RecordingAudioStem = .mix) throws {
        let url = Self.url(id: id, stem: stem)
        self.file = try AVAudioFile(
            forWriting: url,
            settings: Self.playbackCompatibleWavSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.url = url
    }

    /// Schreibt einen Float-Buffer (16kHz Mono). Wird vom AudioCapture-Mix gefüttert.
    func write(samples: [Float]) {
        guard let file else { return }
        do {
            try write(samples: samples, to: file)
        } catch {
            NSLog("[AudioWriter] write failed: \(error)")
        }
    }

    func close() -> URL? {
        let result = url
        file = nil
        return result
    }

    private func write(samples: [Float], to file: AVAudioFile) throws {
        let prepared = Self.prepareForPlayback(samples)
        let frameCount = AVAudioFrameCount(prepared.count)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            prepared.withUnsafeBufferPointer { src in
                guard let baseAddress = src.baseAddress else { return }
                channel.update(from: baseAddress, count: prepared.count)
            }
        }
        try file.write(from: buffer)
    }

    private static func prepareForPlayback(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        return samples.map { sample in
            guard sample.isFinite else { return 0 }
            return min(max(sample, -0.95), 0.95)
        }
    }
}
