import Foundation

// Subprocess-Wrapper für lokale `claude -p` Verarbeitung.
// Generiert TLDR + Highlights + Action Items aus einem Transkript.
// Kein API-Key nötig — nutzt OAuth-Login der Claude CLI.
// Das Ergebnis-Vokabular (MeetingSummaryAI & Co.) lebt in SummaryModels.swift.

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
