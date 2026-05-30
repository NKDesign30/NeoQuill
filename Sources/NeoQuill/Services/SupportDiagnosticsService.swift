import AVFoundation
import Foundation
import Security

struct SupportDiagnosticsReport: Codable, Equatable {
    let generatedAt: String
    let app: SupportDiagnosticsApp
    let storage: SupportDiagnosticsStorage
    let settings: [SupportDiagnosticsSetting]
    let privacyNotice: String
}

struct SupportDiagnosticsApp: Codable, Equatable {
    let version: String
    let build: String
    let gitCommit: String
    let gitBranch: String
    let gitDirty: String
    let buildDate: String
    let signature: SupportDiagnosticsSignature
}

struct SupportDiagnosticsSignature: Codable, Equatable {
    let bundlePath: String
    let bundleIdentifier: String
    let status: String
    let statusCode: Int
}

struct SupportDiagnosticsStorage: Codable, Equatable {
    let applicationSupportPath: String
    let meetingsDatabase: SupportDiagnosticsFile
    let speakersDatabase: SupportDiagnosticsFile
    let recordingsDirectory: SupportDiagnosticsDirectory
    let recordingAudioFiles: [SupportDiagnosticsAudioFile]
}

struct SupportDiagnosticsFile: Codable, Equatable {
    let path: String
    let exists: Bool
    let bytes: Int64
}

struct SupportDiagnosticsDirectory: Codable, Equatable {
    let path: String
    let exists: Bool
    let fileCount: Int
    let bytes: Int64
}

struct SupportDiagnosticsAudioFile: Codable, Equatable {
    let path: String
    let stem: String
    let readable: Bool
    let bytes: Int64
    let sampleRate: Double?
    let channels: Int?
    let frames: Int64?
    let durationSeconds: Double?
}

struct SupportDiagnosticsSetting: Codable, Equatable {
    let key: String
    let value: String
}

enum SupportDiagnosticsService {
    static let privacyNotice = "Enthält keine Meeting-Titel, Transkripte, Audio-Inhalte, Namen, URLs, API-Keys oder Keychain-Werte."

    static func makeReport(
        appVersion: AppVersionInfo = .current(),
        applicationSupportDirectory: URL = MeetingStore.applicationSupportDirectory(),
        recordingsDirectory: URL = AudioWriter.recordingsDirectory(),
        defaults: UserDefaults = .standard,
        now: Date = Date(),
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> SupportDiagnosticsReport {
        let generatedAt = iso8601String(from: now)
        let app = SupportDiagnosticsApp(
            version: appVersion.version,
            build: appVersion.build,
            gitCommit: appVersion.gitCommit,
            gitBranch: appVersion.gitBranch,
            gitDirty: appVersion.gitDirty,
            buildDate: appVersion.buildDate,
            signature: signatureSnapshot(
                bundleURL: bundleURL,
                bundleIdentifier: bundleIdentifier,
                homeDirectory: homeDirectory
            )
        )
        let storage = SupportDiagnosticsStorage(
            applicationSupportPath: redactedPath(applicationSupportDirectory, homeDirectory: homeDirectory),
            meetingsDatabase: fileSnapshot(
                applicationSupportDirectory.appendingPathComponent("meetings.sqlite"),
                fileManager: fileManager,
                homeDirectory: homeDirectory
            ),
            speakersDatabase: fileSnapshot(
                applicationSupportDirectory.appendingPathComponent("speakers.sqlite"),
                fileManager: fileManager,
                homeDirectory: homeDirectory
            ),
            recordingsDirectory: try directorySnapshot(
                recordingsDirectory,
                fileManager: fileManager,
                homeDirectory: homeDirectory
            ),
            recordingAudioFiles: try recordingAudioSnapshots(
                recordingsDirectory,
                fileManager: fileManager,
                homeDirectory: homeDirectory
            )
        )

        return SupportDiagnosticsReport(
            generatedAt: generatedAt,
            app: app,
            storage: storage,
            settings: safeSettings(defaults: defaults),
            privacyNotice: privacyNotice
        )
    }

    static func exportBundle(
        report: SupportDiagnosticsReport,
        to directory: URL,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let folder = directory.appendingPathComponent("NeoQuill-Diagnostics-\(compactTimestamp(from: now))", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: folder.appendingPathComponent("diagnostics.json"), options: .atomic)
        try summary(report).write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        return folder
    }

    static func exportBundleToDesktop() throws -> URL {
        let now = Date()
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let report = try makeReport(now: now)
        return try exportBundle(report: report, to: desktop, now: now)
    }

    private static func safeSettings(defaults: UserDefaults) -> [SupportDiagnosticsSetting] {
        [
            stringSetting(AppSettings.whisperModel, defaults: defaults),
            stringSetting(AppSettings.language, defaults: defaults),
            stringSetting(AppSettings.sidebarDensity, defaults: defaults),
            stringSetting(AppSettings.detailLayout, defaults: defaults),
            stringSetting(AppSettings.aiSummaryProvider, defaults: defaults),
            stringSetting(AppSettings.aiSummaryModel, defaults: defaults),
            stringSetting(AppSettings.recordHotkey, defaults: defaults),
            boolSetting(AppSettings.autoDetectMeetings, defaults: defaults),
            boolSetting(AppSettings.speakerDiarization, defaults: defaults),
            boolSetting(AppSettings.liveCaptionCapture, defaults: defaults),
            boolSetting(AppSettings.autoWatchDownloadsForTranscripts, defaults: defaults),
            boolSetting(AppSettings.voiceIdEnrolled, defaults: defaults),
            boolSetting(AppSettings.calendarParticipantPool, defaults: defaults),
            boolSetting(AppSettings.claudeAnalysisEnabled, defaults: defaults),
            boolSetting(AppSettings.localOnlyMode, defaults: defaults),
            boolSetting(AppSettings.deleteAudioAfterTranscription, defaults: defaults),
            boolSetting(AppSettings.actionNeoSkillBridgeEnabled, defaults: defaults),
            boolSetting(AppSettings.captureSourceTeams, defaults: defaults),
            boolSetting(AppSettings.captureSourceZoom, defaults: defaults),
            boolSetting(AppSettings.captureSourceMeet, defaults: defaults),
            boolSetting(AppSettings.captureSourceSystem, defaults: defaults),
            boolSetting(AppSettings.captureSourceLocal, defaults: defaults),
            boolSetting(AppSettings.profileOnboarded, defaults: defaults),
            SupportDiagnosticsSetting(
                key: "mic_device_selected",
                value: (defaults.string(forKey: AppSettings.micDeviceId)?.isEmpty == false).description
            ),
        ]
        .sorted { $0.key < $1.key }
    }

    private static func stringSetting(_ key: String, defaults: UserDefaults) -> SupportDiagnosticsSetting {
        SupportDiagnosticsSetting(key: key, value: defaults.string(forKey: key) ?? "")
    }

    private static func boolSetting(_ key: String, defaults: UserDefaults) -> SupportDiagnosticsSetting {
        SupportDiagnosticsSetting(key: key, value: defaults.bool(forKey: key).description)
    }

    private static func fileSnapshot(
        _ url: URL,
        fileManager: FileManager,
        homeDirectory: URL
    ) -> SupportDiagnosticsFile {
        guard fileManager.fileExists(atPath: url.path) else {
            return SupportDiagnosticsFile(
                path: redactedPath(url, homeDirectory: homeDirectory),
                exists: false,
                bytes: 0
            )
        }
        return SupportDiagnosticsFile(
            path: redactedPath(url, homeDirectory: homeDirectory),
            exists: true,
            bytes: fileSize(url, fileManager: fileManager)
        )
    }

    private static func signatureSnapshot(
        bundleURL: URL,
        bundleIdentifier: String?,
        homeDirectory: URL
    ) -> SupportDiagnosticsSignature {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            bundleURL.absoluteURL as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            return SupportDiagnosticsSignature(
                bundlePath: redactedPath(bundleURL, homeDirectory: homeDirectory),
                bundleIdentifier: normalizedBundleIdentifier(bundleIdentifier),
                status: "unavailable",
                statusCode: Int(createStatus)
            )
        }

        let checkStatus = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            nil
        )
        return SupportDiagnosticsSignature(
            bundlePath: redactedPath(bundleURL, homeDirectory: homeDirectory),
            bundleIdentifier: normalizedBundleIdentifier(bundleIdentifier),
            status: checkStatus == errSecSuccess ? "valid" : "invalid",
            statusCode: Int(checkStatus)
        )
    }

    private static func normalizedBundleIdentifier(_ bundleIdentifier: String?) -> String {
        guard let bundleIdentifier else { return "unknown" }
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private static func directorySnapshot(
        _ url: URL,
        fileManager: FileManager,
        homeDirectory: URL
    ) throws -> SupportDiagnosticsDirectory {
        guard fileManager.fileExists(atPath: url.path) else {
            return SupportDiagnosticsDirectory(
                path: redactedPath(url, homeDirectory: homeDirectory),
                exists: false,
                fileCount: 0,
                bytes: 0
            )
        }

        let files = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let regularFiles = files.filter { file in
            (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        let totalBytes = regularFiles.reduce(Int64(0)) { partial, file in
            partial + fileSize(file, fileManager: fileManager)
        }

        return SupportDiagnosticsDirectory(
            path: redactedPath(url, homeDirectory: homeDirectory),
            exists: true,
            fileCount: regularFiles.count,
            bytes: totalBytes
        )
    }

    private static func recordingAudioSnapshots(
        _ url: URL,
        fileManager: FileManager,
        homeDirectory: URL
    ) throws -> [SupportDiagnosticsAudioFile] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        let wavFiles = files
            .filter { file in
                file.pathExtension.lowercased() == "wav"
                    && ((try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return wavFiles.map { file in
            audioFileSnapshot(file, fileManager: fileManager, homeDirectory: homeDirectory)
        }
    }

    private static func audioFileSnapshot(
        _ url: URL,
        fileManager: FileManager,
        homeDirectory: URL
    ) -> SupportDiagnosticsAudioFile {
        let bytes = fileSize(url, fileManager: fileManager)
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let sampleRate = audioFile.fileFormat.sampleRate
            let frames = Int64(audioFile.length)
            let duration = sampleRate > 0 ? Double(frames) / sampleRate : nil
            return SupportDiagnosticsAudioFile(
                path: redactedPath(url, homeDirectory: homeDirectory),
                stem: recordingStem(for: url),
                readable: true,
                bytes: bytes,
                sampleRate: sampleRate,
                channels: Int(audioFile.fileFormat.channelCount),
                frames: frames,
                durationSeconds: duration
            )
        } catch {
            return SupportDiagnosticsAudioFile(
                path: redactedPath(url, homeDirectory: homeDirectory),
                stem: recordingStem(for: url),
                readable: false,
                bytes: bytes,
                sampleRate: nil,
                channels: nil,
                frames: nil,
                durationSeconds: nil
            )
        }
    }

    private static func recordingStem(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix("\(RecordingAudioStem.hq.suffix).wav") { return "hq" }
        if name.hasSuffix("\(RecordingAudioStem.mic.suffix).wav") { return "mic" }
        if name.hasSuffix("\(RecordingAudioStem.system.suffix).wav") { return "system" }
        return "mix"
    }

    private static func fileSize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.int64Value
    }

    private static func redactedPath(_ url: URL, homeDirectory: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else { return url.lastPathComponent }
        return "~" + String(path.dropFirst(home.count))
    }

    private static func summary(_ report: SupportDiagnosticsReport) -> String {
        """
        NeoQuill Diagnostics

        Version: \(report.app.version) (\(report.app.build))
        Git: \(report.app.gitBranch)@\(report.app.gitCommit) \(report.app.gitDirty)
        Erstellt: \(report.generatedAt)
        Signatur: \(report.app.signature.status) (\(report.app.signature.statusCode))
        Recordings: \(report.storage.recordingsDirectory.fileCount) Dateien, \(report.storage.recordingAudioFiles.count) Audio-Metadaten

        Datenschutz: \(report.privacyNotice)
        """
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func compactTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
