import Foundation

enum PlatformParserError: Error, CustomStringConvertible, Equatable {
    case invalidEncoding
    case invalidJSON(String)
    case missingField(String)
    case empty

    var description: String {
        switch self {
        case .invalidEncoding:
            return "Konnte Quelle nicht als UTF-8 lesen."
        case .invalidJSON(let detail):
            return "JSON nicht parsbar: \(detail)"
        case .missingField(let field):
            return "Pflichtfeld fehlt: \(field)"
        case .empty:
            return "Quelle ist leer oder enthielt keine verwertbaren Einträge."
        }
    }
}

enum ISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = withFractional.date(from: trimmed) { return value }
        return plain.date(from: trimmed)
    }
}

enum PlatformTimeBase {
    static func relativeSeconds(start: Date, reference: Date) -> TimeInterval {
        max(0, start.timeIntervalSince(reference))
    }

    static func relativeSeconds(end: Date, reference: Date, minimumStart: TimeInterval) -> TimeInterval {
        max(minimumStart, end.timeIntervalSince(reference))
    }
}
