import Foundation

// Subprocess-Wrapper für `claude -p` aus Niko's Max Plan.
// Generiert TLDR + Highlights + Action Items aus einem Transkript.
// Kein API-Key nötig — nutzt OAuth-Login der Claude CLI.

struct MeetingSummaryAI: Codable {
    let title: String
    let tldr: String
    let highlights: [HighlightAI]
    let tasks: [TaskAI]
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
        let prompt = buildPrompt(transcript: transcript, locale: locale)

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
                return parseSummary(inner)
            }
            return parseSummary(raw)
        }.value
    }

    private static func buildPrompt(transcript: String, locale: String) -> String {
        let lang = locale == "en" ? "English" : "German"
        return """
        Du bist ein Meeting-Notizen-Assistent. Analysiere das folgende Transkript und antworte AUSSCHLIESSLICH mit gültigem JSON in dieser Struktur (Sprache: \(lang)):

        {
          "title": "Kurzer aussagekräftiger Titel (max 8 Wörter)",
          "tldr": "Eine prägnante Zusammenfassung in 2-3 Sätzen — was wurde gesagt, was ist wichtig",
          "highlights": [
            {"label": "Entscheidung", "text": "...", "tone": "brand"},
            {"label": "Risiko", "text": "...", "tone": "warning"},
            {"label": "Termin", "text": "...", "tone": "info"}
          ],
          "tasks": [
            {"who": "NK", "task": "...", "due": "DD. MMM.", "status": "open"}
          ]
        }

        Regeln:
        - tone: "brand" für Entscheidungen, "warning" für Risiken/offene Punkte, "info" für Termine
        - status: nur "open" oder "done"
        - who: Sprecher-Initialen (z.B. NK, SE, TM) — wenn unbekannt: "??"
        - Wenn ein Feld leer wäre: leere Liste statt erfundene Einträge
        - KEIN Markdown, KEIN Erklärtext, NUR das JSON

        TRANSKRIPT:
        \(transcript)
        """
    }

    private static func parseSummary(_ text: String) -> MeetingSummaryAI? {
        // Trim ggf. Markdown-Codefences
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed.replacingOccurrences(of: "```json", with: "")
            trimmed = trimmed.replacingOccurrences(of: "```", with: "")
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Cut auf erstes { ... letztes }
        guard let first = trimmed.firstIndex(of: "{"),
              let last = trimmed.lastIndex(of: "}") else { return nil }
        let payload = String(trimmed[first...last])
        guard let data = payload.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(MeetingSummaryAI.self, from: data)
        } catch {
            NSLog("[ClaudeCLI] parse failed: \(error) raw=\(payload.prefix(200))")
            return nil
        }
    }
}
