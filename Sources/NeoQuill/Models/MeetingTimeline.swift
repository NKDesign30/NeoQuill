import Foundation

/// Die formatierten Zeit-/Datums-Felder eines Meetings, abgeleitet aus
/// Startzeitpunkt und Laufzeit.
///
/// Vorher lag dasselbe Präludium — Dauer, Uhrzeit, Datum (kurz/lang) und der
/// `"14:05 – 14:17"`-Zeitbereich — an drei Stellen im `RecordingController`
/// wortgleich, mit den `DateFormatter`-Definitionen als verstreute Controller-
/// Statics. Hier ist es ein testbarer Value-Type mit einer einzigen Quelle der
/// Formatierung.
struct MeetingTimeline {
    /// "12m 3s" oder "45s".
    let durationShort: String
    /// "14:05".
    let timeShort: String
    /// "09. Jun.".
    let dateShort: String
    /// "Montag, 09. Juni".
    let dateLong: String
    /// "14:05 – 14:17".
    let timeRange: String

    init(started: Date, runtime: TimeInterval) {
        durationShort = Self.durationShort(runtime)
        timeShort = Self.timeFormatter.string(from: started)
        dateShort = Self.dateShortFormatter.string(from: started)
        dateLong = Self.dateLongFormatter.string(from: started)
        let endDate = started.addingTimeInterval(runtime)
        timeRange = "\(timeShort) – \(Self.timeFormatter.string(from: endDate))"
    }

    /// "12m 3s" / "45s" — auch für Fälle ohne vollständige Timeline nutzbar.
    static func durationShort(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        if minutes == 0 { return "\(remainder)s" }
        return "\(minutes)m \(remainder)s"
    }

    /// "14:05" — für Fallback-Titel ("Aufnahme 14:05").
    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd. MMM."
        return f
    }()

    private static let dateLongFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, dd. MMMM"
        return f
    }()
}
