import Foundation
import AppKit

// Markdown-Export für ein MeetingDetail. Wird von Toolbar-Buttons (Copy/Export/Share) genutzt.

enum MeetingExporter {

    enum ExportError: LocalizedError {
        case emptyArchive

        var errorDescription: String? {
            switch self {
            case .emptyArchive: return "Keine Meetings zum Exportieren vorhanden."
            }
        }
    }

    /// Ziel-KI für den Übergabe-Prompt.
    enum AITarget: String {
        case neo
        case chaty
        case generic

        var label: String {
            switch self {
            case .neo: return "Neo (Claude Code)"
            case .chaty: return "Chaty (Codex)"
            case .generic: return "Generisch"
            }
        }
    }

    /// Umfang des Übergabe-Prompts.
    enum HandoffMode {
        /// Schlank: nur ID + Auftrag, die KI holt die Daten selbst aus der lokalen DB.
        case reference
        /// Self-contained: komplettes Meeting-Markdown inklusive Transkript inline.
        case full
    }

    static func markdown(_ m: MeetingDetail) -> String {
        var out = "# \(m.title)\n\n"
        out += "**\(m.dateLong) · \(m.timeRange) · \(m.duration) · \(m.platform.rawValue)**\n\n"

        if !m.tldr.isEmpty {
            out += "## TL;DR\n\n\(m.tldr)\n\n"
        }

        if !m.highlights.isEmpty {
            out += "## Highlights\n\n"
            for h in m.highlights {
                out += "- **\(h.label):** \(h.text)\n"
            }
            out += "\n"
        }

        if !m.tasks.isEmpty {
            out += "## Aktionspunkte\n\n"
            for t in m.tasks {
                let mark = t.status == .done ? "x" : " "
                let who = m.participants.first(where: { $0.id == t.who })?.name ?? t.who
                out += "- [\(mark)] \(t.task) — \(who) · fällig \(t.due)\n"
            }
            out += "\n"
        }

        if !m.chapters.isEmpty {
            out += "## Kapitel\n\n"
            for c in m.chapters {
                out += "- \(c.timestamp) — \(c.label) (\(c.duration))\n"
            }
            out += "\n"
        }

        if !m.transcript.isEmpty {
            out += "## Transkript\n\n"
            for line in m.transcript {
                let speaker = m.participants.first(where: { $0.id == line.who })?.name ?? line.who
                out += "**\(line.timestamp) — \(speaker):** \(line.body)\n\n"
            }
        }

        return out
    }

    static func copyToPasteboard(_ m: MeetingDetail) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(markdown(m), forType: .string)
    }

    // MARK: - KI-Übergabe (Clipboard-Prompt)

    /// Baut einen fertigen Prompt, mit dem eine KI (Neo/Chaty/generisch) die
    /// projektrelevanten Erkenntnisse aus diesem Meeting ins Memory übernimmt.
    static func aiHandoffPrompt(
        _ m: MeetingDetail,
        target: AITarget,
        mode: HandoffMode,
        workspace: String? = nil
    ) -> String {
        let trimmedWorkspace = workspace?.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = (trimmedWorkspace?.isEmpty == false) ? trimmedWorkspace! : "das passende Projekt"

        var out = "# Aufgabe: Meeting-Erkenntnisse ins Projekt-Memory übernehmen\n\n"
        out += "Es geht um das Meeting **\"\(m.title)\"** (\(m.dateLong) · \(m.timeRange)).\n"
        out += "Meeting-ID: `\(m.id)`\n"
        out += "Zielprojekt: **\(project)**\n\n"

        out += "Bitte:\n"
        out += "1. Das Meeting vollständig durchgehen.\n"
        out += "2. Die für **\(project)** relevanten Punkte herauspicken: Entscheidungen (mit Begründung), offene Action-Items mit Verantwortlichen, Termine/Deadlines, Anforderungen — alles was den Projektkontext dauerhaft verändert.\n"
        out += "3. Smalltalk, Geplauder und Redundanz weglassen — nur was in sechs Wochen noch wichtig ist.\n"
        out += targetInstructions(target: target, project: project)
        out += "\n"

        switch mode {
        case .reference:
            out += referenceDataSection(m, target: target)
        case .full:
            out += "---\n\n## Meeting-Inhalt\n\n"
            out += markdown(m)
        }

        return out
    }

    /// Schreibt den Übergabe-Prompt ins Clipboard.
    static func copyHandoffToPasteboard(
        _ m: MeetingDetail,
        target: AITarget,
        mode: HandoffMode,
        workspace: String? = nil
    ) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(aiHandoffPrompt(m, target: target, mode: mode, workspace: workspace), forType: .string)
    }

    private static func targetInstructions(target: AITarget, project: String) -> String {
        switch target {
        case .neo:
            return """
            4. Vor dem Schreiben `memory-search` nutzen, damit nichts doppelt landet.
            5. Erkenntnisse mit `write_memory` ablegen — echte Architektur-/Produktentscheidungen als `category='decision'` mit Rationale, sonst `category='meeting'`, jeweils dem Projekt \(project) zugeordnet.

            """
        case .chaty:
            return """
            4. Vorhandenes Projekt-Memory bzw. den Projektordner von \(project) prüfen, damit nichts doppelt landet.
            5. Die Erkenntnisse strukturiert dort ablegen.

            """
        case .generic:
            return """
            4. Die Erkenntnisse als saubere, strukturierte Markdown-Notiz ausgeben, gruppiert nach Entscheidungen / Action-Items / Termine / Sonstiges — bereit zum Ablegen in \(project).

            """
        }
    }

    private static func referenceDataSection(_ m: MeetingDetail, target: AITarget) -> String {
        switch target {
        case .neo, .chaty:
            return """
            ---

            ## Datenzugriff
            Die Meeting-Daten liegen lokal. Nutze die `quill` CLI (Skill `meeting-reader`):
            - `quill show \(m.id)` — TL;DR, Highlights, Tasks, Chapters
            - `quill transcript \(m.id)` — Volltext-Transkript
            - `quill search "\(m.title)"` — falls du das Meeting per Titel suchst
            Hinweis: Stille verleitet Whisper zu Wiederhol-Halluzinationen — solche Passagen nicht wörtlich übernehmen.
            """
        case .generic:
            return """
            ---

            ## Datenzugriff
            Die Meeting-Daten liegen in einer lokalen SQLite-DB unter
            `~/Library/Application Support/NeoQuill/meetings.sqlite` (Tabelle `meeting`, ID `\(m.id)`).
            Ohne Zugriff darauf stattdessen den Voll-Prompt nutzen (Button „An KI übergeben → \(m.title.isEmpty ? "Voll" : "Voll-Prompt mit Transkript")").
            """
        }
    }

    /// Schreibt Markdown und das kanonische Transcript-JSON nach ~/Desktop.
    static func exportToDesktop(_ m: MeetingDetail) -> URL? {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let safeTitle = m.title.replacingOccurrences(of: "/", with: "-")
        let url = desktop.appendingPathComponent("\(safeTitle).md")
        do {
            try markdown(m).write(to: url, atomically: true, encoding: .utf8)
            let transcriptURL = desktop.appendingPathComponent("\(safeTitle).transcript.json")
            try transcriptJSONData(m).write(to: transcriptURL, options: [.atomic])
            NSWorkspace.shared.activateFileViewerSelecting([url, transcriptURL])
            return url
        } catch {
            NSLog("[MeetingExporter] export failed: \(error)")
            return nil
        }
    }

    static func exportArchive(_ meetings: [MeetingDetail], to directory: URL, now: Date = Date()) throws -> URL {
        guard !meetings.isEmpty else { throw ExportError.emptyArchive }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let folder = directory.appendingPathComponent("NeoQuill-Export-\(formatter.string(from: now))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for meeting in meetings {
            let baseName = safeFilename("\(meeting.dateLong)-\(meeting.title)")
            try markdown(meeting).write(
                to: folder.appendingPathComponent(baseName.appending(".md")),
                atomically: true,
                encoding: .utf8
            )
            try transcriptJSONData(meeting).write(
                to: folder.appendingPathComponent(baseName.appending(".transcript.json")),
                options: [.atomic]
            )
        }
        return folder
    }

    static func exportArchiveToDesktop(_ meetings: [MeetingDetail]) throws -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let folder = try exportArchive(meetings, to: desktop)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
        return folder
    }

    static func share(_ m: MeetingDetail, from view: NSView) {
        let picker = NSSharingServicePicker(items: [markdown(m)])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }

    private static func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = value
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Meeting" : cleaned
    }

    private static func transcriptJSONData(_ meeting: MeetingDetail) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(transcriptRun(for: meeting))
    }

    private static func transcriptRun(for meeting: MeetingDetail) -> TranscriptRun {
        let storedRuns = (try? TranscriptRunStore.readRuns(meetingId: meeting.id)) ?? []
        if let passed = storedRuns
            .filter({ $0.quality.status == .passed })
            .max(by: { $0.createdAt < $1.createdAt }) {
            return passed
        }
        if let latest = storedRuns.max(by: { $0.createdAt < $1.createdAt }) {
            return latest
        }

        let duration = meeting.transcript.map(\.endSeconds).max() ?? 0
        return TranscriptRun.fromLines(
            meetingId: meeting.id,
            stem: "meeting",
            audioSampleRate: AudioImporter.targetSampleRate,
            audioDurationSeconds: duration,
            engine: TranscriptEngineInfo(name: "NeoQuill", model: "persisted-transcript", version: nil),
            settings: TranscriptRunSettings(
                language: "unknown",
                maxContextTokens: 0,
                vadEnabled: false,
                fullJSON: false,
                chunkDurationSeconds: duration,
                overlapSeconds: 0
            ),
            lines: meeting.transcript
        )
    }
}
