import Foundation

enum TranscriptRunStore {
    static func directory(for meetingId: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support
            .appendingPathComponent("NeoQuill/transcript-runs", isDirectory: true)
            .appendingPathComponent(safePathComponent(meetingId), isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func write(_ run: TranscriptRun) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let url = directory(for: run.meetingId)
            .appendingPathComponent("\(safePathComponent(run.stem))-\(run.id.uuidString)")
            .appendingPathExtension("json")
        try encoder.encode(run).write(to: url, options: [.atomic])
        return url
    }

    static func readRuns(meetingId: String) throws -> [TranscriptRun] {
        let dir = directory(for: meetingId)
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
            .filter { $0.pathExtension == "json" }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try urls
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                try decoder.decode(TranscriptRun.self, from: Data(contentsOf: url))
            }
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let safe = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return safe.isEmpty ? "unknown" : safe
    }
}
