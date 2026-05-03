import Foundation

struct PlatformTranscriptEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let platform: Platform
    let speakerName: String?
    let speakerId: String?
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let confidence: Double
    let rawPayload: String?

    init(
        id: UUID = UUID(),
        platform: Platform,
        speakerName: String?,
        speakerId: String?,
        text: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        confidence: Double = 0.94,
        rawPayload: String? = nil
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.id = id
        self.platform = platform
        self.speakerName = cleanName
        self.speakerId = speakerId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.text = cleanText
        self.startSeconds = max(0, startSeconds)
        self.endSeconds = max(endSeconds, startSeconds)
        self.confidence = min(max(confidence, 0), 1)
        self.rawPayload = rawPayload
    }

    var captionEvent: CaptionEvent {
        CaptionEvent(
            platform: platform,
            appBundleIdentifier: nil,
            speakerName: speakerName,
            speakerHandle: speakerId,
            text: text,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            confidence: confidence,
            rawPayload: rawPayload
        )
    }
}
