import Foundation
import SQLite3
import FluidAudio

// SQLite-Backed Persistenz für gelabelte Sprecher.
// FluidAudio liefert Embeddings als [Float] pro Diarize-Run — wir speichern sie
// zusammen mit dem User-gegebenen Namen, sodass beim nächsten Call automatisch
// matched wird (Niko labelt "Thorsten" einmal, Diarizer erkennt ihn wieder).

final class SpeakerStore: ObservableObject {

    @Published private(set) var speakers: [LabeledSpeaker] = []

    private var db: OpaquePointer?
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("NeoQuill", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("speakers.sqlite")
        openDb()
        migrate()
        reload()
    }

    deinit { sqlite3_close(db) }

    // MARK: - Public API

    func upsert(id: String, name: String, embedding: [Float], colorHex: UInt32) {
        let json = encodeEmbedding(embedding)
        let now = Date().timeIntervalSince1970
        let sql = """
            INSERT INTO speaker (id, name, embedding, color_hex, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              embedding = excluded.embedding,
              color_hex = excluded.color_hex,
              last_seen_at = excluded.last_seen_at
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        bindText(stmt, 2, name)
        bindText(stmt, 3, json)
        sqlite3_bind_int(stmt, 4, Int32(bitPattern: colorHex))
        sqlite3_bind_double(stmt, 5, now)
        sqlite3_bind_double(stmt, 6, now)
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
        speakers.filter { !$0.embedding.isEmpty }.map { ls in
            Speaker(
                id: ls.id,
                name: ls.name,
                currentEmbedding: ls.embedding,
                duration: 0,
                createdAt: ls.createdAt,
                updatedAt: ls.lastSeenAt
            )
        }
    }

    /// Suche bekannten Speaker per Cosine-Similarity. Gibt die ID + Score zurück
    /// wenn der beste Match über `threshold` liegt.
    func bestMatch(for embedding: [Float], threshold: Float = 0.72) -> (id: String, score: Float)? {
        guard !speakers.isEmpty, !embedding.isEmpty else { return nil }
        var best: (id: String, score: Float)?
        for ls in speakers {
            let s = Self.cosine(embedding, ls.embedding)
            if s > (best?.score ?? -1) { best = (ls.id, s) }
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
    }

    @discardableResult
    private func runRaw(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func reload() {
        var out: [LabeledSpeaker] = []
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
                out.append(.init(
                    id: id, name: name,
                    embedding: decodeEmbedding(emb),
                    colorHex: color,
                    createdAt: Date(timeIntervalSince1970: created),
                    lastSeenAt: Date(timeIntervalSince1970: lastSeen)
                ))
            }
        }
        sqlite3_finalize(stmt)
        DispatchQueue.main.async { self.speakers = out }
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
}

struct LabeledSpeaker: Identifiable, Hashable {
    let id: String
    var name: String
    var embedding: [Float]
    var colorHex: UInt32
    var createdAt: Date
    var lastSeenAt: Date
}
