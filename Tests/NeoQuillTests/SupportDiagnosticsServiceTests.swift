import XCTest
@testable import NeoQuill

final class SupportDiagnosticsServiceTests: XCTestCase {
    func testReportRedactsSensitiveSettingsAndHomePath() throws {
        let root = temporaryDirectory()
        let appSupport = root.appendingPathComponent("Library/Application Support/NeoQuill", isDirectory: true)
        let recordings = appSupport.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: appSupport.appendingPathComponent("meetings.sqlite"))
        try Data([4, 5]).write(to: appSupport.appendingPathComponent("speakers.sqlite"))
        try Data([6, 7, 8, 9]).write(to: recordings.appendingPathComponent("meeting-1.wav"))

        let defaults = UserDefaults(suiteName: "SupportDiagnosticsServiceTests-\(UUID().uuidString)")!
        defaults.set("Niko Secret", forKey: AppSettings.ownerDisplayName)
        defaults.set("https://jira.secret.local", forKey: AppSettings.actionJiraBaseURL)
        defaults.set("https://hooks.secret.local", forKey: AppSettings.actionWebhookURL)
        defaults.set("nikola@example.com", forKey: AppSettings.actionDefaultRecipient)
        defaults.set("hardware-id-123", forKey: AppSettings.micDeviceId)
        defaults.set("openai_whisper-small", forKey: AppSettings.whisperModel)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel)
        defaults.set(true, forKey: AppSettings.speakerDiarization)

        let report = try SupportDiagnosticsService.makeReport(
            appVersion: appVersion,
            applicationSupportDirectory: appSupport,
            recordingsDirectory: recordings,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 0),
            homeDirectory: root
        )
        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(report.generatedAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(report.storage.applicationSupportPath, "~/Library/Application Support/NeoQuill")
        XCTAssertEqual(report.storage.meetingsDatabase.bytes, 3)
        XCTAssertEqual(report.storage.speakersDatabase.bytes, 2)
        XCTAssertEqual(report.storage.recordingsDirectory.fileCount, 1)
        XCTAssertEqual(report.storage.recordingsDirectory.bytes, 4)
        XCTAssertTrue(json.contains(AppSettings.whisperModel))
        XCTAssertTrue(json.contains("mic_device_selected"))
        XCTAssertFalse(json.contains("Niko Secret"))
        XCTAssertFalse(json.contains("jira.secret"))
        XCTAssertFalse(json.contains("hooks.secret"))
        XCTAssertFalse(json.contains("nikola@example.com"))
        XCTAssertFalse(json.contains("hardware-id-123"))
        XCTAssertFalse(json.contains(root.path))
    }

    func testExportBundleWritesJsonAndReadme() throws {
        let directory = temporaryDirectory()
        let report = try SupportDiagnosticsService.makeReport(
            appVersion: appVersion,
            applicationSupportDirectory: directory.appendingPathComponent("NeoQuill", isDirectory: true),
            recordingsDirectory: directory.appendingPathComponent("NeoQuill/recordings", isDirectory: true),
            defaults: UserDefaults(suiteName: "SupportDiagnosticsServiceTests-\(UUID().uuidString)")!,
            now: Date(timeIntervalSince1970: 0),
            homeDirectory: directory
        )

        let folder = try SupportDiagnosticsService.exportBundle(
            report: report,
            to: directory,
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(folder.lastPathComponent, "NeoQuill-Diagnostics-19700101-000000")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("diagnostics.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("README.txt").path))
    }

    private var appVersion: AppVersionInfo {
        AppVersionInfo(
            version: "0.9.4",
            build: "65",
            gitCommit: "abcdef0",
            gitBranch: "test",
            gitDirty: "clean",
            buildDate: "2026-05-24T00:00:00Z"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("SupportDiagnosticsServiceTests-\(UUID().uuidString)", isDirectory: true)
    }
}
