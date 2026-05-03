import Foundation

enum GoogleMeetTranscriptParser {
    private static let confidence: Double = 0.95

    struct ParticipantSource {
        let resourceName: String
        let displayName: String
    }

    static func parse(
        entriesJSON: String,
        participantsJSON: String? = nil,
        referenceDate: Date? = nil
    ) throws -> [PlatformTranscriptEvent] {
        guard let entriesData = entriesJSON.data(using: .utf8) else {
            throw PlatformParserError.invalidEncoding
        }
        let participantsData = participantsJSON?.data(using: .utf8)
        return try parse(
            entriesData: entriesData,
            participantsData: participantsData,
            referenceDate: referenceDate
        )
    }

    static func parse(
        entriesData: Data,
        participantsData: Data? = nil,
        referenceDate: Date? = nil
    ) throws -> [PlatformTranscriptEvent] {
        let entries = try decodeEntries(entriesData)
        guard !entries.isEmpty else { throw PlatformParserError.empty }

        let participantMap = (try? participantsData.flatMap(decodeParticipants)) ?? [:]

        let parsedDates = entries.compactMap { entry -> Date? in
            guard let raw = entry["startTime"] as? String else { return nil }
            return ISO8601.date(from: raw)
        }
        let reference = referenceDate ?? parsedDates.min() ?? Date()

        let events: [PlatformTranscriptEvent] = entries.compactMap { entry in
            guard let text = (entry["text"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            guard let startRaw = entry["startTime"] as? String,
                  let start = ISO8601.date(from: startRaw) else { return nil }
            let endRaw = entry["endTime"] as? String
            let end = endRaw.flatMap(ISO8601.date(from:)) ?? start.addingTimeInterval(2.5)

            let participantResource = (entry["participant"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty
            let speakerName = participantResource
                .flatMap { participantMap[$0] }
                ?? (entry["speakerName"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty

            let startSeconds = PlatformTimeBase.relativeSeconds(start: start, reference: reference)
            let endSeconds = PlatformTimeBase.relativeSeconds(
                end: end,
                reference: reference,
                minimumStart: startSeconds
            )
            return PlatformTranscriptEvent(
                platform: .meet,
                speakerName: speakerName,
                speakerId: participantResource,
                text: text,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                confidence: confidence,
                rawPayload: text
            )
        }
        if events.isEmpty { throw PlatformParserError.empty }
        return events
    }

    private static func decodeEntries(_ data: Data) throws -> [[String: Any]] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PlatformParserError.invalidJSON("entries: \(String(describing: error))")
        }
        if let array = json as? [[String: Any]] { return array }
        if let dict = json as? [String: Any] {
            if let entries = dict["entries"] as? [[String: Any]] { return entries }
            if let transcriptEntries = dict["transcriptEntries"] as? [[String: Any]] { return transcriptEntries }
        }
        return []
    }

    private static func decodeParticipants(_ data: Data) throws -> [String: String] {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PlatformParserError.invalidJSON("participants: \(String(describing: error))")
        }
        let raw = (json as? [[String: Any]])
            ?? (json as? [String: Any])?["participants"] as? [[String: Any]]
            ?? []
        var map: [String: String] = [:]
        for item in raw {
            let resource = (item["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !resource.isEmpty else { continue }
            let displayName = displayName(from: item)
            guard let displayName, !displayName.isEmpty else { continue }
            map[resource] = displayName
        }
        return map
    }

    private static func displayName(from participant: [String: Any]) -> String? {
        if let user = participant["user"] as? [String: Any],
           let name = (user["displayName"] as? String)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let signed = participant["signedinUser"] as? [String: Any],
           let name = (signed["displayName"] as? String)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let anonymous = participant["anonymousUser"] as? [String: Any],
           let name = (anonymous["displayName"] as? String)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let phone = participant["phoneUser"] as? [String: Any],
           let name = (phone["displayName"] as? String)?
               .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        if let direct = (participant["displayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !direct.isEmpty {
            return direct
        }
        return nil
    }
}
