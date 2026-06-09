import Foundation

/// Drop-In Helper für Neo Action-Inbox. Wird identisch in NeoVoice und NeoQuill
/// genutzt. POST an `http://127.0.0.1:3850/api/action-inbox/tickets/ingest`.
/// Backend-Limits werden clientseitig geclampt (title 200, body 4000, label 60,
/// max 10 labels), damit kein 400 wegen Längen fliegt.
public struct NeonInboxClient: Sendable {

    public enum Source: String, Sendable {
        case neovoice
        case neoquill
        case neoinvoice
    }

    public enum Priority: String, Sendable {
        case low
        case medium
        case high
        case critical
    }

    public struct Ingest: Sendable, Equatable {
        public var source: Source
        public var sourceId: String
        public var title: String
        public var body: String?
        public var priorityHint: Priority?
        public var labels: [String]

        public init(
            source: Source,
            sourceId: String,
            title: String,
            body: String? = nil,
            priorityHint: Priority? = nil,
            labels: [String] = []
        ) {
            self.source = source
            self.sourceId = sourceId
            self.title = title
            self.body = body
            self.priorityHint = priorityHint
            self.labels = labels
        }
    }

    public struct Result: Sendable, Equatable {
        public let ticketId: String
        public let cardId: String
        public let created: Bool
    }

    public enum InboxError: Error, Sendable, Equatable {
        case invalidEndpoint
        case http(status: Int, body: String)
        case decode(String)
        case transport(String)
    }

    /// UserDefaults-Key, über den ein Nutzer einen eigenen Inbox-Endpoint setzt.
    /// Self-contained gehalten, damit der Client als Drop-In ohne `AppSettings` bleibt.
    public static let endpointDefaultsKey = "action_inbox_endpoint"

    /// Fallback, wenn kein eigener Endpoint konfiguriert ist (lokaler Neon-Stack).
    public static let defaultEndpoint: URL = {
        guard let url = URL(string: "http://127.0.0.1:3850/api/action-inbox/tickets/ingest") else {
            preconditionFailure("NeonInboxClient.defaultEndpoint URL string is not parseable")
        }
        return url
    }()

    /// Liest den vom Nutzer konfigurierten Endpoint aus den Defaults, sonst Fallback.
    public static func resolvedEndpoint(defaults: UserDefaults = .standard) -> URL {
        guard let raw = defaults.string(forKey: endpointDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw)
        else {
            return defaultEndpoint
        }
        return url
    }

    public let endpoint: URL
    public let timeout: TimeInterval
    private let session: URLSession

    public init(
        endpoint: URL? = nil,
        timeout: TimeInterval = 4.0,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint ?? NeonInboxClient.resolvedEndpoint()
        self.timeout = timeout
        self.session = session
    }

    public func ingest(_ ingest: Ingest) async throws -> Result {
        let payload: Data
        do {
            payload = try encodePayload(ingest)
        } catch {
            throw InboxError.transport("encode failed: \(error.localizedDescription)")
        }
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw InboxError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw InboxError.transport("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw InboxError.http(status: http.statusCode, body: body)
        }

        do {
            let decoded = try JSONDecoder().decode(IngestResponse.self, from: data)
            guard decoded.ok, let ticket = decoded.ticket, let card = decoded.card else {
                throw InboxError.decode(decoded.error ?? "missing ticket/card in response")
            }
            return Result(ticketId: ticket.id, cardId: card.id, created: decoded.created ?? false)
        } catch let error as InboxError {
            throw error
        } catch {
            throw InboxError.decode(error.localizedDescription)
        }
    }

    /// Deterministischer Source-Id-Builder. Gleiche Parts → gleicher Fingerprint
    /// im Backend → Dedupe. Sonderzeichen werden zu `_`, Limit 180 Zeichen
    /// (Backend max 200 — Puffer für Source-Prefix).
    public static func sourceId(_ parts: String...) -> String {
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        let cleaned = joined.unicodeScalars.map { scalar -> Character in
            let isAllowed = CharacterSet.alphanumerics.contains(scalar)
                || scalar == ":" || scalar == "-" || scalar == "_" || scalar == "."
            return isAllowed ? Character(scalar) : "_"
        }
        let result = String(cleaned)
        return result.count <= 180 ? result : String(result.prefix(180))
    }

    private func encodePayload(_ ingest: Ingest) throws -> Data {
        let payload = IngestPayload(
            source: ingest.source.rawValue,
            sourceId: clamp(ingest.sourceId, to: 200),
            title: clamp(ingest.title, to: 200),
            body: ingest.body.flatMap { raw in
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : clamp(cleaned, to: 4000)
            },
            priorityHint: ingest.priorityHint?.rawValue,
            labels: clampLabels(ingest.labels)
        )
        return try JSONEncoder().encode(payload)
    }

    private func clamp(_ text: String, to maxLength: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength))
    }

    private func clampLabels(_ labels: [String]) -> [String] {
        let cleaned = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { String($0.prefix(60)) }
        return Array(cleaned.prefix(10))
    }
}

private struct IngestPayload: Encodable {
    let source: String
    let sourceId: String
    let title: String
    let body: String?
    let priorityHint: String?
    let labels: [String]
}

private struct IngestResponse: Decodable {
    let ok: Bool
    let error: String?
    let created: Bool?
    let ticket: TicketRef?
    let card: CardRef?

    struct TicketRef: Decodable {
        let id: String
    }
    struct CardRef: Decodable {
        let id: String
    }
}
