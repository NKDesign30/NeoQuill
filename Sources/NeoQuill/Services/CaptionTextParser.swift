import Foundation

struct CaptionCandidate: Hashable {
    let bundleIdentifier: String?
    let speakerName: String?
    let text: String
    let rawText: String
    let estimatedDuration: TimeInterval
}

enum CaptionTextParser {
    static func parseCandidate(_ raw: String, bundleIdentifier: String?) -> CaptionCandidate? {
        let text = normalizeVisibleText(raw)
        guard isProbableCaptionText(text) else { return nil }

        if let split = splitSpeakerAndText(text) {
            return CaptionCandidate(
                bundleIdentifier: bundleIdentifier,
                speakerName: split.speaker,
                text: split.text,
                rawText: raw,
                estimatedDuration: estimatedDuration(for: split.text)
            )
        }

        return CaptionCandidate(
            bundleIdentifier: bundleIdentifier,
            speakerName: nil,
            text: text,
            rawText: raw,
            estimatedDuration: estimatedDuration(for: text)
        )
    }

    static func fingerprint(candidate: CaptionCandidate, platform: Platform) -> String {
        [
            platform.rawValue,
            candidate.speakerName?.lowercased() ?? "",
            candidate.text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        ].joined(separator: "|")
    }

    static func isUsefulVisibleText(_ text: String) -> Bool {
        let normalized = normalizeVisibleText(text)
        guard (2...420).contains(normalized.count) else { return false }
        let lower = normalized.lowercased()
        let blockedFragments = [
            "microphone", "camera", "share screen", "raise hand", "leave",
            "mikrofon", "kamera", "bildschirm", "teilnehmen", "verlassen",
            "calendar", "chat", "reaction", "reaktion", "settings"
        ]
        return !blockedFragments.contains { lower.contains($0) }
    }

    static func normalizeVisibleText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitSpeakerAndText(_ text: String) -> (speaker: String, text: String)? {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count >= 2, isProbableSpeakerName(lines[0]) {
            let body = lines.dropFirst().joined(separator: " ")
            if isProbableCaptionText(body) {
                return (lines[0], body)
            }
        }

        guard let colon = text.firstIndex(of: ":") else { return nil }
        let speaker = String(text[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isProbableSpeakerName(speaker), isProbableCaptionText(body) else { return nil }
        return (speaker, body)
    }

    private static func isProbableSpeakerName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...64).contains(trimmed.count) else { return false }
        let lower = trimmed.lowercased()
        if lower.contains("caption") || lower.contains("untertitel") || lower.contains("transcript") { return false }
        let words = trimmed.split(separator: " ")
        return words.count <= 5 && trimmed.rangeOfCharacter(from: .letters) != nil
    }

    private static func isProbableCaptionText(_ text: String) -> Bool {
        let normalized = normalizeVisibleText(text)
        guard (4...360).contains(normalized.count) else { return false }
        guard normalized.rangeOfCharacter(from: .letters) != nil else { return false }
        let wordCount = normalized.split(separator: " ").count
        if wordCount >= 3 { return true }
        return normalized.contains(".") || normalized.contains("?") || normalized.contains("!")
    }

    private static func estimatedDuration(for text: String) -> TimeInterval {
        let words = max(1, text.split(separator: " ").count)
        return min(8.0, max(1.2, Double(words) / 2.4))
    }
}
