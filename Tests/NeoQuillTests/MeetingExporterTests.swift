import XCTest
@testable import NeoQuill

final class MeetingExporterTests: XCTestCase {
    func testArchiveExportWritesOneMarkdownFilePerMeeting() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let folder = try MeetingExporter.exportArchive(
            [makeMeeting(title: "Kickoff: Q2/Plan?")],
            to: directory,
            now: Date(timeIntervalSince1970: 1_779_000_000)
        )

        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let markdownFiles = files.filter { $0.pathExtension == "md" }
        let file = try XCTUnwrap(markdownFiles.first)
        let content = try String(contentsOf: file, encoding: .utf8)

        XCTAssertEqual(markdownFiles.count, 1)
        XCTAssertTrue(folder.lastPathComponent.hasPrefix("NeoQuill-Export-"))
        XCTAssertTrue(file.lastPathComponent.contains("Kickoff- Q2-Plan-"))
        XCTAssertTrue(content.contains("# Kickoff: Q2/Plan?"))
        XCTAssertTrue(content.contains("## Transkript"))
        XCTAssertTrue(content.contains("Launch ist morgen."))
    }

    func testArchiveExportRejectsEmptyMeetingList() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try MeetingExporter.exportArchive([], to: directory)) { error in
            XCTAssertEqual(error as? MeetingExporter.ExportError, .emptyArchive)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeMeeting(title: String) -> MeetingDetail {
        MeetingDetail(
            id: "meeting-export-1",
            title: title,
            dateLong: "Sonntag, 17. Mai",
            timeRange: "10:00 – 10:30",
            duration: "30m",
            platform: .meet,
            wordCount: 420,
            participants: [
                Participant(id: "ME", name: "Niko", role: "Owner", colorHex: 0x2EAB73, spoke: "10m")
            ],
            tldr: "Wir planen den Launch.",
            highlights: [
                Highlight(label: "Entscheidung", text: "Launch ist morgen.", tone: .brand)
            ],
            tasks: [
                ActionItem(id: "task-1", who: "ME", task: "Follow-up senden", due: "18. Mai", status: .open)
            ],
            chapters: [
                Chapter(id: "chapter-1", timestamp: "00:00", label: "Start", duration: "5m")
            ],
            transcript: [
                TranscriptLine(who: "ME", timestamp: "00:00", body: "Launch ist morgen.")
            ],
            audioURL: nil,
            lifecycle: .done
        )
    }
}
