import AVFoundation
import Foundation

enum FinalSTTError: Error {
    case missingBinaryOrModel
    case processFailed(Int32)
    case outputMissing
    case qualityRejected(TranscriptRun)
}

struct FinalSTTResult {
    let run: TranscriptRun
    let lines: [TranscriptLine]
}

enum FinalSTTTranscriber {
    private static let sampleRate: Double = 16_000
    private static let quietThreshold: Float = 0.00035
    private static let maxChunkDurationSeconds: TimeInterval = 600
    private static let chunkOverlapSeconds: TimeInterval = 0

    static var isAvailable: Bool {
        executableURL() != nil && modelURL() != nil
    }

    static var label: String {
        isAvailable ? "Whisper large-v3 turbo" : "WhisperKit"
    }

    static func transcribe(
        audioData: [Float],
        speaker: String,
        language: String,
        meetingId: String,
        stem: String
    ) async throws -> FinalSTTResult {
        try await Task.detached(priority: .utility) {
            try transcribeBlocking(
                audioData: audioData,
                speaker: speaker,
                language: language,
                meetingId: meetingId,
                stem: stem
            )
        }.value
    }

    private static func transcribeBlocking(
        audioData: [Float],
        speaker: String,
        language: String,
        meetingId: String,
        stem: String
    ) throws -> FinalSTTResult {
        let cleaned = sanitize(audioData)
        guard let executable = executableURL(), let model = modelURL() else {
            throw FinalSTTError.missingBinaryOrModel
        }
        let duration = TimeInterval(cleaned.count) / sampleRate
        let audioSha256 = AudioFingerprint.sha256(samples: cleaned)
        let settings = runSettings(language: language)
        let engine = TranscriptEngineInfo(
            name: "whisper.cpp",
            model: model.deletingPathExtension().lastPathComponent,
            version: nil
        )
        guard hasSpeech(cleaned) else {
            let run = TranscriptRun.fromLines(
                meetingId: meetingId,
                stem: stem,
                audioSampleRate: sampleRate,
                audioDurationSeconds: duration,
                engine: engine,
                settings: settings,
                lines: [],
                audioSha256: audioSha256
            )
            throw FinalSTTError.qualityRejected(run)
        }

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillFinalSTT", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let chunks = makeChunks(cleaned)
        var segments: [TranscriptRunSegment] = []

        for chunk in chunks {
            let decoded = try decodeChunk(
                chunk,
                executable: executable,
                model: model,
                workDir: workDir,
                speaker: speaker,
                language: language
            )
            segments.append(contentsOf: decoded)
        }

        let quality = TranscriptQualityScorer.evaluate(
            segments: segments,
            audioDurationSeconds: duration
        )
        let run = TranscriptRun(
            meetingId: meetingId,
            stem: stem,
            audioSha256: audioSha256,
            audioSampleRate: sampleRate,
            audioDurationSeconds: duration,
            engine: engine,
            settings: settings,
            quality: quality,
            segments: segments
        )
        guard quality.status == .passed else {
            throw FinalSTTError.qualityRejected(run)
        }
        return FinalSTTResult(run: run, lines: run.transcriptLines())
    }

    private static func decodeChunk(
        _ chunk: AudioChunk,
        executable: URL,
        model: URL,
        workDir: URL,
        speaker: String,
        language: String
    ) throws -> [TranscriptRunSegment] {
        let id = "\(UUID().uuidString)-\(chunk.index)"
        let inputURL = workDir.appendingPathComponent("\(id).wav")
        let outputBaseURL = workDir.appendingPathComponent("\(id)-out")
        let jsonURL = outputBaseURL.appendingPathExtension("json")

        try writeWAV(samples: chunk.samples, to: inputURL)
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: jsonURL)
        }

        let process = Process()
        process.executableURL = executable
        var arguments = [
            "--no-gpu",
            "-t", "6",
            "-mc", "0",
            "-m", model.path,
            "-l", language == "auto" ? "auto" : language,
            "-f", inputURL.path,
            "-oj",
            "-ojf",
            "-of", outputBaseURL.path,
            "-sns",
            "--print-confidence",
        ]
        if let vadModel = vadModelURL() {
            arguments.append(contentsOf: ["--vad", "-vm", vadModel.path])
        }
        process.arguments = arguments
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
        let chunkOffsetMilliseconds = Int((TimeInterval(chunk.startSample) / sampleRate * 1_000).rounded())
        return response.transcription.compactMap { segment in
            let text = LiveTranscriber.cleanTokens(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !text.isEmpty else { return nil }
            let isLocalSpeaker = LocalSpeakerProfile.isLocalSpeakerId(speaker)
            let start = chunkOffsetMilliseconds + segment.offsets.from
            let end = max(chunkOffsetMilliseconds + (segment.offsets.to ?? segment.offsets.from), start)
            let speakerSource: SpeakerIdentitySource = isLocalSpeaker ? .microphoneOwner : .unknown
            let words = words(from: segment.tokens ?? [], chunkOffsetMilliseconds: chunkOffsetMilliseconds)
            return TranscriptRunSegment(
                id: UUID(),
                startMilliseconds: start,
                endMilliseconds: end,
                text: text,
                source: isLocalSpeaker ? .mic : .system,
                speaker: TranscriptRunSpeaker(
                    id: speaker,
                    name: isLocalSpeaker ? LocalSpeakerProfile.displayName : nil,
                    source: speakerSource,
                    confidence: 1.0
                ),
                confidence: averageConfidence(words),
                words: words
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

    private static func vadModelURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".cache/whisper-cpp/ggml-silero-v5.1.2.bin"),
            home.appendingPathComponent(".cache/whisper-cpp/ggml-silero-v5.1.2-q8_0.bin"),
            home.appendingPathComponent("Library/Application Support/NeoQuill/models/ggml-silero-v5.1.2.bin"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func runSettings(language: String) -> TranscriptRunSettings {
        TranscriptRunSettings(
            language: language == "auto" ? "auto" : language,
            maxContextTokens: 0,
            vadEnabled: vadModelURL() != nil,
            fullJSON: true,
            chunkDurationSeconds: maxChunkDurationSeconds,
            overlapSeconds: chunkOverlapSeconds
        )
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

    private static func makeChunks(_ samples: [Float]) -> [AudioChunk] {
        let maxChunkSamples = max(1, Int(maxChunkDurationSeconds * sampleRate))
        let overlapSamples = max(0, Int(chunkOverlapSeconds * sampleRate))
        var chunks: [AudioChunk] = []
        var start = 0

        while start < samples.count {
            let end = min(samples.count, start + maxChunkSamples)
            let chunkSamples = Array(samples[start..<end])
            if let chunk = trimmedChunk(index: chunks.count, startSample: start, samples: chunkSamples) {
                chunks.append(chunk)
            }
            guard end < samples.count else { break }
            start = max(end - overlapSamples, start + 1)
        }

        return chunks
    }

    private static func trimmedChunk(index: Int, startSample: Int, samples: [Float]) -> AudioChunk? {
        guard hasSpeech(samples) else { return nil }
        let windowSize = max(1, Int(sampleRate * 0.25))
        let pad = Int(sampleRate * 0.5)
        var firstSpeech = 0
        var lastSpeech = samples.count

        var cursor = 0
        while cursor < samples.count {
            let end = min(samples.count, cursor + windowSize)
            if rms(samples[cursor..<end]) > quietThreshold {
                firstSpeech = max(0, cursor - pad)
                break
            }
            cursor = end
        }

        cursor = samples.count
        while cursor > 0 {
            let begin = max(0, cursor - windowSize)
            if rms(samples[begin..<cursor]) > quietThreshold {
                lastSpeech = min(samples.count, cursor + pad)
                break
            }
            cursor = begin
        }

        guard lastSpeech > firstSpeech else { return nil }
        return AudioChunk(
            index: index,
            startSample: startSample + firstSpeech,
            samples: Array(samples[firstSpeech..<lastSpeech])
        )
    }

    private static func rms(_ samples: ArraySlice<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { partial, sample in
            partial + sample * sample
        }
        return sqrt(sum / Float(samples.count))
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

    private static func words(
        from tokens: [WhisperCLIToken],
        chunkOffsetMilliseconds: Int
    ) -> [TranscriptRunWord] {
        TranscriptWordAssembler.words(
            from: tokens.map { token in
                TranscriptTokenSlice(
                    text: token.text,
                    startMilliseconds: token.offsets.from,
                    endMilliseconds: token.offsets.to ?? token.offsets.from,
                    confidence: token.probability
                )
            },
            chunkOffsetMilliseconds: chunkOffsetMilliseconds
        )
    }

    private static func averageConfidence(_ words: [TranscriptRunWord]) -> Double? {
        let confidences = words.compactMap(\.confidence)
        guard !confidences.isEmpty else { return nil }
        return confidences.reduce(0, +) / Double(confidences.count)
    }

}

private struct AudioChunk {
    let index: Int
    let startSample: Int
    let samples: [Float]
}

private struct WhisperCLIResponse: Decodable {
    let transcription: [WhisperCLISegment]
}

private struct WhisperCLISegment: Decodable {
    let offsets: WhisperCLIOffsets
    let text: String
    let tokens: [WhisperCLIToken]?
}

private struct WhisperCLIOffsets: Decodable {
    let from: Int
    let to: Int?
}

private struct WhisperCLIToken: Decodable {
    let text: String
    let offsets: WhisperCLIOffsets
    let probability: Double?

    private enum CodingKeys: String, CodingKey {
        case text
        case offsets
        case probability = "p"
    }
}
