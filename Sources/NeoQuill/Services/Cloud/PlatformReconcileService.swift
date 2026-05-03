import Foundation

// Holt für ein bestimmtes Meeting das offizielle Cloud-Transkript der jeweiligen
// Plattform und übersetzt es in unsere `PlatformTranscriptEvent`-Struktur. Die
// drei Clients sind bewusst klein gehalten und teilen sich Auth + Networking.
//
// Aktuell sind die Provider-Endpoints implementiert, aber ohne echte Tenant-
// Konfiguration nicht testbar (siehe CloudOAuthConfig). Sobald Niko Client-IDs
// hinterlegt + sich anmeldet, fliessen die Daten via PlatformImportService in
// MeetingStore zurück.

enum PlatformReconcileError: LocalizedError {
    case providerNotConnected(CloudProvider)
    case requestFailed(String)
    case noTranscriptAvailable

    var errorDescription: String? {
        switch self {
        case .providerNotConnected(let p): return "\(p.displayName) ist nicht verbunden — bitte in den Einstellungen anmelden."
        case .requestFailed(let m):        return "Cloud-Anfrage fehlgeschlagen: \(m)"
        case .noTranscriptAvailable:       return "Kein offizielles Transkript für dieses Meeting gefunden."
        }
    }
}

@MainActor
final class PlatformReconcileService {

    private let oauth: CloudOAuthService
    private let urlSession: URLSession

    init(oauth: CloudOAuthService, urlSession: URLSession = .shared) {
        self.oauth = oauth
        self.urlSession = urlSession
    }

    /// Holt das aktuellste Transkript für den Provider und konvertiert es.
    /// Erwartet: Plattform-Meeting-ID (Teams/Meet/Zoom-spezifisch).
    func fetchTranscript(provider: CloudProvider, externalMeetingId: String) async throws -> [PlatformTranscriptEvent] {
        guard oauth.isConnected(provider) else { throw PlatformReconcileError.providerNotConnected(provider) }
        let token = try await oauth.accessToken(for: provider)
        switch provider {
        case .teams:
            return try await fetchTeamsTranscript(meetingId: externalMeetingId, token: token)
        case .meet:
            return try await fetchMeetTranscript(conferenceId: externalMeetingId, token: token)
        case .zoom:
            return try await fetchZoomTranscript(meetingId: externalMeetingId, token: token)
        }
    }

    // MARK: - Teams (Microsoft Graph beta)

    private func fetchTeamsTranscript(meetingId: String, token: String) async throws -> [PlatformTranscriptEvent] {
        // Schritt 1: Liste aller Transkripte → nimm das aktuellste.
        let listURL = URL(string: "https://graph.microsoft.com/beta/me/onlineMeetings/\(meetingId)/transcripts")!
        let listData = try await get(url: listURL, token: token)
        struct TranscriptList: Decodable {
            struct Item: Decodable { let id: String; let createdDateTime: String? }
            let value: [Item]
        }
        let list = try JSONDecoder().decode(TranscriptList.self, from: listData)
        guard let latest = list.value.sorted(by: { ($0.createdDateTime ?? "") > ($1.createdDateTime ?? "") }).first else {
            throw PlatformReconcileError.noTranscriptAvailable
        }

        // Schritt 2: Content (text/vtt) downloaden.
        let contentURL = URL(string: "https://graph.microsoft.com/beta/me/onlineMeetings/\(meetingId)/transcripts/\(latest.id)/content?$format=text/vtt")!
        let contentData = try await get(url: contentURL, token: token, accept: "text/vtt")
        guard let vtt = String(data: contentData, encoding: .utf8) else {
            throw PlatformReconcileError.requestFailed("VTT war kein UTF-8")
        }
        return PlatformTranscriptParser.parseWebVTT(vtt, platform: .teams)
    }

    // MARK: - Google Meet (Conference Records API)

    private func fetchMeetTranscript(conferenceId: String, token: String) async throws -> [PlatformTranscriptEvent] {
        // Schritt 1: ListTranscripts.
        let listURL = URL(string: "https://meet.googleapis.com/v2/conferenceRecords/\(conferenceId)/transcripts")!
        let listData = try await get(url: listURL, token: token)
        struct TranscriptList: Decodable {
            struct Item: Decodable { let name: String }
            let transcripts: [Item]?
        }
        let list = try JSONDecoder().decode(TranscriptList.self, from: listData)
        guard let firstName = list.transcripts?.first?.name else {
            throw PlatformReconcileError.noTranscriptAvailable
        }

        // Schritt 2: ListTranscriptEntries.
        let entriesURL = URL(string: "https://meet.googleapis.com/v2/\(firstName)/entries?pageSize=500")!
        let entriesData = try await get(url: entriesURL, token: token)

        // Schritt 3: ListParticipants (separate API).
        let participantsURL = URL(string: "https://meet.googleapis.com/v2/conferenceRecords/\(conferenceId)/participants?pageSize=200")!
        let participantsData = try await get(url: participantsURL, token: token)

        return try PlatformTranscriptParser.parseGoogleMeetEntries(
            entriesData: entriesData,
            participantsData: participantsData
        )
    }

    // MARK: - Zoom Cloud Recording

    private func fetchZoomTranscript(meetingId: String, token: String) async throws -> [PlatformTranscriptEvent] {
        // Zoom liefert Recording-Files inkl. Transcript-Download-URL.
        let metaURL = URL(string: "https://api.zoom.us/v2/meetings/\(meetingId)/recordings")!
        let metaData = try await get(url: metaURL, token: token)
        struct Recordings: Decodable {
            struct File: Decodable {
                let file_type: String?
                let download_url: String?
            }
            let recording_files: [File]?
        }
        let payload = try JSONDecoder().decode(Recordings.self, from: metaData)
        guard let transcriptFile = payload.recording_files?.first(where: { ($0.file_type ?? "").uppercased() == "TRANSCRIPT" }),
              let downloadURLString = transcriptFile.download_url,
              let downloadURL = URL(string: downloadURLString) else {
            throw PlatformReconcileError.noTranscriptAvailable
        }
        let vttData = try await get(url: downloadURL, token: token, accept: "text/vtt")
        guard let vtt = String(data: vttData, encoding: .utf8) else {
            throw PlatformReconcileError.requestFailed("VTT war kein UTF-8")
        }
        return PlatformTranscriptParser.parseWebVTT(vtt, platform: .zoom)
    }

    // MARK: - HTTP helper

    private func get(url: URL, token: String, accept: String = "application/json") async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PlatformReconcileError.requestFailed("Keine HTTP-Antwort von \(url.host ?? "")")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw PlatformReconcileError.requestFailed("HTTP \(http.statusCode) — \(text.prefix(200))")
        }
        return data
    }
}
