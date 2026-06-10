import Foundation

struct VTTCue: Hashable {
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let payload: String

    var voiceTagName: String? {
        guard let openRange = payload.range(of: "<v "),
              let closeRange = payload.range(of: ">", range: openRange.upperBound..<payload.endIndex) else {
            return nil
        }
        let raw = payload[openRange.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    var voiceTagText: String? {
        guard let openRange = payload.range(of: "<v "),
              let nameClose = payload.range(of: ">", range: openRange.upperBound..<payload.endIndex) else {
            return nil
        }
        let body = payload[nameClose.upperBound...]
        let stripped = body.replacingOccurrences(of: "</v>", with: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    var colonSpeakerPrefix: (speaker: String, text: String)? {
        guard let colon = payload.firstIndex(of: ":") else { return nil }
        let speaker = payload[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let text = payload[payload.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // VTT-Profil: 1-Zeichen-Speaker erlaubt (anonymisierte "A:"-Cues),
        // bis zu 6 Wörter (lange Roster-Display-Namen). Die geteilte Heuristik
        // kappt zusätzlich bei 64 Zeichen — Präfixe darüber (Konzern-Roster
        // mit Firmenzusatz) gelten als Fließtext, nicht als Sprechername.
        guard TranscriptEventHeuristics.isProbableSpeakerName(speaker, minLength: 1, maxWords: 6) else {
            return nil
        }
        return (speaker, text)
    }
}

enum VTTCueParser {
    static func parse(_ raw: String) -> [VTTCue] {
        let blocks = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        var cues: [VTTCue] = []
        for block in blocks {
            guard let cue = makeCue(from: block) else { continue }
            cues.append(cue)
        }
        return cues
    }

    private static func makeCue(from block: String) -> VTTCue? {
        let lines = block
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard !lines.isEmpty else { return nil }

        var timingLine: String?
        var payloadLines: [String] = []
        var foundTiming = false
        for line in lines {
            if !foundTiming, line.contains("-->") {
                timingLine = line
                foundTiming = true
                continue
            }
            if foundTiming {
                payloadLines.append(line)
            }
        }
        guard let timing = timingLine,
              let (start, end) = parseTimingLine(timing) else { return nil }
        let payload = payloadLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return nil }
        return VTTCue(startSeconds: start, endSeconds: end, payload: payload)
    }

    private static func parseTimingLine(_ line: String) -> (TimeInterval, TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let lhs = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rhsRaw = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = rhsRaw.split(separator: " ", maxSplits: 1).first.map(String.init) ?? rhsRaw
        guard let start = parseTimestamp(lhs),
              let end = parseTimestamp(rhs) else { return nil }
        return (start, max(end, start))
    }

    static func parseTimestamp(_ value: String) -> TimeInterval? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = trimmed.split(separator: ":")
        guard segments.count == 2 || segments.count == 3 else { return nil }
        let secondsField = segments.last.map(String.init) ?? "0"
        let secondsParts = secondsField.split(separator: ".")
        guard let seconds = Double(secondsParts.first ?? "0") else { return nil }
        let millis: Double = {
            guard secondsParts.count == 2,
                  let raw = Double(secondsParts[1]) else { return 0 }
            let digits = secondsParts[1].count
            return raw / pow(10.0, Double(digits))
        }()

        if segments.count == 2 {
            guard let minutes = Double(segments[0]) else { return nil }
            return minutes * 60 + seconds + millis
        } else {
            guard let hours = Double(segments[0]),
                  let minutes = Double(segments[1]) else { return nil }
            return hours * 3600 + minutes * 60 + seconds + millis
        }
    }
}
