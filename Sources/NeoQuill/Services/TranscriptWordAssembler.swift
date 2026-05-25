import Foundation

struct TranscriptTokenSlice: Hashable {
    let text: String
    let startMilliseconds: Int
    let endMilliseconds: Int
    let confidence: Double?
}

enum TranscriptWordAssembler {
    static func words(
        from tokens: [TranscriptTokenSlice],
        chunkOffsetMilliseconds: Int
    ) -> [TranscriptRunWord] {
        var result: [TranscriptRunWord] = []
        var currentText = ""
        var currentStart: Int?
        var currentEnd: Int?
        var probabilities: [Double] = []

        func flush() {
            let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let start = currentStart, let end = currentEnd else {
                currentText = ""
                currentStart = nil
                currentEnd = nil
                probabilities.removeAll(keepingCapacity: true)
                return
            }
            let confidence = probabilities.isEmpty
                ? nil
                : probabilities.reduce(0, +) / Double(probabilities.count)
            result.append(TranscriptRunWord(
                text: text,
                startMilliseconds: chunkOffsetMilliseconds + start,
                endMilliseconds: chunkOffsetMilliseconds + max(end, start),
                confidence: confidence
            ))
            currentText = ""
            currentStart = nil
            currentEnd = nil
            probabilities.removeAll(keepingCapacity: true)
        }

        for token in tokens {
            let trimmed = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("[_") else { continue }

            let startsNewWord = token.text.first?.isWhitespace == true || currentText.isEmpty
            if startsNewWord {
                flush()
            }
            currentText += trimmed
            currentStart = min(currentStart ?? token.startMilliseconds, token.startMilliseconds)
            currentEnd = max(currentEnd ?? token.endMilliseconds, token.endMilliseconds)
            if let confidence = token.confidence {
                probabilities.append(confidence)
            }
        }
        flush()
        return result
    }
}
