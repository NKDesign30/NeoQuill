import Foundation

/// Brücke von NeoQuill-Meetings zur Neo Action-Inbox. Pro ActionItem ein Ticket
/// mit stabiler sourceId (`neoquill:<meetingId>:<itemId>`), damit ein zweites
/// Senden derselben Aufgabe sie nicht dupliziert, sondern im Backend nur
/// aktualisiert.
enum MeetingInboxBridge {

    static func sendActionItem(
        _ item: ActionItem,
        from meeting: MeetingDetail,
        client: NeonInboxClient = NeonInboxClient()
    ) async throws -> NeonInboxClient.Result {
        let title = clampTitle(item.task)
        let owner = ownerName(for: item, in: meeting)
        let due = item.due.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueLine = due.isEmpty ? "—" : due

        let body = """
        Aufgabe aus NeoQuill-Meeting „\(meeting.title)".
        Owner: \(owner)
        Fällig: \(dueLine)
        Status im Meeting: \(item.status.rawValue)

        Quelle: \(meeting.title) · \(meeting.dateLong) · \(meeting.timeRange)
        """

        let sourceId = NeonInboxClient.sourceId("neoquill", meeting.id, item.id)
        let ingest = NeonInboxClient.Ingest(
            source: .neoquill,
            sourceId: sourceId,
            title: title,
            body: body,
            priorityHint: nil,
            labels: ["neoquill", "meeting"]
        )
        return try await client.ingest(ingest)
    }

    private static func clampTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Aufgabe aus NeoQuill-Meeting" }
        return trimmed.count <= 180 ? trimmed : String(trimmed.prefix(180))
    }

    private static func ownerName(for item: ActionItem, in meeting: MeetingDetail) -> String {
        meeting.participants.first(where: { $0.id == item.who })?.name ?? item.who
    }
}
