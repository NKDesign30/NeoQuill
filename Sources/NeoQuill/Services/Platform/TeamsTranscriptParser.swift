import Foundation

enum TeamsTranscriptParser {
    private static let confidenceVTT: Double = 0.9
    private static let confidenceMetadata: Double = 0.96

    static func fromVTT(_ raw: String) throws -> [PlatformTranscriptEvent] {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PlatformParserError.empty
        }
        let cues = VTTCueParser.parse(raw)
        let events: [PlatformTranscriptEvent] = cues.compactMap { cue in
            let speaker = cue.voiceTagName ?? cue.colonSpeakerPrefix?.speaker
            let text = cue.voiceTagText ?? cue.colonSpeakerPrefix?.text ?? cue.payload
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty else { return nil }
            return PlatformTranscriptEvent(
                platform: .teams,
                speakerName: speaker,
                speakerId: nil,
                text: cleanText,
                startSeconds: cue.startSeconds,
                endSeconds: cue.endSeconds,
                confidence: confidenceVTT,
                rawPayload: cue.payload
            )
        }
        if events.isEmpty { throw PlatformParserError.empty }
        return events
    }

    static func fromMetadataContent(_ raw: String, referenceDate: Date? = nil) throws -> [PlatformTranscriptEvent] {
        guard let data = raw.data(using: .utf8) else {
            throw PlatformParserError.invalidEncoding
        }
        return try fromMetadataContent(data, referenceDate: referenceDate)
    }

    static func fromMetadataContent(_ data: Data, referenceDate: Date? = nil) throws -> [PlatformTranscriptEvent] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PlatformParserError.invalidJSON(String(describing: error))
        }

        let entries = extractEntries(from: json)
        guard !entries.isEmpty else { throw PlatformParserError.empty }

        let parsedDates = entries.compactMap { entry -> Date? in
            guard let raw = entry["startDateTime"] as? String else { return nil }
            return ISO8601.date(from: raw)
        }
        let reference = referenceDate ?? parsedDates.min() ?? Date()

        let events: [PlatformTranscriptEvent] = entries.compactMap { entry in
            guard let text = (entry["spokenText"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            guard let startRaw = entry["startDateTime"] as? String,
                  let start = ISO8601.date(from: startRaw) else { return nil }
            let endRaw = entry["endDateTime"] as? String
            let end = endRaw.flatMap(ISO8601.date(from:)) ?? start.addingTimeInterval(2.5)
            let speakerName = (entry["speakerName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let speakerId = (entry["speakerId"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let startSeconds = PlatformTimeBase.relativeSeconds(start: start, reference: reference)
            let endSeconds = PlatformTimeBase.relativeSeconds(
                end: end,
                reference: reference,
                minimumStart: startSeconds
            )
            return PlatformTranscriptEvent(
                platform: .teams,
                speakerName: speakerName,
                speakerId: speakerId,
                text: text,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                confidence: confidenceMetadata,
                rawPayload: text
            )
        }
        if events.isEmpty { throw PlatformParserError.empty }
        return events
    }

    private static func extractEntries(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] { return array }
        if let dict = json as? [String: Any] {
            if let value = dict["value"] as? [[String: Any]] { return value }
            if let entries = dict["entries"] as? [[String: Any]] { return entries }
            if let transcripts = dict["transcripts"] as? [[String: Any]] { return transcripts }
        }
        return []
    }
}
