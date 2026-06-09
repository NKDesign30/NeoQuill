import Foundation
import SQLite3

// SQLite-WAL Backed Store für Meetings + Transkripte. Muesli-Pattern: kein CoreData,
// direkter sqlite3, WAL für Concurrency, JSON für strukturierte Felder.
//
// Aktuell: lazy-init, Schema-Migrations, echte Meeting-Daten.
// RecordingController schreibt hier rein, UI liest aus Publishers.

final class MeetingStore: ObservableObject {

    @Published private(set) var meetings: [MeetingSummary] = []
    @Published private(set) var details: [String: MeetingDetail] = [:]

    private var db: OpaquePointer?
    private let url: URL

    static func applicationSupportDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("NeoQuill", isDirectory: true)
    }

    static func databaseURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("meetings.sqlite")
    }

    init(url: URL? = nil) {
        let databaseURL = url ?? Self.databaseURL()
        let dir = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = databaseURL
        open()
        migrate()
        cleanupGarbageMeetings()
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
        // Spalten die später dazugekommen sind. ALTER TABLE ist idempotent
        // wenn wir den Fehler schlucken — Spalte existiert dann schon.
        runRaw("ALTER TABLE meeting ADD COLUMN audio_url TEXT;")
        runRaw("ALTER TABLE meeting ADD COLUMN processing INTEGER NOT NULL DEFAULT 0;")
        // `lifecycle` ist die typisierte Nachfolge von `processing` (siehe
        // MeetingLifecycle). NULL bei Altzeilen → wird beim Lesen aus
        // `processing` abgeleitet. `processing` bleibt parallel befüllt
        // (computed aus lifecycle) für Rückwärtskompatibilität/Rollback.
        runRaw("ALTER TABLE meeting ADD COLUMN lifecycle TEXT;")
        // Zähler für unterbrochene Transkriptions-Versuche. Begrenzt das
        // Auto-Recovery (siehe RecordingController.recoverOrphanedTranscripts),
        // damit ein dauerhaft scheiternder Lauf nicht endlos neu startet.
        runRaw("ALTER TABLE meeting ADD COLUMN transcribe_attempts INTEGER NOT NULL DEFAULT 0;")
    }

    @discardableResult
    private func runRaw(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    /// Putzt Meetings aus früheren Test-Runs raus, deren Whisper-Output nicht
    /// gefiltert wurde — Special-Tokens wie `<|startoftranscript|>` erscheinen
    /// dann als Titel/TLDR. Idempotent, läuft bei jedem Boot.
    private func cleanupGarbageMeetings() {
        runRaw("""
            DELETE FROM meeting WHERE
              title LIKE '<|%' OR
              tldr  LIKE '<|%' OR
              transcript LIKE '%<|startoftranscript%' OR
              transcript LIKE '%<|endoftext|%';
        """)
    }

    /// Löscht alle echten Meeting-Daten ohne Demo-Re-Seed. Für Kunden-/Privacy-Reset.
    func deleteAllMeetings() {
        runRaw("DELETE FROM meeting;")
        readBackToPublished()
    }

    func clearAudioURLs() {
        runRaw("UPDATE meeting SET audio_url = NULL;")
        readBackToPublished()
    }

    // MARK: - Transkriptions-Versuche (Recovery-Bound)

    /// Aktueller Zähler unterbrochener Transkriptions-Versuche eines Meetings.
    func transcribeAttempts(for id: String) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT transcribe_attempts FROM meeting WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        bind(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    /// Erhöht den Versuchszähler um 1 und gibt den neuen Wert zurück.
    @discardableResult
    func bumpTranscribeAttempts(for id: String) -> Int {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE meeting SET transcribe_attempts = transcribe_attempts + 1 WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return transcribeAttempts(for: id)
    }

    /// Setzt den Versuchszähler nach erfolgreicher Transkription zurück.
    func resetTranscribeAttempts(for id: String) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "UPDATE meeting SET transcribe_attempts = 0 WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            bind(stmt, 1, id)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - Seed / Load

    private func loadAll() {
        // Frühere Versionen seedeten Mocks beim ersten Start. Der Standard ist jetzt real
        // aufnehmen, kein Demo-Material — bei leerer DB bleibt die Sidebar leer.
        readBackToPublished()
    }

    private func readBackToPublished() {
        var summaries: [MeetingSummary] = []
        var detailMap: [String: MeetingDetail] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT id,title,date_short,date_long,time_short,time_range,duration,platform,word_count,grouping,unread,tldr,participants,highlights,tasks,chapters,transcript,audio_url,processing,lifecycle FROM meeting ORDER BY created_at DESC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let decoder = JSONDecoder()
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id         = String(cString: sqlite3_column_text(stmt, 0))
                let title      = String(cString: sqlite3_column_text(stmt, 1))
                let dateShort  = String(cString: sqlite3_column_text(stmt, 2))
                let dateLong   = String(cString: sqlite3_column_text(stmt, 3))
                let timeShort  = String(cString: sqlite3_column_text(stmt, 4))
                let timeRange  = textOrNil(stmt, 5) ?? ""
                let dur        = String(cString: sqlite3_column_text(stmt, 6))
                let platStr    = String(cString: sqlite3_column_text(stmt, 7))
                let words      = Int(sqlite3_column_int(stmt, 8))
                let group      = String(cString: sqlite3_column_text(stmt, 9))
                let unread     = sqlite3_column_int(stmt, 10) == 1
                let tldr       = textOrNil(stmt, 11) ?? ""
                let participants  = decode([Participant].self, stmt: stmt, idx: 12, decoder: decoder) ?? []
                let highlights = decode([Highlight].self,    stmt: stmt, idx: 13, decoder: decoder) ?? []
                let tasks      = decode([ActionItem].self,   stmt: stmt, idx: 14, decoder: decoder) ?? []
                let chapters   = decode([Chapter].self,      stmt: stmt, idx: 15, decoder: decoder) ?? []
                let transcript = decode([TranscriptLine].self, stmt: stmt, idx: 16, decoder: decoder) ?? []
                let audioURL   = textOrNil(stmt, 17)
                let processing = sqlite3_column_int(stmt, 18) == 1
                // lifecycle bevorzugen; bei Altzeilen (NULL) aus processing ableiten:
                // unterbrochene Jobs landen in .transcribing, damit recoverOrphaned
                // sie aufgreift, fertige in .done.
                let lifecycle  = textOrNil(stmt, 19)
                    .map { MeetingLifecycle(serialized: $0) }
                    ?? (processing ? .transcribing : .done)
                let platform   = Platform(rawValue: platStr) ?? .call

                summaries.append(.init(
                    id: id, title: title, date: dateShort, time: timeShort,
                    duration: dur, platform: platform, wordCount: words,
                    group: group, participantIds: participants.map(\.id), unread: unread
                ))
                detailMap[id] = MeetingDetail(
                    id: id, title: title, dateLong: dateLong, timeRange: timeRange,
                    duration: dur, platform: platform, wordCount: words,
                    participants: participants, tldr: tldr,
                    highlights: highlights, tasks: tasks, chapters: chapters,
                    transcript: transcript, audioURL: audioURL, lifecycle: lifecycle
                )
            }
        }
        sqlite3_finalize(stmt)

        let publish = {
            self.meetings = summaries
            self.details = detailMap
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.async(execute: publish)
        }
    }

    private func textOrNil(_ stmt: OpaquePointer?, _ idx: Int32) -> String? {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return nil }
        return String(cString: cstr)
    }

    private func decode<T: Decodable>(_ type: T.Type, stmt: OpaquePointer?, idx: Int32, decoder: JSONDecoder) -> T? {
        guard let cstr = sqlite3_column_text(stmt, idx) else { return nil }
        let s = String(cString: cstr)
        guard !s.isEmpty, let data = s.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    func detail(for id: String) -> MeetingDetail? {
        details[id]
    }

    func updateTaskStatus(meetingId: String, taskId: String, status: TaskStatus) {
        guard let d = details[meetingId] else { return }
        var tasks = d.tasks
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].status = status
        let upd = MeetingDetail(
            id: d.id, title: d.title, dateLong: d.dateLong, timeRange: d.timeRange,
            duration: d.duration, platform: d.platform, wordCount: d.wordCount,
            participants: d.participants, tldr: d.tldr,
            highlights: d.highlights, tasks: tasks, chapters: d.chapters, transcript: d.transcript,
            audioURL: d.audioURL, lifecycle: d.lifecycle
        )
        upsertDetail(upd)
        readBackToPublished()
    }

    func relabelSpeaker(meetingId: String, from oldId: String, to newId: String, name: String, colorHex: UInt32) {
        guard let d = details[meetingId] else { return }
        let oldName = d.participants.first { $0.id == oldId }?.name
        let existingSpoke = d.participants.first { $0.id == oldId }?.spoke
            ?? d.participants.first { $0.id == newId }?.spoke
            ?? "0s"
        let labeled = Participant(id: newId, name: name, role: "Bekannt", colorHex: colorHex, spoke: existingSpoke)

        var participants = d.participants.filter { $0.id != newId }
        if let idx = participants.firstIndex(where: { $0.id == oldId }) {
            participants[idx] = labeled
        } else {
            participants.append(labeled)
        }

        let transcript = d.transcript.map { line in
            guard line.who == oldId else { return line }
            return TranscriptLine(
                id: line.id,
                who: newId,
                displayName: name,
                timestamp: line.timestamp,
                startSeconds: line.startSeconds,
                endSeconds: line.endSeconds,
                body: line.body,
                source: line.source,
                speakerSource: .manual,
                confidence: 1.0,
                highlight: line.highlight
            )
        }
        let tldr = replacingSpeakerMentions(in: d.tldr, oldId: oldId, oldName: oldName, newName: name)
        let highlights = d.highlights.map { highlight in
            Highlight(
                id: highlight.id,
                label: replacingSpeakerMentions(in: highlight.label, oldId: oldId, oldName: oldName, newName: name),
                text: replacingSpeakerMentions(in: highlight.text, oldId: oldId, oldName: oldName, newName: name),
                tone: highlight.tone
            )
        }
        let tasks = d.tasks.map { item in
            ActionItem(
                id: item.id,
                who: item.who == oldId ? newId : item.who,
                task: replacingSpeakerMentions(in: item.task, oldId: oldId, oldName: oldName, newName: name),
                due: item.due,
                status: item.status
            )
        }
        let chapters = d.chapters.map { chapter in
            Chapter(
                id: chapter.id,
                timestamp: chapter.timestamp,
                label: replacingSpeakerMentions(in: chapter.label, oldId: oldId, oldName: oldName, newName: name),
                duration: chapter.duration
            )
        }

        let updated = MeetingDetail(
            id: d.id,
            title: d.title,
            dateLong: d.dateLong,
            timeRange: d.timeRange,
            duration: d.duration,
            platform: d.platform,
            wordCount: d.wordCount,
            participants: participants,
            tldr: tldr,
            highlights: highlights,
            tasks: tasks,
            chapters: chapters,
            transcript: transcript,
            audioURL: d.audioURL,
            lifecycle: d.lifecycle
        )
        upsertDetail(updated)
        readBackToPublished()
    }

    private func replacingSpeakerMentions(in text: String, oldId: String, oldName: String?, newName: String) -> String {
        speakerMentionCandidates(oldId: oldId, oldName: oldName).reduce(text) { partial, candidate in
            replacingWholeMention(candidate, in: partial, with: newName)
        }
    }

    private func speakerMentionCandidates(oldId: String, oldName: String?) -> [String] {
        var candidates = [oldName, oldId, "Speaker \(oldId)"]
        let upperId = oldId.uppercased()
        if upperId.hasPrefix("S") {
            let number = String(upperId.dropFirst())
            if !number.isEmpty {
                candidates.append("Speaker \(number)")
            }
        }

        var seen: Set<String> = []
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .filter { seen.insert($0).inserted }
    }

    private func replacingWholeMention(_ candidate: String, in text: String, with replacement: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N}_])\(NSRegularExpression.escapedPattern(for: candidate))(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
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
              title = ?, date_long = ?, time_range = ?, tldr = ?,
              word_count = ?,
              participants = ?, highlights = ?, tasks = ?, chapters = ?, transcript = ?,
              audio_url = ?, processing = ?, lifecycle = ?
            WHERE id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, d.title)
        bind(stmt, 2, d.dateLong)
        bind(stmt, 3, d.timeRange)
        bind(stmt, 4, d.tldr)
        sqlite3_bind_int(stmt, 5, Int32(d.wordCount))
        bind(stmt, 6, jsonString(d.participants, encoder))
        bind(stmt, 7, jsonString(d.highlights,   encoder))
        bind(stmt, 8, jsonString(d.tasks,        encoder))
        bind(stmt, 9, jsonString(d.chapters,     encoder))
        bind(stmt, 10, jsonString(d.transcript,   encoder))
        if let a = d.audioURL { bind(stmt, 11, a) } else { sqlite3_bind_null(stmt, 11) }
        sqlite3_bind_int(stmt, 12, d.processing ? 1 : 0)
        bind(stmt, 13, d.lifecycle.serialized)
        bind(stmt, 14, d.id)
        sqlite3_step(stmt)
    }

    /// Public Update — RecordingController nutzt das nach PostProcessing,
    /// um Title/TLDR/Highlights/Tasks/AudioURL nachzureichen.
    func updateDetail(_ detail: MeetingDetail, summaryTitle: String? = nil) {
        upsertDetail(detail)
        if let newTitle = summaryTitle {
            let sql = "UPDATE meeting SET title = ? WHERE id = ?"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                bind(stmt, 1, newTitle)
                bind(stmt, 2, detail.id)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        readBackToPublished()
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
