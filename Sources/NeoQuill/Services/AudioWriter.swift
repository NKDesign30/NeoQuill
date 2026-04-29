import AVFoundation
import Foundation

// Schreibt Audio-Chunks live in eine WAV-Datei während der Aufnahme.
// 16kHz Mono Float32 — gleiche Format wie WhisperKit erwartet.
// File-Pfad: ~/Library/Application Support/NeoQuill/recordings/<id>.wav

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

    func start(id: String) throws {
        let url = Self.recordingsDirectory().appendingPathComponent("\(id).wav")
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
        let frameCount = AVAudioFrameCount(samples.count)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                channel.update(from: src.baseAddress!, count: samples.count)
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
}
