import AVFoundation
import Foundation

enum FinalSTTError: Error {
    case missingBinaryOrModel
    case processFailed(Int32)
    case outputMissing
}

enum FinalSTTTranscriber {
    private static let sampleRate: Double = 16_000
    private static let quietThreshold: Float = 0.00035

    static var isAvailable: Bool {
        executableURL() != nil && modelURL() != nil
    }

    static var label: String {
        isAvailable ? "Whisper large-v3 turbo" : "WhisperKit"
    }

    static func transcribe(audioData: [Float], speaker: String, language: String) async throws -> [TranscriptLine] {
        try await Task.detached(priority: .utility) {
            try transcribeBlocking(audioData: audioData, speaker: speaker, language: language)
        }.value
    }

    private static func transcribeBlocking(audioData: [Float], speaker: String, language: String) throws -> [TranscriptLine] {
        let cleaned = sanitize(audioData)
        guard hasSpeech(cleaned) else { return [] }
        guard let executable = executableURL(), let model = modelURL() else {
            throw FinalSTTError.missingBinaryOrModel
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillFinalSTT", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let inputURL = workDir.appendingPathComponent("\(id).wav")
        let outputBaseURL = workDir.appendingPathComponent("\(id)-out")
        let jsonURL = outputBaseURL.appendingPathExtension("json")

        try writeWAV(samples: cleaned, to: inputURL)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: jsonURL)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--no-gpu",
            "-t", "6",
            "-m", model.path,
            "-l", language == "auto" ? "auto" : language,
            "-f", inputURL.path,
            "-oj",
            "-of", outputBaseURL.path,
            "-sns",
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw FinalSTTError.processFailed(process.terminationStatus)
        }
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw FinalSTTError.outputMissing
        }

        let data = try Data(contentsOf: jsonURL)
        let response = try JSONDecoder().decode(WhisperCLIResponse.self, from: data)
        return response.transcription.compactMap { segment in
            let text = LiveTranscriber.cleanTokens(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else { return nil }
            let isLocalSpeaker = LocalSpeakerProfile.isLocalSpeakerId(speaker)
            let startSeconds = TimeInterval(segment.offsets.from) / 1000
            let endSeconds = TimeInterval(segment.offsets.to ?? segment.offsets.from) / 1000
            return TranscriptLine(
                who: speaker,
                displayName: isLocalSpeaker ? LocalSpeakerProfile.displayName : nil,
                timestamp: timestamp(ms: segment.offsets.from),
                startSeconds: startSeconds,
                endSeconds: max(endSeconds, startSeconds),
                body: text,
                source: isLocalSpeaker ? .mic : .system,
                speakerSource: isLocalSpeaker ? .microphoneOwner : .unknown,
                highlight: false
            )
        }
    }

    private static func executableURL() -> URL? {
        [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
        ]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func modelURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".cache/whisper-cpp/ggml-large-v3-turbo.bin"),
            home.appendingPathComponent("Library/Application Support/NeoWispr/models/ggml-large-v3-turbo.bin"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func sanitize(_ samples: [Float]) -> [Float] {
        samples.map { sample in
            guard sample.isFinite else { return 0 }
            return min(max(sample, -1), 1)
        }
    }

    private static func hasSpeech(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        let rms = sqrt(samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count))
        return rms > quietThreshold
    }

    private static func writeWAV(samples: [Float], to url: URL) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { src in
                guard let baseAddress = src.baseAddress else { return }
                channel.update(from: baseAddress, count: samples.count)
            }
        }
        try file.write(from: buffer)
    }

    private static func timestamp(ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WhisperCLIResponse: Decodable {
    let transcription: [WhisperCLISegment]
}

private struct WhisperCLISegment: Decodable {
    let offsets: WhisperCLIOffsets
    let text: String
}

private struct WhisperCLIOffsets: Decodable {
    let from: Int
    let to: Int?
}
