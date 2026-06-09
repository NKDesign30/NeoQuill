import Foundation

/// Stateless format-detector + parser-router. Liest eine Plattform-Transkriptdatei,
/// erkennt das Format anhand von Extension + Content-Sniff, und gibt die geparsten
/// Events plus die ermittelte Plattform zurück. Side-Effects (Re-Merge + Persist)
/// laufen ueber `RecordingController.applyPlatformImport`.
enum PlatformImportService {
    enum ImportError: LocalizedError, Equatable {
        case unreadable
        case unsupportedFormat
        case empty
        case parser(String)
        case licenseBlocked

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "Datei konnte nicht gelesen werden."
            case .unsupportedFormat:
                return "Format wird nicht unterstützt. Erwartet: .vtt oder .json (Teams/Meet/Zoom)."
            case .empty:
                return "Keine Transkript-Einträge in der Datei gefunden."
            case .parser(let detail):
                return "Parser-Fehler: \(detail)"
            case .licenseBlocked:
                return "Plattform-Import ist Pro-Feature. Aktiviere deine Lizenz oder starte den Trial."
            }
        }
    }

    struct Outcome {
        let platform: Platform
        let events: [PlatformTranscriptEvent]
    }

    static func detectAndParse(url: URL, fallbackPlatform: Platform = .meet) throws -> Outcome {
        guard let data = try? Data(contentsOf: url) else {
            throw ImportError.unreadable
        }
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent.lowercased()

        switch ext {
        case "vtt":
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.unreadable
            }
            let platform = vttPlatform(filename: filename, content: text, fallback: fallbackPlatform)
            let events = PlatformTranscriptParser.parseWebVTT(text, platform: platform)
            guard !events.isEmpty else { throw ImportError.empty }
            return Outcome(platform: platform, events: events)

        case "json":
            return try parseJSON(data: data, filename: filename)

        default:
            throw ImportError.unsupportedFormat
        }
    }

    private static func parseJSON(data: Data, filename: String) throws -> Outcome {
        let kind = sniffJSONKind(data: data, filename: filename)
        do {
            switch kind {
            case .teamsMetadata:
                let events = try PlatformTranscriptParser.parseTeamsMetadataContent(data)
                guard !events.isEmpty else { throw ImportError.empty }
                return Outcome(platform: .teams, events: events)

            case .meetEntries:
                let events = try PlatformTranscriptParser.parseGoogleMeetEntries(
                    entriesData: data,
                    participantsData: nil
                )
                guard !events.isEmpty else { throw ImportError.empty }
                return Outcome(platform: .meet, events: events)

            case .zoomTimeline:
                let events = try PlatformTranscriptParser.parseZoomTimeline(data)
                guard !events.isEmpty else { throw ImportError.empty }
                return Outcome(platform: .zoom, events: events)

            case .unknown:
                throw ImportError.unsupportedFormat
            }
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.parser(String(describing: error))
        }
    }

    private enum JSONKind {
        case teamsMetadata
        case meetEntries
        case zoomTimeline
        case unknown
    }

    private static func sniffJSONKind(data: Data, filename: String) -> JSONKind {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return .unknown
        }
        let dict = root as? [String: Any] ?? [:]
        let arr = root as? [[String: Any]] ?? []
        let allDicts = !arr.isEmpty ? arr : flatten(dict)

        let hasSpokenText = allDicts.contains { $0["spokenText"] != nil }
        let hasMeetParticipant = allDicts.contains { $0["participant"] is String }
        let hasTimelineKey = dict["timeline"] != nil
        let hasZoomFields = allDicts.contains {
            $0["user_name"] != nil || $0["speaker_name"] != nil || $0["end_ts"] != nil || $0["users"] is [Any]
        }

        if hasSpokenText { return .teamsMetadata }
        if hasMeetParticipant { return .meetEntries }
        if hasTimelineKey || hasZoomFields { return .zoomTimeline }

        if filename.contains("teams") { return .teamsMetadata }
        if filename.contains("meet") { return .meetEntries }
        if filename.contains("zoom") { return .zoomTimeline }
        return .unknown
    }

    private static func flatten(_ value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            return [dict] + dict.values.flatMap(flatten)
        }
        if let array = value as? [Any] {
            return array.flatMap(flatten)
        }
        return []
    }

    private static func vttPlatform(filename: String, content: String, fallback: Platform) -> Platform {
        if filename.contains("teams") { return .teams }
        if filename.contains("zoom") { return .zoom }
        if filename.contains("meet") || filename.contains("google") { return .meet }
        if content.contains("<v ") { return .teams }
        return fallback
    }
}
