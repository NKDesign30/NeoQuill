import AppKit
import Foundation
import UserNotifications

/// Optionaler Background-Service: beobachtet ~/Downloads auf neue Plattform-Transkriptdateien
/// (Teams VTT, Teams Metadata JSON, Meet Entries, Zoom Timeline). Bei Treffer poste eine
/// macOS-Notification + ein internes Event mit Match-Kandidaten — die UI uebernimmt.
///
/// Activation: UserDefault `auto_watch_downloads_for_transcripts` (default false).
/// Persistenz: bereits verarbeitete Pfade landen in UserDefaults `processed_transcript_files`.
@MainActor
enum TranscriptDownloadWatcher {
    enum Hint: String, Codable, CaseIterable {
        case teamsVTT
        case teamsMetadata
        case meetEntries
        case zoomVTT
        case zoomTimeline
        case generic

        var platform: Platform {
            switch self {
            case .teamsVTT, .teamsMetadata: return .teams
            case .meetEntries:              return .meet
            case .zoomVTT, .zoomTimeline:   return .zoom
            case .generic:                  return .meet
            }
        }
    }

    struct Detection: Equatable {
        let fileURL: URL
        let hint: Hint
        let detectedAt: Date
    }

    private static let processedKey = "processed_transcript_files"
    private static var dispatchSource: DispatchSourceFileSystemObject?
    private static var fileDescriptor: CInt = -1
    private static var notificationsRequested = false

    // MARK: - Activation

    static func installIfEnabled() {
        guard UserDefaults.standard.bool(forKey: AppSettings.autoWatchDownloadsForTranscripts) else { return }
        startWatching()
    }

    static func startWatching(directory: URL = defaultDownloadsDirectory()) {
        stopWatching()
        ensureNotificationPermission()

        let path = directory.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("[TranscriptDownloadWatcher] open(\(path)) failed errno=\(errno)")
            return
        }
        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: .main
        )
        source.setEventHandler {
            scanDirectory(directory)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        dispatchSource = source
        scanDirectory(directory)
    }

    static func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fileDescriptor = -1
    }

    // MARK: - Pure helpers (testbar)

    static func detectHint(filename: String) -> Hint? {
        let lower = filename.lowercased()
        guard lower.hasSuffix(".vtt") || lower.hasSuffix(".json") else { return nil }
        if lower.contains("teams") && lower.hasSuffix(".vtt") { return .teamsVTT }
        if lower.contains("teams") && lower.contains("metadata") { return .teamsMetadata }
        if lower.contains("teams") && lower.hasSuffix(".json") { return .teamsMetadata }
        if lower.contains("meet") && lower.hasSuffix(".json") { return .meetEntries }
        if lower.contains("google") && lower.hasSuffix(".json") { return .meetEntries }
        if lower.contains("zoom") && lower.hasSuffix(".vtt") { return .zoomVTT }
        if lower.contains("zoom") && lower.contains("timeline") { return .zoomTimeline }
        if lower.contains("zoom") && lower.hasSuffix(".json") { return .zoomTimeline }
        if lower.hasSuffix(".vtt") { return .generic }
        return nil
    }

    /// Liefert Meeting-IDs deren Start-Datum innerhalb von ±2h um den Detection-Zeitpunkt liegt,
    /// sortiert nach zeitlicher Naehe (naechstes Match zuerst).
    static func candidateMeetingIds(
        for detectedAt: Date,
        meetings: [MeetingSummary],
        windowSeconds: TimeInterval = 7200
    ) -> [String] {
        let referenceTime = detectedAt.timeIntervalSince1970
        let scored: [(id: String, distance: TimeInterval)] = meetings.compactMap { summary in
            guard let start = recordingTimestamp(from: summary.id) else { return nil }
            let distance = abs(start - referenceTime)
            guard distance <= windowSeconds else { return nil }
            return (summary.id, distance)
        }
        return scored
            .sorted { $0.distance < $1.distance }
            .map { $0.id }
    }

    /// Meeting-IDs sind im Format `rec-<unixTimestamp>` (siehe RecordingController).
    /// Liefert das Recording-Start-Date oder nil wenn kein parseable Suffix.
    static func recordingTimestamp(from meetingId: String) -> TimeInterval? {
        let trimmed = meetingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("rec-") ? String(trimmed.dropFirst(4)) : trimmed
        guard let value = TimeInterval(stripped) else { return nil }
        return value
    }

    static func processedPaths() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: processedKey) ?? [])
    }

    static func markProcessed(_ url: URL) {
        var current = processedPaths()
        current.insert(url.path)
        UserDefaults.standard.set(Array(current), forKey: processedKey)
    }

    // MARK: - Scanning + Notification

    private static func scanDirectory(_ directory: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return
        }
        let alreadyProcessed = processedPaths()
        for case let url as URL in enumerator {
            guard !alreadyProcessed.contains(url.path) else { continue }
            guard let hint = detectHint(filename: url.lastPathComponent) else { continue }
            stableCheck(url: url) { stable in
                guard stable else { return }
                postDetection(Detection(fileURL: url, hint: hint, detectedAt: Date()))
            }
        }
    }

    private static func stableCheck(url: URL, attempt: Int = 0, completion: @escaping (Bool) -> Void) {
        let fm = FileManager.default
        guard let firstSize = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int else {
            completion(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let secondSize = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int else {
                completion(false)
                return
            }
            if firstSize == secondSize, firstSize > 0 {
                completion(true)
            } else if attempt < 2 {
                stableCheck(url: url, attempt: attempt + 1, completion: completion)
            } else {
                completion(false)
            }
        }
    }

    private static func postDetection(_ detection: Detection) {
        markProcessed(detection.fileURL)
        NotificationCenter.default.post(
            name: .transcriptCandidateDetected,
            object: nil,
            userInfo: [
                "fileURL": detection.fileURL,
                "hint": detection.hint.rawValue,
                "detectedAt": detection.detectedAt
            ]
        )
        scheduleSystemNotification(detection)
    }

    private static func scheduleSystemNotification(_ detection: Detection) {
        let content = UNMutableNotificationContent()
        content.title = "Transkript erkannt"
        content.body = "\(detection.fileURL.lastPathComponent) — auf Meeting anwenden?"
        content.sound = .default
        content.userInfo = ["fileURL": detection.fileURL.path]
        let request = UNNotificationRequest(identifier: "transcript-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    private static func ensureNotificationPermission() {
        guard !notificationsRequested else { return }
        notificationsRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated static func defaultDownloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
    }
}

extension Notification.Name {
    static let transcriptCandidateDetected = Notification.Name("com.neon.quill.transcriptCandidateDetected")
}
