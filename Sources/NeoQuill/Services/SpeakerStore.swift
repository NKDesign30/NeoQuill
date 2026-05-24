import Foundation
import SQLite3
import FluidAudio

// SQLite-Backed Persistenz für gelabelte Sprecher.
// FluidAudio liefert Embeddings als [Float] pro Diarize-Run — wir speichern sie
// zusammen mit dem User-gegebenen Namen, sodass beim nächsten Call automatisch
// matched wird (User labelt "Thorsten" einmal, Diarizer erkennt ihn wieder).

final class SpeakerStore: ObservableObject {

    @Published private(set) var speakers: [LabeledSpeaker] = []

    private var db: OpaquePointer?
    private let url: URL
    private var embeddingsBySpeakerId: [String: [[Float]]] = [:]

    init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = support.appendingPathComponent("NeoQuill", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("speakers.sqlite")
        }
        openDb()
        migrate()
        reload()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Public API

    func upsertIdentity(id: String, name: String, colorHex: UInt32) {
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT INTO speaker (id, name, embedding, color_hex, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              color_hex = excluded.color_hex,
              last_seen_at = excluded.last_seen_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        bindText(stmt, 2, name)
        bindText(stmt, 3, "[]")
        sqlite3_bind_int(stmt, 4, Int32(bitPattern: colorHex))
        sqlite3_bind_double(stmt, 5, now)
        sqlite3_bind_double(stmt, 6, now)
        sqlite3_step(stmt)
        reload()
    }

    func upsert(id: String, name: String, embedding: [Float], colorHex: UInt32) {
        upsertIdentity(id: id, name: name, colorHex: colorHex)
        guard !embedding.isEmpty else { return }
        insertEmbedding(speakerId: id, embedding: embedding, duration: 0, quality: 1.0)
        updateLegacyEmbedding(speakerId: id, embedding: embedding)
        reload()
    }

    func upsertAlias(
        speakerId: String,
        alias: String,
        source: String,
        platform: Platform,
        externalId: String?
    ) {
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !speakerId.isEmpty, !trimmedAlias.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT INTO speaker_alias (id, speaker_id, alias, source, platform, external_id, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(speaker_id, alias, source, platform) DO UPDATE SET
              external_id = excluded.external_id,
              last_seen_at = excluded.last_seen_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, UUID().uuidString)
        bindText(stmt, 2, speakerId)
        bindText(stmt, 3, trimmedAlias)
        bindText(stmt, 4, source)
        bindText(stmt, 5, platform.rawValue)
        if let externalId, !externalId.isEmpty {
            bindText(stmt, 6, externalId)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_double(stmt, 7, now)
        sqlite3_bind_double(stmt, 8, now)
        sqlite3_step(stmt)
        reload()
    }

    func remove(id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM speaker WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        sqlite3_step(stmt)
        reload()
    }

    func speaker(for id: String) -> LabeledSpeaker? {
        speakers.first { $0.id == id }
    }

    /// Übergibt alle bekannten Speaker an FluidAudio für Re-Identification beim nächsten Diarize.
    func fluidAudioSpeakers() -> [Speaker] {
        speakers.compactMap { ls in
            guard let embedding = representativeEmbedding(for: ls.id), !embedding.isEmpty else { return nil }
            return Speaker(
                id: ls.id,
                name: ls.name,
                currentEmbedding: embedding,
                duration: 0,
                createdAt: ls.createdAt,
                updatedAt: ls.lastSeenAt
            )
        }
    }

    /// Speichert das Embedding eines anonymen Speakers (`S1`/`S2`/...) pro
    /// Meeting. Wird beim spaeteren Label-Backfill genutzt: sobald derselbe
    /// Speaker in irgendeinem Meeting einen Namen bekommt, koennen wir alle
    /// anderen Meetings ueber diese Embeddings zuordnen.
    func recordMeetingEmbedding(meetingId: String, internalId: String, embedding: [Float]) {
        let trimmedMeeting = meetingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInternal = internalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMeeting.isEmpty, !trimmedInternal.isEmpty, !embedding.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT INTO meeting_speaker_embedding (id, meeting_id, internal_id, embedding, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(meeting_id, internal_id) DO UPDATE SET
              embedding = excluded.embedding,
              created_at = excluded.created_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, UUID().uuidString)
        bindText(stmt, 2, trimmedMeeting)
        bindText(stmt, 3, trimmedInternal)
        bindText(stmt, 4, encodeEmbedding(embedding))
        sqlite3_bind_double(stmt, 5, now)
        sqlite3_step(stmt)
    }

    func meetingEmbedding(meetingId: String, internalId: String) -> [Float]? {
        let trimmedMeeting = meetingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInternal = internalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMeeting.isEmpty, !trimmedInternal.isEmpty else { return nil }

        let sql = """
            SELECT embedding FROM meeting_speaker_embedding
             WHERE meeting_id = ? AND internal_id = ?
             LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, trimmedMeeting)
        bindText(stmt, 2, trimmedInternal)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let raw = sqlite3_column_text(stmt, 0)
        else { return nil }
        let embedding = decodeEmbedding(String(cString: raw))
        return embedding.isEmpty ? nil : embedding
    }

    struct MeetingSpeakerMatch: Hashable {
        let meetingId: String
        let internalId: String
        let score: Float
    }

    /// Sucht in allen gespeicherten Meeting-Embeddings nach Treffern fuer das
    /// gegebene Embedding. Optional kann `excluding` ein Meeting auslassen
    /// (z.B. das gerade gelabelte). Ergebnis sortiert nach Score absteigend.
    func meetingMatches(
        for embedding: [Float],
        threshold: Float = 0.78,
        excluding meetingId: String? = nil
    ) -> [MeetingSpeakerMatch] {
        guard !embedding.isEmpty else { return [] }
        var stmt: OpaquePointer?
        let sql = "SELECT meeting_id, internal_id, embedding FROM meeting_speaker_embedding"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var hits: [MeetingSpeakerMatch] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let storedMeetingId = String(cString: sqlite3_column_text(stmt, 0))
            if let exclude = meetingId, storedMeetingId == exclude { continue }
            let storedInternalId = String(cString: sqlite3_column_text(stmt, 1))
            let storedEmbeddingJson = String(cString: sqlite3_column_text(stmt, 2))
            let stored = decodeEmbedding(storedEmbeddingJson)
            guard !stored.isEmpty else { continue }
            let score = Self.cosine(embedding, stored)
            guard score >= threshold else { continue }
            hits.append(MeetingSpeakerMatch(
                meetingId: storedMeetingId,
                internalId: storedInternalId,
                score: score
            ))
        }
        return hits.sorted { $0.score > $1.score }
    }

    /// Nach erfolgtem Backfill umbenennen — die `internal_id`-Spalte zeigt jetzt
    /// auf den canonical Speaker, damit zukuenftige Cross-Meeting-Matches
    /// konsistent bleiben.
    func renameMeetingInternalId(meetingId: String, from oldInternalId: String, to newInternalId: String) {
        guard !meetingId.isEmpty, !oldInternalId.isEmpty, !newInternalId.isEmpty,
              oldInternalId != newInternalId else { return }
        let sql = """
            UPDATE meeting_speaker_embedding
               SET internal_id = ?
             WHERE meeting_id = ? AND internal_id = ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, newInternalId)
        bindText(stmt, 2, meetingId)
        bindText(stmt, 3, oldInternalId)
        sqlite3_step(stmt)
    }

    /// Suche bekannten Speaker per Cosine-Similarity. Gibt die ID + Score zurück
    /// wenn der beste Match über `threshold` liegt.
    func bestMatch(for embedding: [Float], threshold: Float = 0.72) -> (id: String, score: Float)? {
        guard !embedding.isEmpty else { return nil }
        var best: (id: String, score: Float)?
        for (speakerId, knownEmbeddings) in embeddingsBySpeakerId {
            for knownEmbedding in knownEmbeddings where !knownEmbedding.isEmpty {
                let s = Self.cosine(embedding, knownEmbedding)
                if s > (best?.score ?? -1) { best = (speakerId, s) }
            }
        }
        guard let b = best, b.score >= threshold else { return nil }
        return b
    }

    // MARK: - Internal

    private func openDb() {
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            NSLog("[SpeakerStore] open failed at " + url.path)
            return
        }
        runRaw("PRAGMA journal_mode = WAL;")
        runRaw("PRAGMA busy_timeout = 5000;")
        runRaw("PRAGMA foreign_keys = ON;")
    }

    private func migrate() {
        runRaw("""
            CREATE TABLE IF NOT EXISTS speaker (
                id            TEXT PRIMARY KEY,
                name          TEXT NOT NULL,
                embedding     TEXT NOT NULL,
                color_hex     INTEGER NOT NULL,
                created_at    REAL NOT NULL,
                last_seen_at  REAL NOT NULL
            );
        """)
        runRaw("""
            CREATE TABLE IF NOT EXISTS speaker_embedding (
                id          TEXT PRIMARY KEY,
                speaker_id  TEXT NOT NULL,
                embedding   TEXT NOT NULL,
                duration    REAL NOT NULL DEFAULT 0,
                quality     REAL NOT NULL DEFAULT 1,
                created_at  REAL NOT NULL,
                FOREIGN KEY(speaker_id) REFERENCES speaker(id) ON DELETE CASCADE
            );
        """)
        runRaw("""
            CREATE INDEX IF NOT EXISTS idx_speaker_embedding_speaker
            ON speaker_embedding(speaker_id);
        """)
        runRaw("""
            CREATE TABLE IF NOT EXISTS speaker_alias (
                id            TEXT PRIMARY KEY,
                speaker_id    TEXT NOT NULL,
                alias         TEXT NOT NULL,
                source        TEXT NOT NULL,
                platform      TEXT NOT NULL,
                external_id   TEXT,
                created_at    REAL NOT NULL,
                last_seen_at  REAL NOT NULL,
                UNIQUE(speaker_id, alias, source, platform),
                FOREIGN KEY(speaker_id) REFERENCES speaker(id) ON DELETE CASCADE
            );
        """)
        runRaw("""
            CREATE TABLE IF NOT EXISTS meeting_speaker_embedding (
                id            TEXT PRIMARY KEY,
                meeting_id    TEXT NOT NULL,
                internal_id   TEXT NOT NULL,
                embedding     TEXT NOT NULL,
                created_at    REAL NOT NULL,
                UNIQUE(meeting_id, internal_id)
            );
        """)
        runRaw("""
            CREATE INDEX IF NOT EXISTS idx_meeting_speaker_embedding_meeting
            ON meeting_speaker_embedding(meeting_id);
        """)
        migrateLegacyEmbeddings()
    }

    @discardableResult
    private func runRaw(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func reload() {
        var out: [LabeledSpeaker] = []
        let loadedEmbeddings = loadEmbeddingsBySpeaker()
        var stmt: OpaquePointer?
        let sql = "SELECT id, name, embedding, color_hex, created_at, last_seen_at FROM speaker ORDER BY last_seen_at DESC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id    = String(cString: sqlite3_column_text(stmt, 0))
                let name  = String(cString: sqlite3_column_text(stmt, 1))
                let emb   = String(cString: sqlite3_column_text(stmt, 2))
                let color = UInt32(bitPattern: Int32(sqlite3_column_int(stmt, 3)))
                let created  = sqlite3_column_double(stmt, 4)
                let lastSeen = sqlite3_column_double(stmt, 5)
                let embeddings = loadedEmbeddings[id] ?? [decodeEmbedding(emb)].filter { !$0.isEmpty }
                out.append(.init(
                    id: id, name: name,
                    embedding: Self.average(embeddings) ?? decodeEmbedding(emb),
                    colorHex: color,
                    createdAt: Date(timeIntervalSince1970: created),
                    lastSeenAt: Date(timeIntervalSince1970: lastSeen)
                ))
            }
        }
        sqlite3_finalize(stmt)
        embeddingsBySpeakerId = loadedEmbeddings
        DispatchQueue.main.async { self.speakers = out }
    }

    private func insertEmbedding(speakerId: String, embedding: [Float], duration: TimeInterval, quality: Double) {
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT INTO speaker_embedding (id, speaker_id, embedding, duration, quality, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, UUID().uuidString)
        bindText(stmt, 2, speakerId)
        bindText(stmt, 3, encodeEmbedding(embedding))
        sqlite3_bind_double(stmt, 4, duration)
        sqlite3_bind_double(stmt, 5, quality)
        sqlite3_bind_double(stmt, 6, now)
        sqlite3_step(stmt)
    }

    private func updateLegacyEmbedding(speakerId: String, embedding: [Float]) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE speaker SET embedding = ?, last_seen_at = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, encodeEmbedding(embedding))
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        bindText(stmt, 3, speakerId)
        sqlite3_step(stmt)
    }

    private func migrateLegacyEmbeddings() {
        var stmt: OpaquePointer?
        let sql = "SELECT id, embedding, created_at FROM speaker WHERE embedding IS NOT NULL AND embedding != '' AND embedding != '[]'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let speakerId = String(cString: sqlite3_column_text(stmt, 0))
            let embeddingJson = String(cString: sqlite3_column_text(stmt, 1))
            let created = sqlite3_column_double(stmt, 2)
            guard !decodeEmbedding(embeddingJson).isEmpty,
                  !hasEmbedding(speakerId: speakerId, embeddingJson: embeddingJson)
            else { continue }
            insertLegacyEmbedding(speakerId: speakerId, embeddingJson: embeddingJson, createdAt: created)
        }
    }

    private func hasEmbedding(speakerId: String, embeddingJson: String) -> Bool {
        var stmt: OpaquePointer?
        let sql = "SELECT 1 FROM speaker_embedding WHERE speaker_id = ? AND embedding = ? LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, speakerId)
        bindText(stmt, 2, embeddingJson)
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    private func insertLegacyEmbedding(speakerId: String, embeddingJson: String, createdAt: Double) {
        let sql = """
            INSERT INTO speaker_embedding (id, speaker_id, embedding, duration, quality, created_at)
            VALUES (?, ?, ?, 0, 1, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, UUID().uuidString)
        bindText(stmt, 2, speakerId)
        bindText(stmt, 3, embeddingJson)
        sqlite3_bind_double(stmt, 4, createdAt)
        sqlite3_step(stmt)
    }

    private func loadEmbeddingsBySpeaker() -> [String: [[Float]]] {
        var out: [String: [[Float]]] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT speaker_id, embedding FROM speaker_embedding ORDER BY created_at DESC"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let speakerId = String(cString: sqlite3_column_text(stmt, 0))
                let embeddingJson = String(cString: sqlite3_column_text(stmt, 1))
                let embedding = decodeEmbedding(embeddingJson)
                if !embedding.isEmpty {
                    out[speakerId, default: []].append(embedding)
                }
            }
        }
        sqlite3_finalize(stmt)
        return out
    }

    private func representativeEmbedding(for speakerId: String) -> [Float]? {
        if let average = Self.average(embeddingsBySpeakerId[speakerId] ?? []) {
            return average
        }
        return speaker(for: speakerId)?.embedding
    }

    private func encodeEmbedding(_ e: [Float]) -> String {
        guard let data = try? JSONEncoder().encode(e),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func decodeEmbedding(_ s: String) -> [Float] {
        guard let data = s.data(using: .utf8),
              let arr = try? JSONDecoder().decode([Float].self, from: data) else { return [] }
        return arr
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }

    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<n {
            dot += a[i] * b[i]
            na  += a[i] * a[i]
            nb  += b[i] * b[i]
        }
        let denom = sqrtf(na) * sqrtf(nb)
        return denom > 0 ? dot / denom : 0
    }

    private static func average(_ embeddings: [[Float]]) -> [Float]? {
        let usable = embeddings.filter { !$0.isEmpty }
        guard let first = usable.first else { return nil }
        let count = first.count
        var out = [Float](repeating: 0, count: count)
        var used = 0
        for embedding in usable where embedding.count == count {
            used += 1
            for idx in 0..<count {
                out[idx] += embedding[idx]
            }
        }
        guard used > 0 else { return nil }
        return out.map { $0 / Float(used) }
    }
}

struct LabeledSpeaker: Identifiable, Hashable {
    let id: String
    var name: String
    var embedding: [Float]
    var colorHex: UInt32
    var createdAt: Date
    var lastSeenAt: Date
}
