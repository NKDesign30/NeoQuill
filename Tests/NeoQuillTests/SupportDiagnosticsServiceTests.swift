import AVFoundation
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
        defaults.set("Private Speaker", forKey: AppSettings.ownerDisplayName.key)
        defaults.set("https://jira.secret.local", forKey: AppSettings.actionJiraBaseURL.key)
        defaults.set("https://hooks.secret.local", forKey: AppSettings.actionWebhookURL.key)
        defaults.set("speaker@example.com", forKey: AppSettings.actionDefaultRecipient.key)
        defaults.set("hardware-id-123", forKey: AppSettings.micDeviceId.key)
        defaults.set("openai_whisper-small", forKey: AppSettings.whisperModel.key)
        defaults.set("gpt-5.1", forKey: AppSettings.aiSummaryModel.key)
        defaults.set(true, forKey: AppSettings.speakerDiarization.key)

        let report = try SupportDiagnosticsService.makeReport(
            appVersion: appVersion,
            applicationSupportDirectory: appSupport,
            recordingsDirectory: recordings,
            defaults: defaults,
            now: Date(timeIntervalSince1970: 0),
            homeDirectory: root,
            bundleURL: appSupport.appendingPathComponent("NeoQuill.app", isDirectory: true),
            bundleIdentifier: "com.neon.neoquill.tests"
        )
        let data = try JSONEncoder().encode(report)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(report.generatedAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(report.app.signature.bundlePath, "~/Library/Application Support/NeoQuill/NeoQuill.app")
        XCTAssertEqual(report.app.signature.bundleIdentifier, "com.neon.neoquill.tests")
        XCTAssertEqual(report.app.signature.status, "unavailable")
        XCTAssertNotEqual(report.app.signature.statusCode, 0)
        XCTAssertEqual(report.storage.applicationSupportPath, "~/Library/Application Support/NeoQuill")
        XCTAssertEqual(report.storage.meetingsDatabase.bytes, 3)
        XCTAssertEqual(report.storage.speakersDatabase.bytes, 2)
        XCTAssertEqual(report.storage.recordingsDirectory.fileCount, 1)
        XCTAssertEqual(report.storage.recordingsDirectory.bytes, 4)
        XCTAssertEqual(report.storage.recordingAudioFiles.count, 1)
        let unreadableAudio = try XCTUnwrap(report.storage.recordingAudioFiles.first)
        XCTAssertEqual(unreadableAudio.path, "~/Library/Application Support/NeoQuill/recordings/meeting-1.wav")
        XCTAssertEqual(unreadableAudio.stem, "mix")
        XCTAssertFalse(unreadableAudio.readable)
        XCTAssertEqual(unreadableAudio.bytes, 4)
        XCTAssertNil(unreadableAudio.sampleRate)
        XCTAssertNil(unreadableAudio.channels)
        XCTAssertNil(unreadableAudio.frames)
        XCTAssertNil(unreadableAudio.durationSeconds)
        XCTAssertTrue(json.contains(AppSettings.whisperModel.key))
        XCTAssertTrue(json.contains("mic_device_selected"))
        XCTAssertFalse(json.contains("Private Speaker"))
        XCTAssertFalse(json.contains("jira.secret"))
        XCTAssertFalse(json.contains("hooks.secret"))
        XCTAssertFalse(json.contains("speaker@example.com"))
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
            homeDirectory: directory,
            bundleURL: directory.appendingPathComponent("NeoQuill.app", isDirectory: true),
            bundleIdentifier: nil
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

    func testReportIncludesRecordingAudioMetadataWithoutAudioContent() throws {
        let root = temporaryDirectory()
        let appSupport = root.appendingPathComponent("Library/Application Support/NeoQuill", isDirectory: true)
        let recordings = appSupport.appendingPathComponent("recordings", isDirectory: true)
        let mixURL = recordings.appendingPathComponent("meeting-42.wav")
        let hqURL = recordings.appendingPathComponent("meeting-42.hq.wav")
        let contentMarker: Float = 0.123456

        try AudioWriter.writePlaybackCompatibleWav(
            samples: Array(repeating: contentMarker, count: 16_000),
            to: mixURL
        )
        try writeStereoWav(
            left: sineSamples(sampleRate: 48_000, frames: 48_000, frequency: 220),
            right: sineSamples(sampleRate: 48_000, frames: 48_000, frequency: 330),
            sampleRate: 48_000,
            to: hqURL
        )
        try Data([1, 2, 3]).write(to: recordings.appendingPathComponent("notes.txt"))

        let report = try SupportDiagnosticsService.makeReport(
            appVersion: appVersion,
            applicationSupportDirectory: appSupport,
            recordingsDirectory: recordings,
            defaults: UserDefaults(suiteName: "SupportDiagnosticsServiceTests-\(UUID().uuidString)")!,
            now: Date(timeIntervalSince1970: 0),
            homeDirectory: root,
            bundleURL: appSupport.appendingPathComponent("NeoQuill.app", isDirectory: true),
            bundleIdentifier: "com.neon.neoquill.tests"
        )
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)

        XCTAssertEqual(report.storage.recordingsDirectory.fileCount, 3)
        XCTAssertEqual(report.storage.recordingAudioFiles.count, 2)

        let mix = try XCTUnwrap(report.storage.recordingAudioFiles.first { $0.stem == "mix" })
        XCTAssertEqual(mix.path, "~/Library/Application Support/NeoQuill/recordings/meeting-42.wav")
        XCTAssertTrue(mix.readable)
        XCTAssertEqual(try XCTUnwrap(mix.sampleRate), 16_000, accuracy: 0.1)
        XCTAssertEqual(mix.channels, 1)
        XCTAssertEqual(mix.frames, 16_000)
        XCTAssertEqual(try XCTUnwrap(mix.durationSeconds), 1.0, accuracy: 0.01)

        let hq = try XCTUnwrap(report.storage.recordingAudioFiles.first { $0.stem == "hq" })
        XCTAssertEqual(hq.path, "~/Library/Application Support/NeoQuill/recordings/meeting-42.hq.wav")
        XCTAssertTrue(hq.readable)
        XCTAssertEqual(try XCTUnwrap(hq.sampleRate), 48_000, accuracy: 0.1)
        XCTAssertEqual(hq.channels, 2)
        XCTAssertEqual(hq.frames, 48_000)
        XCTAssertEqual(try XCTUnwrap(hq.durationSeconds), 1.0, accuracy: 0.01)

        XCTAssertFalse(json.contains(root.path))
        XCTAssertFalse(json.contains(String(contentMarker)))
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

    private func writeStereoWav(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {
        let frameCount = max(left.count, right.count)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)))
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for index in 0..<frameCount {
            channels[0][index] = index < left.count ? left[index] : 0
            channels[1][index] = index < right.count ? right[index] : 0
        }
        try file.write(from: buffer)
    }

    private func sineSamples(sampleRate: Double, frames: Int, frequency: Double) -> [Float] {
        let increment = 2.0 * Double.pi * frequency / sampleRate
        return (0..<frames).map { index in
            Float(sin(Double(index) * increment)) * 0.25
        }
    }
}
