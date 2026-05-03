import Foundation
import EventKit

// EventKit-Service der den aktuell laufenden Kalender-Termin findet und die
// Teilnehmer-Namen als Pool zurueckgibt. Wird vom RecordingController
// genutzt um anonyme Diarization-Cluster (`S1/S2/S3`) gegen einen erwarteten
// Personenkreis zu matchen.
//
// Permissions: macOS 14+ braucht `requestFullAccessToEvents`. Ohne Zustimmung
// liefert der Service einfach leere Pools — kein Hard-Fail.

@MainActor
final class CalendarParticipantsService: ObservableObject {

    @Published private(set) var lastError: String?

    private let store: EKEventStore
    private var permissionGranted = false

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    /// Fragt nach Vollzugriff. Idempotent — kann beliebig oft aufgerufen werden.
    @discardableResult
    func ensureAccess() async -> Bool {
        if permissionGranted { return true }
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            permissionGranted = true
            return true
        case .denied, .restricted, .writeOnly:
            permissionGranted = false
            lastError = "Kalender-Zugriff fehlt — bitte in Systemeinstellungen aktivieren."
            return false
        case .notDetermined:
            do {
                let granted = try await store.requestFullAccessToEvents()
                permissionGranted = granted
                if !granted { lastError = "Kalender-Zugriff wurde abgelehnt." }
                return granted
            } catch {
                lastError = "Kalender-Permission-Fehler: \(error.localizedDescription)"
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Liefert Teilnehmer-Namen des Termins der jetzt laeuft (within ±5min Fenster).
    /// Eigene Teilnahme + bekannte Self-Names werden gefiltert.
    func participantsForCurrentMeeting(now: Date = Date()) async -> [String] {
        guard await ensureAccess() else { return [] }
        guard let event = currentEvent(at: now) else { return [] }
        return Self.attendeeNames(for: event)
    }

    /// Wie `participantsForCurrentMeeting`, gibt aber zusaetzlich Event-Titel
    /// fuer UI-Hinweise zurueck.
    func currentMeetingContext(now: Date = Date()) async -> (title: String, attendees: [String])? {
        guard await ensureAccess() else { return nil }
        guard let event = currentEvent(at: now) else { return nil }
        let names = Self.attendeeNames(for: event)
        return (event.title ?? "Meeting", names)
    }

    // MARK: - Internal

    private func currentEvent(at now: Date) -> EKEvent? {
        let window: TimeInterval = 5 * 60
        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-window),
            end: now.addingTimeInterval(window),
            calendars: calendars.isEmpty ? nil : calendars
        )
        let events = store.events(matching: predicate)
        return Self.bestActiveEvent(in: events, at: now)
    }

    /// Pure function: pickt aus einer Event-Liste das wahrscheinlichste
    /// "jetzt-laufende" Meeting. Kriterien (in dieser Reihenfolge):
    /// 1. Meeting umschliesst `now` und hat Teilnehmer
    /// 2. Meeting umschliesst `now` (auch ohne Attendees)
    /// 3. Naechster Termin der innerhalb von 5min beginnt
    nonisolated static func bestActiveEvent(in events: [EKEvent], at now: Date) -> EKEvent? {
        let candidates = events.map { event in
            EventCandidate(
                start: event.startDate,
                end: event.endDate,
                hasAttendees: (event.attendees?.count ?? 0) > 0,
                payload: event
            )
        }
        return bestCandidate(in: candidates, at: now)?.payload
    }

    struct EventCandidate<Payload> {
        let start: Date
        let end: Date
        let hasAttendees: Bool
        let payload: Payload
    }

    /// EKEvent-freier Selektor — nutzbar in Tests ohne echte Calendar-Permissions.
    nonisolated static func bestCandidate<Payload>(
        in candidates: [EventCandidate<Payload>],
        at now: Date
    ) -> EventCandidate<Payload>? {
        let surrounding = candidates.filter { $0.start <= now && $0.end >= now }
        if let withAttendees = surrounding.first(where: \.hasAttendees) {
            return withAttendees
        }
        if let any = surrounding.first {
            return any
        }
        return candidates
            .filter { $0.start > now && $0.start.timeIntervalSince(now) <= 5 * 60 }
            .sorted { $0.start < $1.start }
            .first
    }

    nonisolated static func attendeeNames(for event: EKEvent) -> [String] {
        guard let attendees = event.attendees else { return [] }
        let raw = attendees.compactMap { participant -> String? in
            if participant.isCurrentUser { return nil }
            let name = participant.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let name, !name.isEmpty else { return nil }
            if SpeakerNameResolver.isHiddenIdentity(name) { return nil }
            return name
        }
        // Dedupe und stable order beibehalten.
        var seen: Set<String> = []
        var unique: [String] = []
        for name in raw where seen.insert(name.lowercased()).inserted {
            unique.append(name)
        }
        return unique
    }
}
