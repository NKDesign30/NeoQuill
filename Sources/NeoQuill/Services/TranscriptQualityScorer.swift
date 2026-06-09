import Foundation

enum TranscriptQualityScorer {
    private static let longRepeatedRunThreshold = 10
    private static let highRepeatRatioThreshold = 0.35
    private static let lowUniqueTextRatioThreshold = 0.15

    static func evaluate(lines: [TranscriptLine], audioDurationSeconds: TimeInterval) -> TranscriptQualityReport {
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
        return evaluate(segments: segments, audioDurationSeconds: audioDurationSeconds)
    }

    static func evaluate(
        segments: [TranscriptRunSegment],
        audioDurationSeconds: TimeInterval
    ) -> TranscriptQualityReport {
        let bodies = segments
            .map { normalizedBody($0.text) }
            .filter { !$0.isEmpty }
        let segmentCount = bodies.count
        let wordCount = segments.reduce(0) { count, segment in
            count + segment.text.split(whereSeparator: \.isWhitespace).count
        }

        guard segmentCount > 0 else {
            return TranscriptQualityReport(
                status: .failed,
                score: 0,
                segmentCount: 0,
                wordCount: 0,
                uniqueTextRatio: 0,
                repeatRatio: 0,
                longestRepeatedRun: 0,
                warnings: [.noSegments]
            )
        }

        var longestRepeatedRun = 1
        var currentRepeatedRun = 0
        var previous = ""
        var repeatedBeyondFirst = 0

        for body in bodies {
            if body == previous {
                currentRepeatedRun += 1
                repeatedBeyondFirst += 1
            } else {
                previous = body
                currentRepeatedRun = 1
            }
            longestRepeatedRun = max(longestRepeatedRun, currentRepeatedRun)
        }

        let uniqueTextRatio = Double(Set(bodies).count) / Double(segmentCount)
        let repeatRatio = Double(repeatedBeyondFirst) / Double(segmentCount)
        let tooFewWords = audioDurationSeconds >= 120 && wordCount < max(8, Int(audioDurationSeconds / 30))

        var warnings: [TranscriptQualityWarning] = []
        if longestRepeatedRun >= longRepeatedRunThreshold {
            warnings.append(.longRepeatedRun)
        }
        if segmentCount >= 20 && repeatRatio > highRepeatRatioThreshold {
            warnings.append(.highRepeatRatio)
        }
        if segmentCount >= 20 && uniqueTextRatio < lowUniqueTextRatioThreshold {
            warnings.append(.lowUniqueTextRatio)
        }
        if tooFewWords {
            warnings.append(.tooFewWordsForDuration)
        }

        let repetitionPenalty = min(0.65, repeatRatio * 0.75)
        let uniquenessPenalty = uniqueTextRatio < 0.5 ? min(0.35, (0.5 - uniqueTextRatio) * 0.7) : 0
        let longRunPenalty = longestRepeatedRun > 2 ? min(0.35, Double(longestRepeatedRun - 2) * 0.03) : 0
        let wordPenalty = tooFewWords ? 0.4 : 0
        let score = max(0, min(1, 1 - repetitionPenalty - uniquenessPenalty - longRunPenalty - wordPenalty))

        let failedWarnings = warnings.filter { $0 != .tooFewWordsForDuration }
        return TranscriptQualityReport(
            status: failedWarnings.isEmpty ? .passed : .failed,
            score: score,
            segmentCount: segmentCount,
            wordCount: wordCount,
            uniqueTextRatio: uniqueTextRatio,
            repeatRatio: repeatRatio,
            longestRepeatedRun: longestRepeatedRun,
            warnings: warnings
        )
    }

    /// Fürs Scoring strippt der Vergleich zusätzlich alle Satzzeichen — "danke!"
    /// und "danke" sollen für die repeatRatio als derselbe Body zählen. Das ist
    /// die bewusste Divergenz gegenüber `TranscriptRepeatKey.normalized`, auf dem
    /// diese Funktion aufbaut.
    private static func normalizedBody(_ body: String) -> String {
        let folded = TranscriptRepeatKey.normalized(body)
        let scalars = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
