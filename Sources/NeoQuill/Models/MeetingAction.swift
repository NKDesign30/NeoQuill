import Foundation

enum MeetingActionKind: String, Codable, CaseIterable {
    case followUpEmail
    case followUpMeeting
    case jiraTicket
    case inboxTask
    case webhookPayload

    var displayName: String {
        switch self {
        case .followUpEmail: return "Follow-up Mail"
        case .followUpMeeting: return "Follow-up Meeting"
        case .jiraTicket: return "Jira Ticket"
        case .inboxTask: return "Action Inbox"
        case .webhookPayload: return "Webhook"
        }
    }

    var actionLabel: String {
        switch self {
        case .followUpEmail: return "Mail öffnen"
        case .followUpMeeting: return "Kalender öffnen"
        case .jiraTicket: return "Ticket kopieren"
        case .inboxTask: return "Aufgabe kopieren"
        case .webhookPayload: return "JSON kopieren"
        }
    }
}

struct MeetingAction: Identifiable, Codable, Hashable {
    let id: String
    let kind: MeetingActionKind
    let title: String
    let summary: String
    let body: String
    let assignee: String
    let due: String
    let source: String
    let confidence: Double
}

enum MeetingActionGenerator {
    static func suggest(for meeting: MeetingDetail, limit: Int = 6) -> [MeetingAction] {
        guard !meeting.processing else { return [] }

        var actions: [MeetingAction] = []
        if !meeting.tldr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append(followUpEmail(for: meeting))
        }

        if shouldSuggestFollowUpMeeting(meeting) {
            actions.append(followUpMeeting(for: meeting))
        }

        let openTasks = meeting.tasks.filter { $0.status == .open }
        for (index, task) in openTasks.prefix(3).enumerated() {
            actions.append(taskAction(for: task, meeting: meeting, index: index))
        }

        if !meeting.transcript.isEmpty || !meeting.tasks.isEmpty || !meeting.highlights.isEmpty {
            actions.append(webhookPayload(for: meeting))
        }

        return Array(actions.prefix(limit))
    }

    private static func followUpEmail(for meeting: MeetingDetail) -> MeetingAction {
        MeetingAction(
            id: "\(meeting.id)-action-follow-up-email",
            kind: .followUpEmail,
            title: "Follow-up Mail vorbereiten",
            summary: "Kurzfassung, Entscheidungen und offene Punkte als sendbarer Draft.",
            body: followUpBody(for: meeting),
            assignee: "ME",
            due: "",
            source: meeting.tldr,
            confidence: 0.9
        )
    }

    private static func followUpMeeting(for meeting: MeetingDetail) -> MeetingAction {
        MeetingAction(
            id: "\(meeting.id)-action-follow-up-meeting",
            kind: .followUpMeeting,
            title: "Follow-up Meeting planen",
            summary: "30-Minuten-Termin mit Agenda aus Summary und offenen Aufgaben.",
            body: agendaBody(for: meeting),
            assignee: "ME",
            due: "Nächster Werktag",
            source: meeting.highlights.first?.text ?? meeting.tldr,
            confidence: 0.78
        )
    }

    private static func taskAction(for task: ActionItem, meeting: MeetingDetail, index: Int) -> MeetingAction {
        let kind: MeetingActionKind = looksTechnical(task.task) ? .jiraTicket : .inboxTask
        return MeetingAction(
            id: "\(meeting.id)-action-task-\(index)-\(kind.rawValue)",
            kind: kind,
            title: kind == .jiraTicket ? "Jira Ticket: \(task.task)" : "Inbox-Aufgabe: \(task.task)",
            summary: kind == .jiraTicket ? "Ticket-Draft mit Meeting-Kontext." : "Aufgabe als kopierbare Inbox-Payload.",
            body: task.task,
            assignee: task.who,
            due: task.due,
            source: task.task,
            confidence: 0.82
        )
    }

    private static func webhookPayload(for meeting: MeetingDetail) -> MeetingAction {
        MeetingAction(
            id: "\(meeting.id)-action-webhook",
            kind: .webhookPayload,
            title: "Meeting an Automation senden",
            summary: "JSON-Payload für Make, Zapier, n8n oder eigene APIs.",
            body: meeting.tldr,
            assignee: "ME",
            due: "",
            source: "MeetingDetail",
            confidence: 0.7
        )
    }

    private static func followUpBody(for meeting: MeetingDetail) -> String {
        let decisions = meeting.highlights
            .filter { $0.tone == .brand }
            .map { "- \($0.text)" }
            .joined(separator: "\n")
        let tasks = meeting.tasks
            .filter { $0.status == .open }
            .map { "- \($0.task)" }
            .joined(separator: "\n")

        return """
        Hi,

        danke für das Gespräch. Kurz zusammengefasst:
        \(meeting.tldr)

        Entscheidungen:
        \(decisions.isEmpty ? "- Keine klare Entscheidung erkannt." : decisions)

        Offene Punkte:
        \(tasks.isEmpty ? "- Keine offenen Aufgaben erkannt." : tasks)

        Viele Grüße
        """
    }

    private static func agendaBody(for meeting: MeetingDetail) -> String {
        let tasks = meeting.tasks
            .filter { $0.status == .open }
            .map { "- \($0.task)" }
            .joined(separator: "\n")

        return """
        Agenda:
        - Kurzer Recap: \(meeting.title)
        - Offene Punkte klären
        \(tasks.isEmpty ? "- Nächste Schritte festlegen" : tasks)
        """
    }

    private static func shouldSuggestFollowUpMeeting(_ meeting: MeetingDetail) -> Bool {
        let hasOpenTasks = meeting.tasks.contains { $0.status == .open }
        let hasRiskOrDate = meeting.highlights.contains {
            $0.tone == .warning || $0.label.localizedCaseInsensitiveContains("Termin")
        }
        return hasOpenTasks || hasRiskOrDate
    }

    private static func looksTechnical(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        let markers = ["bug", "fix", "jira", "ticket", "dev", "api", "frontend", "backend", "deploy", "test", "bauen", "implementieren"]
        return markers.contains { lowercased.contains($0) }
    }
}
