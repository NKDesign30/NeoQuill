import Foundation

struct DiarizedSpeakerSegment: Hashable {
    let start: TimeInterval
    let end: TimeInterval
    let speakerId: String
    let embedding: [Float]
    let speakerSource: SpeakerIdentitySource
    let confidence: Double

    init(
        start: TimeInterval,
        end: TimeInterval,
        speakerId: String,
        embedding: [Float],
        speakerSource: SpeakerIdentitySource = .diarization,
        confidence: Double = 0.7
    ) {
        self.start = max(0, start)
        self.end = max(end, start)
        self.speakerId = speakerId
        self.embedding = embedding
        self.speakerSource = speakerSource
        self.confidence = min(max(confidence, 0), 1)
    }
}

enum SpeakerNameResolver {
    static func id(for name: String) -> String {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let initials = normalized.compactMap { $0.first.map(String.init) }.joined()
        if !initials.isEmpty { return initials.uppercased() }
        let fallback = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(3)
            .uppercased()
        return fallback.isEmpty ? "SP" : String(fallback)
    }

    static func isHiddenIdentity(_ name: String?) -> Bool {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return true }
        let lower = raw.lowercased()
        return lower == "unknown"
            || lower == "speaker"
            || lower == "participant"
            || lower.contains("hidden")
            || lower.contains("anonymous")
            || lower.contains("anonym")
            || lower.contains("unbekannt")
    }
}

enum TranscriptMerger {
    static func merge(
        audioLines: [TranscriptLine],
        captionEvents: [CaptionEvent],
        diarization: [DiarizedSpeakerSegment]
    ) -> [TranscriptLine] {
        audioLines.map { line in
            if LocalSpeakerProfile.isLocalSpeakerId(line.who) {
                return copy(
                    line,
                    who: LocalSpeakerProfile.id,
                    displayName: line.displayName ?? LocalSpeakerProfile.displayName,
                    source: line.source == .caption ? .caption : line.source,
                    speakerSource: .microphoneOwner,
                    confidence: max(line.confidence, 1.0)
                )
            }

            if let caption = bestCaptionMatch(for: line, in: captionEvents),
               !SpeakerNameResolver.isHiddenIdentity(caption.speakerName),
               let speakerName = caption.speakerName {
                return copy(
                    line,
                    who: SpeakerNameResolver.id(for: speakerName),
                    displayName: speakerName,
                    source: .merged,
                    speakerSource: .caption,
                    confidence: caption.confidence
                )
            }

            if let segment = bestDiarizationMatch(for: line, in: diarization) {
                return copy(
                    line,
                    who: segment.speakerId,
                    displayName: line.displayName,
                    source: .merged,
                    speakerSource: segment.speakerSource,
                    confidence: segment.confidence
                )
            }

            return line
        }
        .sorted { lhs, rhs in
            if lhs.startSeconds == rhs.startSeconds { return lhs.endSeconds < rhs.endSeconds }
            return lhs.startSeconds < rhs.startSeconds
        }
    }

    private static func bestCaptionMatch(for line: TranscriptLine, in events: [CaptionEvent]) -> CaptionEvent? {
        let candidates = events.compactMap { event -> (event: CaptionEvent, score: Double)? in
            let windowScore = temporalScore(
                lineStart: line.startSeconds,
                lineEnd: line.endSeconds,
                eventStart: event.startSeconds,
                eventEnd: event.endSeconds ?? event.startSeconds + 2.5
            )
            guard windowScore > 0 else { return nil }
            let textScore = textSimilarity(line.body, event.text)
            let score = (windowScore * 0.55) + (textScore * 0.45)
            guard score >= 0.34 || textScore >= 0.42 else { return nil }
            return (event, score)
        }
        return candidates.max { $0.score < $1.score }?.event
    }

    private static func bestDiarizationMatch(
        for line: TranscriptLine,
        in segments: [DiarizedSpeakerSegment]
    ) -> DiarizedSpeakerSegment? {
        segments.max { lhs, rhs in
            overlapScore(line: line, segment: lhs) < overlapScore(line: line, segment: rhs)
        }.flatMap { segment in
            overlapScore(line: line, segment: segment) > 0 ? segment : nil
        }
    }

    private static func overlapScore(line: TranscriptLine, segment: DiarizedSpeakerSegment) -> Double {
        let lineEnd = max(line.endSeconds, line.startSeconds + 0.8)
        let overlap = max(0, min(lineEnd, segment.end) - max(line.startSeconds, segment.start))
        let span = max(lineEnd - line.startSeconds, 0.8)
        if overlap > 0 { return overlap / span }
        let distance = min(abs(line.startSeconds - segment.end), abs(segment.start - lineEnd))
        return distance <= 1.2 ? 0.2 : 0
    }

    private static func temporalScore(
        lineStart: TimeInterval,
        lineEnd: TimeInterval,
        eventStart: TimeInterval,
        eventEnd: TimeInterval
    ) -> Double {
        let resolvedLineEnd = max(lineEnd, lineStart + 0.8)
        let resolvedEventEnd = max(eventEnd, eventStart + 0.8)
        let overlap = max(0, min(resolvedLineEnd, resolvedEventEnd) - max(lineStart, eventStart))
        let union = max(resolvedLineEnd, resolvedEventEnd) - min(lineStart, eventStart)
        if overlap > 0, union > 0 { return overlap / union }
        let distance = min(abs(lineStart - resolvedEventEnd), abs(eventStart - resolvedLineEnd))
        return distance <= 3.0 ? max(0, 1.0 - (distance / 3.0)) * 0.55 : 0
    }

    private static func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let a = tokens(lhs)
        let b = tokens(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    private static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
        )
    }

    private static func copy(
        _ line: TranscriptLine,
        who: String,
        displayName: String?,
        source: TranscriptSource,
        speakerSource: SpeakerIdentitySource,
        confidence: Double
    ) -> TranscriptLine {
        TranscriptLine(
            id: line.id,
            who: who,
            displayName: displayName,
            timestamp: line.timestamp,
            startSeconds: line.startSeconds,
            endSeconds: line.endSeconds,
            body: line.body,
            source: source,
            speakerSource: speakerSource,
            confidence: min(max(confidence, 0), 1),
            highlight: line.highlight
        )
    }
}
