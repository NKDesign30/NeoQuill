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
