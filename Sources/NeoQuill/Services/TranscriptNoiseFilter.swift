import Foundation

enum TranscriptNoiseFilter {
    /// Liegt in `TranscriptQualityPolicy`, damit alle Wiederholungs-Schwellen an
    /// einem Ort stehen.
    static var maxConsecutiveRepeatedBodies: Int { TranscriptQualityPolicy.maxConsecutiveRepeatedBodies }

    static func filtered(_ lines: [TranscriptLine]) -> [TranscriptLine] {
        var result: [TranscriptLine] = []
        var previousBodyKey = ""
        var repeatedBodyCount = 0

        for line in lines {
            let bodyKey = normalizedBody(line.body)
            guard !bodyKey.isEmpty else { continue }

            if bodyKey == previousBodyKey {
                repeatedBodyCount += 1
            } else {
                previousBodyKey = bodyKey
                repeatedBodyCount = 1
            }

            if repeatedBodyCount <= maxConsecutiveRepeatedBodies {
                result.append(line)
            }
        }

        return result
    }

    static func wordCount(_ lines: [TranscriptLine]) -> Int {
        lines.reduce(0) { count, line in
            count + line.body.split(whereSeparator: \.isWhitespace).count
        }
    }

    private static func normalizedBody(_ body: String) -> String {
        body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
