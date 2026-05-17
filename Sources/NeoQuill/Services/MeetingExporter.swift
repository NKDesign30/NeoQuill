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

    /// Schreibt eine .md-Datei nach ~/Desktop/<id>.md und öffnet die Datei im Finder-Reveal.
    static func exportToDesktop(_ m: MeetingDetail) -> URL? {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let safeTitle = m.title.replacingOccurrences(of: "/", with: "-")
        let url = desktop.appendingPathComponent("\(safeTitle).md")
        do {
            try markdown(m).write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
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
            let fileName = safeFilename("\(meeting.dateLong)-\(meeting.title)").appending(".md")
            try markdown(meeting).write(to: folder.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
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
}
