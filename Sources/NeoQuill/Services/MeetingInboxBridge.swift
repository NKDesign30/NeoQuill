import Foundation

/// Brücke von NeoQuill-Meetings zur Neo Action-Inbox. Pro ActionItem ein Ticket
/// mit stabiler sourceId (`neoquill:<meetingId>:<itemId>`), damit ein zweites
/// Senden derselben Aufgabe sie nicht dupliziert, sondern im Backend nur
/// aktualisiert.
enum MeetingInboxBridge {

    static func sendMeetingAction(
        _ action: MeetingAction,
        from meeting: MeetingDetail,
        client: NeonInboxClient = NeonInboxClient()
    ) async throws -> NeonInboxClient.Result {
        try await client.ingest(ingest(for: action, from: meeting))
    }

    static func ingest(for action: MeetingAction, from meeting: MeetingDetail) -> NeonInboxClient.Ingest {
        let sourceId = NeonInboxClient.sourceId("neoquill", meeting.id, action.id)
        return NeonInboxClient.Ingest(
            source: .neoquill,
            sourceId: sourceId,
            title: clampTitle(action.title),
            body: skillBridgeBody(for: action, meeting: meeting),
            priorityHint: priority(for: action),
            labels: labels(for: action)
        )
    }

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
        Aufgabe aus NeoQuill-Meeting „\(meeting.title)“.
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

    private static func labels(for action: MeetingAction) -> [String] {
        switch action.kind {
        case .followUpEmail: return ["neoquill", "meeting", "action", "skill:gog", "gmail"]
        case .followUpMeeting: return ["neoquill", "meeting", "action", "skill:gog", "calendar"]
        case .jiraTicket: return ["neoquill", "meeting", "action", "skill:jira", "jira"]
        case .inboxTask: return ["neoquill", "meeting", "action", "inbox"]
        case .webhookPayload: return ["neoquill", "meeting", "action", "webhook"]
        }
    }

    private static func priority(for action: MeetingAction) -> NeonInboxClient.Priority? {
        action.kind == .jiraTicket ? .high : .medium
    }

    private static func skillBridgeBody(for action: MeetingAction, meeting: MeetingDetail) -> String {
        """
        Aktion aus NeoQuill-Meeting „\(meeting.title)“.

        Ziel: \(bridgeTarget(for: action.kind))
        Aktionstyp: \(action.kind.displayName)
        Titel: \(action.title)
        Inhalt:
        \(action.body)

        Assignee: \(ownerName(for: action, in: meeting))
        Fällig: \(action.due.isEmpty ? "—" : action.due)
        Confidence: \(Int(action.confidence * 100))%

        Meeting-Kontext:
        \(meeting.dateLong) · \(meeting.timeRange) · \(meeting.duration)
        TL;DR: \(meeting.tldr)

        Quelle:
        \(action.source)
        """
    }

    private static func bridgeTarget(for kind: MeetingActionKind) -> String {
        switch kind {
        case .followUpEmail: return "Gmail-Draft über gog erstellen. Nicht direkt senden."
        case .followUpMeeting: return "Kalender-Event über gog erstellen."
        case .jiraTicket: return "Jira-Ticket über lokale Jira-CLI oder Jira-Skill erstellen."
        case .inboxTask: return "Neo-Inbox-Aufgabe erstellen oder übernehmen."
        case .webhookPayload: return "Webhook/Automation-Payload prüfen und ausführen, falls konfiguriert."
        }
    }

    private static func ownerName(for item: ActionItem, in meeting: MeetingDetail) -> String {
        meeting.participants.first(where: { $0.id == item.who })?.name ?? item.who
    }

    private static func ownerName(for action: MeetingAction, in meeting: MeetingDetail) -> String {
        meeting.participants.first(where: { $0.id == action.assignee })?.name ?? action.assignee
    }
}
