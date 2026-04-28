import Foundation
import SQLite3

// SQLite-WAL Backed Store für Meetings + Transkripte. Muesli-Pattern: kein CoreData,
// direkter sqlite3, WAL für Concurrency, JSON für strukturierte Felder.
//
// Aktuell: lazy-init, Schema-Migrations, Seed mit MockData beim ersten Start.
// Später: RecordingManager schreibt hier rein, UI liest aus Publishers.

final class MeetingStore: ObservableObject {

    @Published private(set) var meetings: [MeetingSummary] = []
    @Published private(set) var details: [String: MeetingDetail] = [:]

    private var db: OpaquePointer?
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("NeoQuill", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("meetings.sqlite")
        open()
        migrate()
        loadAll()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Schema

    private func open() {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            NSLog("[MeetingStore] open failed at " + url.path)
            return
        }
        runRaw("PRAGMA journal_mode = WAL;")
        runRaw("PRAGMA synchronous  = NORMAL;")
        runRaw("PRAGMA busy_timeout = 5000;")
        runRaw("PRAGMA foreign_keys = ON;")
    }

    private func migrate() {
        runRaw("""
            CREATE TABLE IF NOT EXISTS meeting (
                id            TEXT PRIMARY KEY,
                title         TEXT NOT NULL,
                date_short    TEXT NOT NULL,
                date_long     TEXT NOT NULL,
                time_short    TEXT NOT NULL,
                time_range    TEXT,
                duration      TEXT NOT NULL,
                platform      TEXT NOT NULL,
                word_count    INTEGER NOT NULL DEFAULT 0,
                grouping      TEXT NOT NULL,
                unread        INTEGER NOT NULL DEFAULT 0,
                created_at    REAL NOT NULL,
                tldr          TEXT,
                participants  TEXT,
                highlights    TEXT,
                tasks         TEXT,
                chapters      TEXT,
                transcript    TEXT
            );
        """)
    }

    @discardableResult
    private func runRaw(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    // MARK: - Seed / Load

    private func loadAll() {
        if rowCount() == 0 {
            seedMock()
        }
        readBackToPublished()
    }

    private func seedMock() {
        for m in MockData.meetings {
            insertSummary(m)
        }
        upsertDetail(MockData.activeMeeting)
    }

    private func rowCount() -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM meeting", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func readBackToPublished() {
        var summaries: [MeetingSummary] = []
        var stmt: OpaquePointer?
        let sql = "SELECT id,title,date_short,time_short,duration,platform,word_count,grouping,unread FROM meeting ORDER BY created_at DESC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id        = String(cString: sqlite3_column_text(stmt, 0))
                let title     = String(cString: sqlite3_column_text(stmt, 1))
                let dateShort = String(cString: sqlite3_column_text(stmt, 2))
                let timeShort = String(cString: sqlite3_column_text(stmt, 3))
                let dur       = String(cString: sqlite3_column_text(stmt, 4))
                let platStr   = String(cString: sqlite3_column_text(stmt, 5))
                let words     = Int(sqlite3_column_int(stmt, 6))
                let group     = String(cString: sqlite3_column_text(stmt, 7))
                let unread    = sqlite3_column_int(stmt, 8) == 1
                let platform  = Platform(rawValue: platStr) ?? .call
                summaries.append(.init(
                    id: id, title: title, date: dateShort, time: timeShort,
                    duration: dur, platform: platform, wordCount: words,
                    group: group, participantIds: [], unread: unread
                ))
            }
        }
        sqlite3_finalize(stmt)

        DispatchQueue.main.async {
            self.meetings = summaries
        }
    }

    // MARK: - Writes (vorerst nur intern; später vom RecordingManager genutzt)

    /// Public Insert: schreibt Summary + Detail und published meetings neu.
    func insert(summary: MeetingSummary, detail: MeetingDetail) {
        insertSummary(summary)
        upsertDetail(detail)
        readBackToPublished()
    }

    private func insertSummary(_ m: MeetingSummary) {
        let sql = """
            INSERT OR REPLACE INTO meeting
            (id,title,date_short,date_long,time_short,duration,platform,word_count,grouping,unread,created_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, m.id)
        bind(stmt, 2, m.title)
        bind(stmt, 3, m.date)
        bind(stmt, 4, m.date)
        bind(stmt, 5, m.time)
        bind(stmt, 6, m.duration)
        bind(stmt, 7, m.platform.rawValue)
        sqlite3_bind_int(stmt, 8, Int32(m.wordCount))
        bind(stmt, 9, m.group)
        sqlite3_bind_int(stmt, 10, m.unread ? 1 : 0)
        sqlite3_bind_double(stmt, 11, Date().timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    private func upsertDetail(_ d: MeetingDetail) {
        let encoder = JSONEncoder()
        let sql = """
            UPDATE meeting SET
              date_long = ?, time_range = ?, tldr = ?,
              participants = ?, highlights = ?, tasks = ?, chapters = ?, transcript = ?
            WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, d.dateLong)
        bind(stmt, 2, d.timeRange)
        bind(stmt, 3, d.tldr)
        bind(stmt, 4, jsonString(d.participants, encoder))
        bind(stmt, 5, jsonString(d.highlights,   encoder))
        bind(stmt, 6, jsonString(d.tasks,        encoder))
        bind(stmt, 7, jsonString(d.chapters,     encoder))
        bind(stmt, 8, jsonString(d.transcript,   encoder))
        bind(stmt, 9, d.id)
        sqlite3_step(stmt)
    }

    private func jsonString<T: Codable>(_ value: T, _ encoder: JSONEncoder) -> String {
        guard let data = try? encoder.encode(value),
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }

    private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }
}
