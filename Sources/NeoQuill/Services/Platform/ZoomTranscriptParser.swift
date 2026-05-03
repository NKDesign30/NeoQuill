import Foundation

enum ZoomTranscriptParser {
    private static let confidenceVTT: Double = 0.9
    private static let confidenceTimeline: Double = 0.78

    static func fromVTT(_ raw: String) throws -> [PlatformTranscriptEvent] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformParserError.empty
        }
        let cues = VTTCueParser.parse(raw)
        let events: [PlatformTranscriptEvent] = cues.compactMap { cue in
            let prefix = cue.colonSpeakerPrefix
            let speaker = prefix?.speaker
            let text = (prefix?.text ?? cue.payload)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return PlatformTranscriptEvent(
                platform: .zoom,
                speakerName: speaker,
                speakerId: nil,
                text: text,
                startSeconds: cue.startSeconds,
                endSeconds: cue.endSeconds,
                confidence: confidenceVTT,
                rawPayload: cue.payload
            )
        }
        if events.isEmpty { throw PlatformParserError.empty }
        return events
    }

    static func fromTimeline(_ raw: String, referenceDate: Date? = nil) throws -> [PlatformTranscriptEvent] {
        guard let data = raw.data(using: .utf8) else {
            throw PlatformParserError.invalidEncoding
        }
        return try fromTimeline(data, referenceDate: referenceDate)
    }

    static func fromTimeline(_ data: Data, referenceDate: Date? = nil) throws -> [PlatformTranscriptEvent] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PlatformParserError.invalidJSON(String(describing: error))
        }

        let entries = extractTimelineEntries(json)
        guard !entries.isEmpty else { throw PlatformParserError.empty }

        let parsedDates = entries.compactMap { entry -> Date? in
            guard let raw = entry["ts"] as? String else { return nil }
            return ISO8601.date(from: raw)
        }
        let reference = referenceDate ?? parsedDates.min() ?? Date()

        let events: [PlatformTranscriptEvent] = entries.compactMap { entry in
            guard let ts = entry["ts"] as? String,
                  let date = ISO8601.date(from: ts) else { return nil }
            let users = (entry["users"] as? [[String: Any]]) ?? []
            let activeUser = users.first { ($0["talking"] as? Bool ?? true) } ?? users.first
            guard let speaker = (activeUser?["user_name"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty else { return nil }
            let speakerId = (activeUser?["user_id"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let text = (entry["text"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let cleanText = text.isEmpty ? "[\(speaker) sprach]" : text
            let startSeconds = PlatformTimeBase.relativeSeconds(start: date, reference: reference)
            let endRaw = entry["end_ts"] as? String
            let end = endRaw.flatMap(ISO8601.date(from:)) ?? date.addingTimeInterval(2.5)
            let endSeconds = PlatformTimeBase.relativeSeconds(
                end: end,
                reference: reference,
                minimumStart: startSeconds
            )
            return PlatformTranscriptEvent(
                platform: .zoom,
                speakerName: speaker,
                speakerId: speakerId,
                text: cleanText,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                confidence: confidenceTimeline,
                rawPayload: text.isEmpty ? nil : text
            )
        }
        if events.isEmpty { throw PlatformParserError.empty }
        return events
    }

    private static func extractTimelineEntries(_ json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] { return array }
        if let dict = json as? [String: Any] {
            if let timeline = dict["timeline"] as? [[String: Any]] { return timeline }
            if let segments = dict["segments"] as? [[String: Any]] { return segments }
        }
        return []
    }
}
