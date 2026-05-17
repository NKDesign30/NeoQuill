import AppKit
import Foundation

struct MeetingActionExecutionResult: Equatable {
    let message: String
}

enum MeetingActionExecutionError: LocalizedError {
    case unsupportedAction
    case couldNotOpenURL
    case couldNotWriteCalendarFile
    case couldNotEncodePayload

    var errorDescription: String? {
        switch self {
        case .unsupportedAction: return "Aktion wird noch nicht unterstützt."
        case .couldNotOpenURL: return "URL konnte nicht geöffnet werden."
        case .couldNotWriteCalendarFile: return "Kalenderdatei konnte nicht geschrieben werden."
        case .couldNotEncodePayload: return "Payload konnte nicht erzeugt werden."
        }
    }
}

enum MeetingActionExecutor {
    @MainActor
    static func execute(_ action: MeetingAction, meeting: MeetingDetail) throws -> MeetingActionExecutionResult {
        switch action.kind {
        case .followUpEmail:
            guard let url = mailtoURL(for: action, meeting: meeting),
                  NSWorkspace.shared.open(url) else {
                throw MeetingActionExecutionError.couldNotOpenURL
            }
            return MeetingActionExecutionResult(message: "Follow-up Mail geöffnet.")

        case .followUpMeeting:
            let url = try writeCalendarInvite(for: action, meeting: meeting)
            guard NSWorkspace.shared.open(url) else {
                throw MeetingActionExecutionError.couldNotOpenURL
            }
            return MeetingActionExecutionResult(message: "Kalenderdatei geöffnet.")

        case .jiraTicket:
            copy(jiraDraft(for: action, meeting: meeting))
            if let baseURL = configuredJiraURL() {
                NSWorkspace.shared.open(baseURL)
            }
            return MeetingActionExecutionResult(message: "Jira-Draft kopiert.")

        case .inboxTask:
            copy(inboxPayload(for: action, meeting: meeting))
            return MeetingActionExecutionResult(message: "Inbox-Aufgabe kopiert.")

        case .webhookPayload:
            copy(try webhookPayload(for: action, meeting: meeting))
            if let webhookURL = configuredWebhookURL() {
                NSWorkspace.shared.open(webhookURL)
            }
            return MeetingActionExecutionResult(message: "Webhook-JSON kopiert.")
        }
    }

    static func mailtoURL(for action: MeetingAction, meeting: MeetingDetail) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = UserDefaults.standard.stringOr(AppSettings.actionDefaultRecipient, default: "")
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Follow-up: \(meeting.title)"),
            URLQueryItem(name: "body", value: action.body),
        ]
        return components.url
    }

    static func calendarInviteContent(for action: MeetingAction, meeting: MeetingDetail, now: Date = Date()) -> String {
        let start = nextBusinessDayMorning(after: now)
        let end = start.addingTimeInterval(30 * 60)
        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//NeoQuill//Meeting Actions//DE
        BEGIN:VEVENT
        UID:\(action.id)@neoquill.local
        DTSTAMP:\(icsDate(now))
        DTSTART:\(icsDate(start))
        DTEND:\(icsDate(end))
        SUMMARY:\(icsEscape(action.title))
        DESCRIPTION:\(icsEscape(action.body + "\n\nQuelle: " + meeting.title))
        END:VEVENT
        END:VCALENDAR
        """
    }

    static func jiraDraft(for action: MeetingAction, meeting: MeetingDetail) -> String {
        """
        Summary: \(action.body)

        Meeting: \(meeting.title)
        Assignee: \(action.assignee)
        Due: \(action.due.isEmpty ? "n/a" : action.due)

        Context:
        \(action.source)

        Acceptance:
        - Klären und umsetzen
        - Ergebnis im Meeting-Kontext zurückmelden
        """
    }

    static func inboxPayload(for action: MeetingAction, meeting: MeetingDetail) -> String {
        """
        Aufgabe aus NeoQuill: \(action.body)
        Meeting: \(meeting.title)
        Owner: \(action.assignee)
        Fällig: \(action.due.isEmpty ? "n/a" : action.due)
        Quelle: \(action.source)
        """
    }

    static func webhookPayload(for action: MeetingAction, meeting: MeetingDetail) throws -> String {
        struct Payload: Encodable {
            let meetingId: String
            let meetingTitle: String
            let actionId: String
            let kind: String
            let title: String
            let body: String
            let assignee: String
            let due: String
            let confidence: Double
            let source: String
        }

        let payload = Payload(
            meetingId: meeting.id,
            meetingTitle: meeting.title,
            actionId: action.id,
            kind: action.kind.rawValue,
            title: action.title,
            body: action.body,
            assignee: action.assignee,
            due: action.due,
            confidence: action.confidence,
            source: action.source
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            throw MeetingActionExecutionError.couldNotEncodePayload
        }
        return json
    }

    private static func writeCalendarInvite(for action: MeetingAction, meeting: MeetingDetail) throws -> URL {
        let directory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = directory.appending(path: "NeoQuill-\(meeting.id)-follow-up.ics")
        do {
            try calendarInviteContent(for: action, meeting: meeting).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            throw MeetingActionExecutionError.couldNotWriteCalendarFile
        }
    }

    private static func configuredJiraURL() -> URL? {
        let raw = UserDefaults.standard.stringOr(AppSettings.actionJiraBaseURL, default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private static func configuredWebhookURL() -> URL? {
        let raw = UserDefaults.standard.stringOr(AppSettings.actionWebhookURL, default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private static func nextBusinessDayMorning(after date: Date) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var candidate = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(24 * 60 * 60)
        while calendar.isDateInWeekend(candidate) {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate.addingTimeInterval(24 * 60 * 60)
        }
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: candidate) ?? candidate
    }

    private static func icsDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func icsEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
