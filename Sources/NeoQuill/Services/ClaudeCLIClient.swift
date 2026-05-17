import Foundation

// Subprocess-Wrapper für lokale `claude -p` Verarbeitung.
// Generiert TLDR + Highlights + Action Items aus einem Transkript.
// Kein API-Key nötig — nutzt OAuth-Login der Claude CLI.

struct MeetingSummaryAI: Codable {
    let title: String
    let tldr: String
    let highlights: [HighlightAI]
    let tasks: [TaskAI]
    let chapters: [ChapterAI]

    // Defensive: wenn Haiku einen Key komplett vergisst, fallen wir auf
    // sinnvolle Defaults statt den ganzen Decode zu killen. Sonst geht
    // ein einzelner fehlender Key (z.B. chapters) als nil-Summary zurueck
    // und der User sieht weder TLDR noch Highlights.
    enum CodingKeys: String, CodingKey {
        case title, tldr, highlights, tasks, chapters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title      = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.tldr       = (try? c.decode(String.self, forKey: .tldr)) ?? ""
        self.highlights = (try? c.decode([HighlightAI].self, forKey: .highlights)) ?? []
        self.tasks      = (try? c.decode([TaskAI].self, forKey: .tasks)) ?? []
        self.chapters   = (try? c.decode([ChapterAI].self, forKey: .chapters)) ?? []
    }

    init(title: String, tldr: String, highlights: [HighlightAI], tasks: [TaskAI], chapters: [ChapterAI]) {
        self.title = title
        self.tldr = tldr
        self.highlights = highlights
        self.tasks = tasks
        self.chapters = chapters
    }
}

struct HighlightAI: Codable {
    let label: String      // "Entscheidung" / "Risiko" / "Termin"
    let text: String
    let tone: String       // "brand" / "warning" / "info"
}

struct TaskAI: Codable {
    let who: String
    let task: String
    let due: String
    let status: String     // "open" / "done"
}

struct ChapterAI: Codable {
    let timestamp: String  // "02:14" — Anfang des Themen-Blocks im Audio
    let label: String      // "Pricing-Diskussion" — 2-5 Worte
    let duration: String   // "6m" oder "45s"
}

enum ClaudeCLIClient {

    static func claudeBinaryPath() -> String? {
        // Wir versuchen `which claude`, dann hardcoded Pfade.
        if let p = which("claude"), !p.isEmpty { return p }
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/which"
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    static func summarize(transcript: String, locale: String = "de") async -> MeetingSummaryAI? {
        guard let bin = claudeBinaryPath() else {
            NSLog("[ClaudeCLI] claude binary not found")
            return nil
        }
        let prompt = MeetingSummaryPrompt.build(transcript: transcript, locale: locale)

        return await Task.detached(priority: .userInitiated) { () -> MeetingSummaryAI? in
            let process = Process()
            process.launchPath = bin
            process.arguments = [
                "-p", prompt,
                "--model", "haiku",
                "--output-format", "json",
            ]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.environment = ProcessInfo.processInfo.environment

            do {
                try process.run()
            } catch {
                NSLog("[ClaudeCLI] launch failed: \(error)")
                return nil
            }
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let raw = String(data: data, encoding: .utf8) else { return nil }

            // claude --output-format json wraps the assistant-text in `.result`.
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let inner = (json["result"] as? String) ?? (json["text"] as? String) {
                return MeetingSummaryPrompt.parseSummary(inner)
            }
            return MeetingSummaryPrompt.parseSummary(raw)
        }.value
    }
}
