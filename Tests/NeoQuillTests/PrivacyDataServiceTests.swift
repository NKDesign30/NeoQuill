import XCTest
@testable import NeoQuill

final class PrivacyDataServiceTests: XCTestCase {
    func testDeletesOnlyAudioFilesForMeeting() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeFile("meeting-1.wav", in: directory)
        try writeFile("meeting-1.mic.wav", in: directory)
        try writeFile("meeting-1.system.wav", in: directory)
        try writeFile("meeting-2.wav", in: directory)
        try writeFile("notes.txt", in: directory)

        let deleted = try PrivacyDataService.deleteAudioFiles(for: "meeting-1", directory: directory)

        XCTAssertEqual(deleted, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-1.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-1.mic.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-1.system.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-2.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("notes.txt").path))
    }

    /// Regression: die `.hq`-Spur (48-kHz-Archiv, größte Datei) wurde früher beim
    /// Löschen vergessen und überlebte ein "Audio löschen" — ein Datenschutz-Leck.
    func testDeletesHighResArchiveToo() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeFile("meeting-1.wav", in: directory)
        try writeFile("meeting-1.mic.wav", in: directory)
        try writeFile("meeting-1.system.wav", in: directory)
        try writeFile("meeting-1.hq.wav", in: directory)

        let deleted = try PrivacyDataService.deleteAudioFiles(for: "meeting-1", directory: directory)

        XCTAssertEqual(deleted, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-1.hq.wav").path))
    }

    func testDeletesAllAudioFilesButKeepsOtherLocalFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeFile("meeting-1.wav", in: directory)
        try writeFile("meeting-2.WAV", in: directory)
        try writeFile("readme.md", in: directory)

        let deleted = try PrivacyDataService.deleteAudioFiles(directory: directory)

        XCTAssertEqual(deleted, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-1.wav").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meeting-2.WAV").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("readme.md").path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeoQuillPrivacyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeFile(_ name: String, in directory: URL) throws {
        try Data("audio".utf8).write(to: directory.appendingPathComponent(name))
    }
}
