import AVFoundation
import Foundation

// Schreibt Audio-Chunks live in eine WAV-Datei während der Aufnahme.
// 16kHz Mono Float32 — gleiche Format wie WhisperKit erwartet.
// File-Pfad: ~/Library/Application Support/NeoQuill/recordings/<id>.wav

enum RecordingAudioStem {
    case mix
    case mic
    case system

    var suffix: String {
        switch self {
        case .mix:    return ""
        case .mic:    return ".mic"
        case .system: return ".system"
        }
    }
}

final class AudioWriter {

    private var file: AVAudioFile?
    private(set) var url: URL?
    private let format: AVAudioFormat

    init() {
        self.format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
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

    static func readSamples(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    func start(id: String, stem: RecordingAudioStem = .mix) throws {
        let url = Self.url(id: id, stem: stem)
        // WAV-Settings explizit für AVAudioFile (Float32 Mono 16kHz)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        self.file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.url = url
    }

    /// Schreibt einen Float-Buffer (16kHz Mono). Wird vom AudioCapture-Mix gefüttert.
    func write(samples: [Float]) {
        guard let file else { return }
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
        do {
            try file.write(from: buffer)
        } catch {
            NSLog("[AudioWriter] write failed: \(error)")
        }
    }

    func close() -> URL? {
        let result = url
        file = nil
        return result
    }

    private static func prepareForPlayback(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        return samples.map { sample in
            guard sample.isFinite else { return 0 }
            return min(max(sample, -0.95), 0.95)
        }
    }
}
