import Foundation
import SQLite3

/// FTS5 Volltextsuche über Meeting-Transkripte
final class SearchService: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.neon.neoquill.search", qos: .utility)

    struct SearchResult: Identifiable {
        let id: String
        let filename: String
        let name: String
        let date: Date
        let snippet: String
        let rank: Double
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let quillDir = appSupport.appendingPathComponent("Quill")
        try? FileManager.default.createDirectory(at: quillDir, withIntermediateDirectories: true)
        dbPath = quillDir.appendingPathComponent("meetings.db").path
    }

    /// Initialisiert DB + FTS5 Schema
    func initialize() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
                    print("[Quill Search] DB öffnen fehlgeschlagen: \(dbPath)")
                    continuation.resume()
                    return
                }

                let schema = """
                CREATE TABLE IF NOT EXISTS meetings (
                    id TEXT PRIMARY KEY,
                    filename TEXT NOT NULL,
                    name TEXT NOT NULL,
                    date TEXT NOT NULL,
                    content TEXT NOT NULL,
                    transcript TEXT,
                    indexed_at TEXT NOT NULL
                );
                CREATE VIRTUAL TABLE IF NOT EXISTS meetings_fts USING fts5(
                    name, content, transcript,
                    content='meetings',
                    content_rowid='rowid'
                );
                CREATE TRIGGER IF NOT EXISTS meetings_ai AFTER INSERT ON meetings BEGIN
                    INSERT INTO meetings_fts(rowid, name, content, transcript)
                    VALUES (new.rowid, new.name, new.content, new.transcript);
                END;
                CREATE TRIGGER IF NOT EXISTS meetings_ad AFTER DELETE ON meetings BEGIN
                    INSERT INTO meetings_fts(meetings_fts, rowid, name, content, transcript)
                    VALUES ('delete', old.rowid, old.name, old.content, old.transcript);
                END;
                CREATE TRIGGER IF NOT EXISTS meetings_au AFTER UPDATE ON meetings BEGIN
                    INSERT INTO meetings_fts(meetings_fts, rowid, name, content, transcript)
                    VALUES ('delete', old.rowid, old.name, old.content, old.transcript);
                    INSERT INTO meetings_fts(rowid, name, content, transcript)
                    VALUES (new.rowid, new.name, new.content, new.transcript);
                END;
                """

                var errMsg: UnsafeMutablePointer<CChar>?
                if sqlite3_exec(db, schema, nil, nil, &errMsg) != SQLITE_OK {
                    let err = errMsg.map { String(cString: $0) } ?? "unbekannt"
                    print("[Quill Search] Schema Fehler: \(err)")
                    sqlite3_free(errMsg)
                }

                print("[Quill Search] DB initialisiert: \(dbPath)")
                continuation.resume()
            }
        }
    }

    /// Indexiert alle bestehenden Meetings aus dem meetings/ Ordner
    func indexAllMeetings() async {
        let dir = PostProcessor.meetingsDir
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }

        let mdFiles = files.filter { $0.hasSuffix(".md") }
        var indexed = 0

        for file in mdFiles {
            let fileId = String(file.dropLast(3))
            let path = "\(dir)/\(file)"

            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }

            if isIndexed(fileId) { continue }

            var name = fileId
            for line in content.components(separatedBy: "\n") {
                if line.hasPrefix("# ") {
                    name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            let dateStr = String(fileId.prefix(10))
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let date = formatter.date(from: dateStr) ?? Date()

            var transcript: String?
            let jsonPath = "\(dir)/\(fileId).json"
            if let jsonData = FileManager.default.contents(atPath: jsonPath),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let segments = json["segments"] as? [[String: Any]] {
                transcript = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
            }

            insertMeeting(id: fileId, filename: file, name: name, date: date,
                          content: content, transcript: transcript)
            indexed += 1
        }

        if indexed > 0 {
            print("[Quill Search] \(indexed) Meetings indexiert")
        }
    }

    /// Importiert ein einzelnes neues Meeting
    func importMeeting(filename: String) async {
        let dir = PostProcessor.meetingsDir
        let fileId = String(filename.dropLast(3))
        let path = "\(dir)/\(filename)"

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        var name = fileId
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("# ") {
                name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        let dateStr = String(fileId.prefix(10))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: dateStr) ?? Date()

        var transcript: String?
        let jsonPath = "\(dir)/\(fileId).json"
        if let jsonData = FileManager.default.contents(atPath: jsonPath),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let segments = json["segments"] as? [[String: Any]] {
            transcript = segments.compactMap { $0["text"] as? String }.joined(separator: " ")
        }

        deleteMeeting(id: fileId)
        insertMeeting(id: fileId, filename: filename, name: name, date: date,
                      content: content, transcript: transcript)
    }

    /// FTS5 Volltextsuche
    func search(query: String) async -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard let db = db else {
                    continuation.resume(returning: [])
                    return
                }

                let ftsQuery = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")

                let sql = """
                SELECT m.id, m.filename, m.name, m.date,
                       snippet(meetings_fts, 1, '<b>', '</b>', '...', 40) as snippet,
                       bm25(meetings_fts) as rank
                FROM meetings_fts
                JOIN meetings m ON m.rowid = meetings_fts.rowid
                WHERE meetings_fts MATCH ?
                ORDER BY rank
                LIMIT 20
                """

                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                    continuation.resume(returning: [])
                    return
                }
                defer { sqlite3_finalize(stmt) }

                let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"

                var results: [SearchResult] = []

                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let filename = String(cString: sqlite3_column_text(stmt, 1))
                    let name = String(cString: sqlite3_column_text(stmt, 2))
                    let dateStr = String(cString: sqlite3_column_text(stmt, 3))
                    let snippet = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                    let rank = sqlite3_column_double(stmt, 5)
                    let date = formatter.date(from: dateStr) ?? Date()

                    results.append(SearchResult(
                        id: id, filename: filename, name: name,
                        date: date, snippet: snippet, rank: rank
                    ))
                }

                continuation.resume(returning: results)
            }
        }
    }

    // MARK: - Private

    private func isIndexed(_ id: String) -> Bool {
        guard let db = db else { return false }
        let sql = "SELECT 1 FROM meetings WHERE id = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func insertMeeting(id: String, filename: String, name: String, date: Date,
                                content: String, transcript: String?) {
        guard let db = db else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)

        let isoFormatter = ISO8601DateFormatter()
        let indexedAt = isoFormatter.string(from: Date())

        let sql = "INSERT OR REPLACE INTO meetings (id, filename, name, date, content, transcript, indexed_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, filename, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, dateStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, content, -1, SQLITE_TRANSIENT)
        if let transcript = transcript {
            sqlite3_bind_text(stmt, 6, transcript, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_text(stmt, 7, indexedAt, -1, SQLITE_TRANSIENT)

        sqlite3_step(stmt)
    }

    private func deleteMeeting(id: String) {
        guard let db = db else { return }
        let sql = "DELETE FROM meetings WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}
