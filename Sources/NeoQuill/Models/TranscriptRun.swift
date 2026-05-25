import Foundation

enum TranscriptQualityStatus: String, Codable, Hashable {
    case passed
    case failed
}

enum TranscriptQualityWarning: String, Codable, Hashable {
    case noSegments = "no_segments"
    case longRepeatedRun = "long_repeated_run"
    case highRepeatRatio = "high_repeat_ratio"
    case lowUniqueTextRatio = "low_unique_text_ratio"
    case tooFewWordsForDuration = "too_few_words_for_duration"
}

struct TranscriptQualityReport: Codable, Hashable {
    let status: TranscriptQualityStatus
    let score: Double
    let segmentCount: Int
    let wordCount: Int
    let uniqueTextRatio: Double
    let repeatRatio: Double
    let longestRepeatedRun: Int
    let warnings: [TranscriptQualityWarning]
}

struct TranscriptEngineInfo: Codable, Hashable {
    let name: String
    let model: String
    let version: String?
}

struct TranscriptRunSettings: Codable, Hashable {
    let language: String
    let maxContextTokens: Int
    let vadEnabled: Bool
    let fullJSON: Bool
    let chunkDurationSeconds: TimeInterval
    let overlapSeconds: TimeInterval
}

struct TranscriptRunSpeaker: Codable, Hashable {
    let id: String
    let name: String?
    let source: SpeakerIdentitySource
    let confidence: Double
}

struct TranscriptRunWord: Codable, Hashable {
    let text: String
    let startMilliseconds: Int
    let endMilliseconds: Int
    let confidence: Double?
}

struct TranscriptRunSegment: Identifiable, Codable, Hashable {
    let id: UUID
    let startMilliseconds: Int
    let endMilliseconds: Int
    let text: String
    let source: TranscriptSource
    let speaker: TranscriptRunSpeaker
    let confidence: Double?
    let words: [TranscriptRunWord]
}

struct TranscriptRawArtifact: Codable, Hashable {
    let kind: String
    let path: String?
}

struct TranscriptRun: Identifiable, Codable, Hashable {
    let schemaVersion: Int
    let id: UUID
    let meetingId: String
    let stem: String
    let createdAt: Date
    let audioSha256: String?
    let audioSampleRate: Double
    let audioDurationSeconds: TimeInterval
    let engine: TranscriptEngineInfo
    let settings: TranscriptRunSettings
    let quality: TranscriptQualityReport
    let segments: [TranscriptRunSegment]
    let rawArtifacts: [TranscriptRawArtifact]

    init(
        id: UUID = UUID(),
        meetingId: String,
        stem: String,
        createdAt: Date = Date(),
        audioSha256: String? = nil,
        audioSampleRate: Double,
        audioDurationSeconds: TimeInterval,
        engine: TranscriptEngineInfo,
        settings: TranscriptRunSettings,
        quality: TranscriptQualityReport,
        segments: [TranscriptRunSegment],
        rawArtifacts: [TranscriptRawArtifact] = []
    ) {
        self.schemaVersion = 2
        self.id = id
        self.meetingId = meetingId
        self.stem = stem
        self.createdAt = createdAt
        self.audioSha256 = audioSha256
        self.audioSampleRate = audioSampleRate
        self.audioDurationSeconds = audioDurationSeconds
        self.engine = engine
        self.settings = settings
        self.quality = quality
        self.segments = segments
        self.rawArtifacts = rawArtifacts
    }

    static func fromLines(
        meetingId: String,
        stem: String,
        audioSampleRate: Double,
        audioDurationSeconds: TimeInterval,
        engine: TranscriptEngineInfo,
        settings: TranscriptRunSettings,
        lines: [TranscriptLine],
        audioSha256: String? = nil,
        createdAt: Date = Date()
    ) -> TranscriptRun {
        let segments = lines.map { line in
            TranscriptRunSegment(
                id: line.id,
                startMilliseconds: Int((line.startSeconds * 1_000).rounded()),
                endMilliseconds: Int((line.endSeconds * 1_000).rounded()),
                text: line.body,
                source: line.source,
                speaker: TranscriptRunSpeaker(
                    id: line.who,
                    name: line.displayName,
                    source: line.speakerSource,
                    confidence: line.confidence
                ),
                confidence: line.confidence,
                words: []
            )
        }
        let quality = TranscriptQualityScorer.evaluate(
            segments: segments,
            audioDurationSeconds: audioDurationSeconds
        )
        return TranscriptRun(
            meetingId: meetingId,
            stem: stem,
            createdAt: createdAt,
            audioSha256: audioSha256,
            audioSampleRate: audioSampleRate,
            audioDurationSeconds: audioDurationSeconds,
            engine: engine,
            settings: settings,
            quality: quality,
            segments: segments
        )
    }

    func transcriptLines() -> [TranscriptLine] {
        segments.map { segment in
            TranscriptLine(
                id: segment.id,
                who: segment.speaker.id,
                displayName: segment.speaker.name,
                timestamp: Self.timestamp(milliseconds: segment.startMilliseconds),
                startSeconds: TimeInterval(segment.startMilliseconds) / 1_000,
                endSeconds: TimeInterval(segment.endMilliseconds) / 1_000,
                body: segment.text,
                source: segment.source,
                speakerSource: segment.speaker.source,
                confidence: segment.confidence ?? segment.speaker.confidence,
                highlight: false
            )
        }
    }

    private static func timestamp(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
