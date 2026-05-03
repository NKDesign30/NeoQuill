import Foundation

struct CaptionEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let platform: Platform
    let appBundleIdentifier: String?
    let speakerName: String?
    let speakerHandle: String?
    let text: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval?
    let observedAt: Date
    let confidence: Double
    let rawPayload: String?

    init(
        id: UUID = UUID(),
        platform: Platform,
        appBundleIdentifier: String?,
        speakerName: String?,
        speakerHandle: String? = nil,
        text: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval? = nil,
        observedAt: Date = Date(),
        confidence: Double,
        rawPayload: String? = nil
    ) {
        self.id = id
        self.platform = platform
        self.appBundleIdentifier = appBundleIdentifier
        self.speakerName = speakerName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.speakerHandle = speakerHandle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedStart = max(0, startSeconds)
        self.startSeconds = resolvedStart
        self.endSeconds = endSeconds.map { max($0, resolvedStart) }
        self.observedAt = observedAt
        self.confidence = min(max(confidence, 0), 1)
        self.rawPayload = rawPayload
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
