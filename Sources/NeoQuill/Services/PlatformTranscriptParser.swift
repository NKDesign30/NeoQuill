import Foundation

enum PlatformTranscriptParserError: Error, Equatable {
    case invalidEncoding
    case invalidJSON
}

enum PlatformTranscriptParser {
    static func parseWebVTT(_ text: String, platform: Platform) -> [PlatformTranscriptEvent] {
        VTTCueParser.parse(text).compactMap { cue in
            let parsed = parseSpeakerAndText(cue)
            guard !parsed.text.isEmpty else { return nil }
            return PlatformTranscriptEvent(
                platform: platform,
                speakerName: parsed.speakerName,
                speakerId: nil,
                text: parsed.text,
                startSeconds: cue.startSeconds,
                endSeconds: cue.endSeconds,
                confidence: parsed.speakerName == nil ? 0.82 : 0.94,
                rawPayload: cue.payload
            )
        }
    }

    static func parseWebVTT(_ data: Data, platform: Platform) throws -> [PlatformTranscriptEvent] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw PlatformTranscriptParserError.invalidEncoding
        }
        return parseWebVTT(text, platform: platform)
    }

    static func parseTeamsMetadataContent(_ data: Data) throws -> [PlatformTranscriptEvent] {
        try parseGenericJSON(
            data,
            platform: .teams,
            textKeys: ["spokenText", "text", "content"],
            speakerKeys: ["speakerName", "displayName", "speaker"],
            speakerIdKeys: ["speakerId", "userId", "participantId"],
            startKeys: ["startDateTime", "startTime", "start", "offset"],
            endKeys: ["endDateTime", "endTime", "end"]
        )
    }

    static func parseGoogleMeetEntries(entriesData: Data, participantsData: Data?) throws -> [PlatformTranscriptEvent] {
        let participantNames = try participantsData.map(parseGoogleParticipants) ?? [:]
        let root = try jsonRoot(entriesData)
        let dicts = candidateDictionaries(root, preferredKeys: ["transcriptEntries", "entries"])
        let rawEvents = dicts.compactMap { dict -> RawPlatformEvent? in
            guard let text = firstString(dict, keys: ["text", "spokenText", "content"])?.nilIfEmpty else { return nil }
            let participantId = firstString(dict, keys: ["participant", "participantName", "speakerId"])
            let speakerName = participantId.flatMap { participantNames[$0] }
                ?? firstString(dict, keys: ["speakerName", "displayName", "speaker"])
            return RawPlatformEvent(
                speakerName: speakerName,
                speakerId: participantId,
                text: text,
                start: firstTimeValue(dict, keys: ["startTime", "startDateTime", "start"]),
                end: firstTimeValue(dict, keys: ["endTime", "endDateTime", "end"]),
                rawPayload: jsonString(dict)
            )
        }
        return normalize(rawEvents, platform: .meet)
    }

    /// Einziger Zoom-Timeline-Parser. Deckt sowohl die flache Form
    /// (`speaker_name`/`text` pro Eintrag) als auch den strukturierten
    /// Zoom-Export mit `users[]`-Talking-State ab.
    ///
    /// Users-basierte Einträge sind strenger: sie brauchen einen Sprecher
    /// (sonst übersprungen) und behalten leere Turns als `[<Sprecher> sprach]`-
    /// Platzhalter, damit Sprecherwechsel im Transkript sichtbar bleiben. Zoom
    /// bekommt einheitlich confidence 0.78 (konservativer als die generische
    /// Default-Confidence, da Timeline-Exports weniger zuverlässig sind als VTT).
    static func parseZoomTimeline(_ data: Data) throws -> [PlatformTranscriptEvent] {
        let root = try jsonRoot(data)
        let dicts = candidateDictionaries(root, preferredKeys: ["transcriptEntries", "entries", "segments", "timeline", "items"])
        let rawEvents: [RawPlatformEvent] = dicts.compactMap { dict in
            let (speakerName, speakerId) = zoomSpeakerFields(from: dict)
            let text = firstString(dict, keys: ["text", "content", "transcript"])
            let start = firstTimeValue(dict, keys: ["startTime", "start_time", "start", "ts"])
            let end = firstTimeValue(dict, keys: ["endTime", "end_time", "end", "end_ts"])

            if dict["users"] is [Any] {
                guard let speakerName else { return nil }
                if text == nil {
                    return RawPlatformEvent(
                        speakerName: speakerName, speakerId: speakerId,
                        text: "[\(speakerName) sprach]", start: start, end: end, rawPayload: nil
                    )
                }
            }
            guard let text else { return nil }
            return RawPlatformEvent(
                speakerName: speakerName, speakerId: speakerId, text: text,
                start: start, end: end, rawPayload: jsonString(dict)
            )
        }
        return normalize(rawEvents, platform: .zoom, confidence: 0.78)
    }

    private static func zoomSpeakerFields(from dict: [String: Any]) -> (name: String?, id: String?) {
        if let users = dict["users"] as? [[String: Any]], !users.isEmpty {
            let active = users.first { ($0["talking"] as? Bool ?? false) } ?? users.first
            let name = active.flatMap { firstString($0, keys: ["user_name", "userName", "name", "speakerName", "speaker"]) }
            let id = active.flatMap { firstString($0, keys: ["user_id", "userId", "speakerId", "speaker_id", "id"]) }
            return (name, id)
        }
        let name = firstString(dict, keys: ["speakerName", "speaker_name", "speaker", "userName", "username", "name"])
        let id = firstString(dict, keys: ["speakerId", "speaker_id", "userId", "user_id"])
        return (name, id)
    }

    private static func parseGenericJSON(
        _ data: Data,
        platform: Platform,
        textKeys: [String],
        speakerKeys: [String],
        speakerIdKeys: [String],
        startKeys: [String],
        endKeys: [String]
    ) throws -> [PlatformTranscriptEvent] {
        let root = try jsonRoot(data)
        let rawEvents = candidateDictionaries(root, preferredKeys: ["transcriptEntries", "entries", "segments", "timeline", "items"])
            .compactMap { dict -> RawPlatformEvent? in
                guard let text = firstString(dict, keys: textKeys)?.nilIfEmpty else { return nil }
                return RawPlatformEvent(
                    speakerName: firstString(dict, keys: speakerKeys),
                    speakerId: firstString(dict, keys: speakerIdKeys),
                    text: text,
                    start: firstTimeValue(dict, keys: startKeys),
                    end: firstTimeValue(dict, keys: endKeys),
                    rawPayload: jsonString(dict)
                )
            }
        return normalize(rawEvents, platform: platform)
    }

    private static func parseGoogleParticipants(_ data: Data) throws -> [String: String] {
        let root = try jsonRoot(data)
        let dicts = candidateDictionaries(root, preferredKeys: ["participants"])
        var out: [String: String] = [:]
        for dict in dicts {
            guard let id = firstString(dict, keys: ["name", "participant", "id"]) else { continue }
            let nestedName = ["signedinUser", "anonymousUser", "phoneUser"]
                .compactMap { dict[$0] as? [String: Any] }
                .compactMap { firstString($0, keys: ["displayName"]) }
                .first
            if let name = nestedName ?? firstString(dict, keys: ["displayName"]) {
                out[id] = name
            }
        }
        return out
    }

    private static func normalize(
        _ rawEvents: [RawPlatformEvent],
        platform: Platform,
        confidence: Double = 0.94
    ) -> [PlatformTranscriptEvent] {
        let absoluteStarts = rawEvents.compactMap { event -> Date? in
            if case .absolute(let date)? = event.start { return date }
            return nil
        }
        let baseDate = absoluteStarts.min()
        return rawEvents.compactMap { raw in
            guard !raw.text.isEmpty else { return nil }
            let start = seconds(from: raw.start, baseDate: baseDate) ?? 0
            let end = seconds(from: raw.end, baseDate: baseDate) ?? max(start + estimatedDuration(raw.text), start)
            return PlatformTranscriptEvent(
                platform: platform,
                speakerName: raw.speakerName,
                speakerId: raw.speakerId,
                text: raw.text,
                startSeconds: start,
                endSeconds: end,
                confidence: confidence,
                rawPayload: raw.rawPayload
            )
        }
    }

    private static func jsonRoot(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PlatformTranscriptParserError.invalidJSON
        }
    }

    private static func candidateDictionaries(_ root: Any, preferredKeys: [String]) -> [[String: Any]] {
        if let array = root as? [[String: Any]] { return array }
        guard let dict = root as? [String: Any] else { return [] }
        for key in preferredKeys {
            if let array = dict[key] as? [[String: Any]] {
                return array
            }
        }
        return flattenDictionaries(dict)
    }

    private static func flattenDictionaries(_ value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            return [dict] + dict.values.flatMap(flattenDictionaries)
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenDictionaries)
        }
        return []
    }

    private static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let string = value as? String {
                return string.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func firstTimeValue(_ dict: [String: Any], keys: [String]) -> TimeValue? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let number = value as? NSNumber {
                return .relative(number.doubleValue)
            }
            if let string = value as? String {
                if let date = parseDate(string) {
                    return .absolute(date)
                }
                if let timestamp = parseTimestamp(string) {
                    return .relative(timestamp)
                }
                if let seconds = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    return .relative(seconds)
                }
            }
        }
        return nil
    }

    private static func seconds(from value: TimeValue?, baseDate: Date?) -> TimeInterval? {
        switch value {
        case .relative(let seconds):
            return seconds
        case .absolute(let date):
            guard let baseDate else { return 0 }
            return date.timeIntervalSince(baseDate)
        case .none:
            return nil
        }
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let timePart = cleaned.components(separatedBy: CharacterSet.whitespaces).first ?? cleaned
        let parts = timePart.split(separator: ":").map(String.init)
        guard parts.count >= 2 else { return nil }
        let secondsPart = parts.last ?? "0"
        let seconds = Double(secondsPart) ?? 0
        let minutes = Double(parts[parts.count - 2]) ?? 0
        let hours = parts.count >= 3 ? (Double(parts[parts.count - 3]) ?? 0) : 0
        return (hours * 3600) + (minutes * 60) + seconds
    }

    private static func parseSpeakerAndText(_ cue: VTTCue) -> (speakerName: String?, text: String) {
        if let name = cue.voiceTagName,
           let text = cue.voiceTagText?.removingHTMLTags() {
            return (name, text)
        }
        if let colon = cue.colonSpeakerPrefix {
            return (colon.speaker, colon.text.removingHTMLTags())
        }
        return parseSpeakerAndText(cue.payload)
    }

    private static func parseSpeakerAndText(_ raw: String) -> (speakerName: String?, text: String) {
        let withoutTags = raw.replacingOccurrences(of: "</v>", with: "")
        if let voiceStart = withoutTags.range(of: "<v "),
           let voiceEnd = withoutTags.range(of: ">", range: voiceStart.upperBound..<withoutTags.endIndex) {
            let name = String(withoutTags[voiceStart.upperBound..<voiceEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(withoutTags[voiceEnd.upperBound...])
                .removingHTMLTags()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (name.nilIfEmpty, text)
        }

        let cleaned = raw.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines)
        if let split = splitColonSpeaker(cleaned) {
            return split
        }
        let lines = cleaned
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count >= 2, isProbableSpeakerName(lines[0]) {
            return (lines[0], lines.dropFirst().joined(separator: " "))
        }
        return (nil, cleaned)
    }

    private static func splitColonSpeaker(_ text: String) -> (speakerName: String?, text: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let speaker = String(text[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isProbableSpeakerName(speaker), !body.isEmpty else { return nil }
        return (speaker, body)
    }

    private static func isProbableSpeakerName(_ text: String) -> Bool {
        TranscriptEventHeuristics.isProbableSpeakerName(text)
    }

    private static func estimatedDuration(_ text: String) -> TimeInterval {
        TranscriptEventHeuristics.estimatedDuration(for: text)
    }

    private static func jsonString(_ dict: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct RawPlatformEvent {
    let speakerName: String?
    let speakerId: String?
    let text: String
    let start: TimeValue?
    let end: TimeValue?
    let rawPayload: String?
}

private enum TimeValue {
    case relative(TimeInterval)
    case absolute(Date)
}

private extension String {
    func removingHTMLTags() -> String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
