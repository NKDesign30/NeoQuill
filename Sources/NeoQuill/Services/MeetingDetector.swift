import Foundation
import Combine
import CoreAudio
import AppKit
import os.log

private let detectorLogger = Logger(subsystem: "com.neon.neoquill", category: "MeetingDetector")

struct AudioProcessActivity: Equatable {
    let bundleIdentifier: String
    let isRunningInput: Bool
    let isRunningOutput: Bool
    let isRunning: Bool
}

/// Erkannte Call-App
enum CallApp: String, CaseIterable {
    case teams = "Microsoft Teams"
    case zoom = "Zoom"
    case facetime = "FaceTime"
    case slack = "Slack"
    case webex = "WebEx"
    case discord = "Discord"
    case browser = "Browser Call"
    case unknown = "Call"

    /// Bundle ID für ScreenCaptureKit Audio-Capture
    var bundleIdentifiers: [String] {
        switch self {
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .zoom: return ["us.zoom.xos"]
        case .facetime: return ["com.apple.FaceTime"]
        case .slack: return ["com.tinyspeck.slackmacgap"]
        case .webex: return ["com.webex.meetingmanager", "Cisco-Systems.Spark"]
        case .discord: return ["com.hnc.Discord"]
        case .browser: return ["com.google.Chrome", "com.apple.Safari",
                               "com.microsoft.edgemac", "org.mozilla.firefox",
                               "company.thebrowser.Browser"]
        case .unknown: return []
        }
    }

    /// Erkennungs-Reihenfolge: spezifische Apps vor dem generischen Browser.
    /// Single Source der Priorität — genutzt von der aktiven Audio-Detection
    /// (`detectRunningCallAudioProcess`) und dem Bundle-Match (`match`).
    static let detectionPriority: [CallApp] = [.teams, .zoom, .facetime, .slack, .webex, .discord, .browser]

    /// Erste Call-App (nach Priorität), deren Bundle-ID unter den laufenden
    /// liegt. Eine Stelle für „welche Bundle-ID gehört zu welcher App" statt
    /// hartkodierter if-Ketten.
    static func match(runningBundleIds: Set<String>) -> CallApp? {
        detectionPriority.first { app in
            app.bundleIdentifiers.contains { runningBundleIds.contains($0) }
        }
    }
}

/// Erkennt aktive Calls in Teams, Zoom, FaceTime, Slack, Discord, Browser
@MainActor
final class MeetingDetector: ObservableObject {
    @Published var isInMeeting = false
    @Published var meetingName: String = "Meeting"
    @Published var meetingType: MeetingType = .general
    @Published var detectedApp: CallApp = .unknown

    private var timer: Timer?
    private var confirmCount = 0
    private let requiredConfirms = 2  // 2x bestätigt (4s) = sicher im Call

    private let detectionQueue = DispatchQueue(label: "com.quill.detection", qos: .utility)

    /// Einmalige Detection: prueft welche Call-App gerade laeuft
    func detectOnce() {
        if let app = detectActiveCall() {
            detectedApp = app
            detectorLogger.warning("detectOnce: \(app.rawValue, privacy: .public)")
        } else {
            // Fallback: schaue welche Call-Apps offen sind (auch ohne aktives Mic).
            // Browser bewusst ausgenommen — ein offener Browser ist kein Call-Signal
            // (anders als in detectActiveCall, das durch aktives Mic gegated ist).
            let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
            if let app = CallApp.match(runningBundleIds: bundleIDs), app != .browser {
                detectedApp = app
            }
            if detectedApp != .unknown {
                detectorLogger.warning("detectOnce Fallback: \(self.detectedApp.rawValue, privacy: .public)")
            }
        }

        // Kalender-Event für besseren Meeting-Namen holen (gleiche Logik wie Auto-Detection)
        if detectedApp != .unknown {
            fetchCalendarEventInBackground()
        } else {
            // Kein App erkannt — Zeit als Fallback
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            meetingName = "Meeting \(formatter.string(from: Date()))"
        }
    }

    func startMonitoring() {
        guard timer == nil else { return }
        runDetectionInBackground()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.runDetectionInBackground()
        }
        print("[Quill] Meeting-Detection gestartet (Teams, Zoom, FaceTime, Slack, Discord, Browser)")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Fuehrt die Detection auf einem Background-Thread aus (pgrep blockiert sonst Main Thread)
    nonisolated private func runDetectionInBackground() {
        detectionQueue.async { [weak self] in
            let activeApp = self?.detectActiveCall()
            Task { @MainActor [weak self] in
                self?.handleDetectionResult(activeApp)
            }
        }
    }

    private func handleDetectionResult(_ activeApp: CallApp?) {
        let inCall = activeApp != nil

        if inCall && !isInMeeting {
            confirmCount += 1
            if confirmCount >= requiredConfirms {
                isInMeeting = true
                detectedApp = activeApp ?? .unknown
                confirmCount = 0
                // Vorläufiger Name bis Kalender-Event geladen ist
                if meetingName == "Meeting" {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    meetingName = "\(detectedApp.rawValue) \(formatter.string(from: Date()))"
                }
                fetchCalendarEventInBackground()
                detectorLogger.warning("Call erkannt: \(self.detectedApp.rawValue, privacy: .public), bundleIds=\(self.detectedApp.bundleIdentifiers, privacy: .public)")
            }
        } else if !inCall && isInMeeting {
            detectorLogger.warning("Call beendet: \(self.detectedApp.rawValue, privacy: .public)")
            isInMeeting = false
            confirmCount = 0
            meetingName = "Meeting"
            meetingType = .general
            detectedApp = .unknown
        } else if !inCall {
            confirmCount = 0
        }
    }

    /// Prüft ob eine Call-App aktiv ist.
    /// Strategie 1: Teams Power Assertion "Microsoft Teams Call in progress" (zuverlaessigste Methode)
    /// Strategie 2: CoreAudio Mic aktiv + bekannte Call-App laeuft (fuer Zoom, Slack, etc.)
    /// Adaptiert von: github.com/RobertD502/TeamsStatusMacOS (MIT)
    nonisolated private func detectActiveCall() -> CallApp? {
        // Strategie 1: Teams Power Assertion (zuverlaessigste Methode, auch bei gemutetem Mic)
        if Self.hasTeamsPowerAssertion() { return .teams }

        // Strategie 2: CoreAudio Process-Status. Teams setzt 2026 nicht immer
        // eine Power Assertion, taucht aber als laufender Audio-Prozess auf.
        if let app = Self.detectRunningCallAudioProcess() { return app }

        // Strategie 3: Mic aktiv bei einer ANDEREN App (nicht Quill selbst)
        // Wir prüfen ob ein Input-Device IO hat, das NICHT das RØDE/USB-Mic ist
        // (Quill nutzt das RØDE selbst, das wuerde sonst immer triggern)
        let externalMicActive = Self.isMicrophoneInUseExcludingUSB()
        guard externalMicActive else { return nil }

        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return CallApp.match(runningBundleIds: bundleIDs)
    }

    nonisolated private static func detectRunningCallAudioProcess() -> CallApp? {
        let running = runningAudioActivities()
        guard !running.isEmpty else { return nil }
        return detectRunningCallAudioProcess(from: running)
    }

    nonisolated static func detectRunningCallAudioProcess(from activities: [AudioProcessActivity]) -> CallApp? {
        guard !activities.isEmpty else { return nil }
        return CallApp.detectionPriority.first { app in
            activities.contains { activity in
                guard app.bundleIdentifiers.contains(where: { bundleIdMatches(activity.bundleIdentifier, target: $0) }) else {
                    return false
                }

                if app == .browser {
                    return activity.isRunningInput
                }

                return activity.isRunningInput || activity.isRunningOutput || activity.isRunning
            }
        }
    }

    nonisolated private static func bundleIdMatches(_ bundleId: String, target: String) -> Bool {
        bundleId == target || bundleId.hasPrefix(target + ".")
    }

    nonisolated private static func runningAudioActivities() -> [AudioProcessActivity] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &objectIDs
        )
        guard dataStatus == noErr else { return [] }

        return objectIDs.compactMap { objectID in
            let isRunningInput = Self.readProcessIsRunning(objectID, selector: kAudioProcessPropertyIsRunningInput)
            let isRunningOutput = Self.readProcessIsRunning(objectID, selector: kAudioProcessPropertyIsRunningOutput)
            let isRunning = Self.readProcessIsRunning(objectID, selector: kAudioProcessPropertyIsRunning)
            guard isRunningInput || isRunningOutput || isRunning,
                  let bundleId = Self.readProcessBundleId(objectID) else { return nil }

            return AudioProcessActivity(
                bundleIdentifier: bundleId,
                isRunningInput: isRunningInput,
                isRunningOutput: isRunningOutput,
                isRunning: isRunning
            )
        }
    }

    nonisolated private static func readProcessBundleId(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID)
        guard status == noErr, let bundleID else { return nil }
        let result = bundleID.takeUnretainedValue() as String
        return result.isEmpty ? nil : result
    }

    nonisolated private static func readProcessIsRunning(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }


    /// Prüft ob Teams eine Power Assertion hat = aktiver Call.
    /// Teams erstellt "Microsoft Teams Call in progress" bei jedem aktiven Call.
    /// Quelle: github.com/RobertD502/TeamsStatusMacOS (MIT-Lizenz)
    nonisolated private static func hasTeamsPowerAssertion() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("Microsoft Teams Call in progress")
        } catch {
            return false
        }
    }

    /// Prüft ob irgendein Input Device aktiv IO hat.
    /// Erkennt: Built-in Mic, USB-Mics (RØDE etc.), Bluetooth, virtuelle Audio-Devices.
    /// Während Quill selbst recordet, pausiert RecordingController den Detector,
    /// daher kein Self-Trigger-Loop trotz USB-Detection.
    nonisolated private static func isMicrophoneInUseExcludingUSB() -> Bool {
        // Alle Audio-Devices holen
        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                       &devicesAddress, 0, nil, &dataSize)
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return false }

        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &devicesAddress, 0, nil, &dataSize, &deviceIDs)

        for deviceID in deviceIDs {
            // Hat das Device Input-Streams?
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var inputSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize)
            guard inputSize > 0 else { continue }

            // Laeuft IO auf diesem Input Device?
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &isRunning)
            if status == noErr && isRunning != 0 {
                return true
            }
        }
        return false
    }

    /// Liest aktuelles Kalender-Event fuer Meeting-Name und Typ (Background Thread)
    private func fetchCalendarEventInBackground() {
        let currentApp = detectedApp
        detectionQueue.async { [weak self] in
            let script = """
            tell application "Calendar"
                set now to current date
                set matchingEvents to {}
                repeat with cal in calendars
                    set evts to (every event of cal whose start date <= now and end date >= now)
                    repeat with evt in evts
                        set end of matchingEvents to (summary of evt)
                    end repeat
                end repeat
                if (count of matchingEvents) > 0 then
                    return item 1 of matchingEvents
                else
                    return ""
                end if
            end tell
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            var title = ""
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                title = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            } catch {
                // Fallback
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !title.isEmpty {
                    self.meetingName = title
                    self.meetingType = self.detectMeetingType(from: title)
                } else {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    self.meetingName = "\(currentApp.rawValue) \(formatter.string(from: Date()))"
                }
            }
        }
    }

    /// Erkennt Meeting-Typ aus dem Titel
    private func detectMeetingType(from title: String) -> MeetingType {
        let lower = title.lowercased()
        let patterns: [(MeetingType, [String])] = [
            (.standup, ["standup", "daily", "sync", "check-in"]),
            (.retro, ["retro", "retrospective"]),
            (.planning, ["planning", "refinement", "grooming"]),
            (.review, ["review", "demo", "showcase"]),
            (.oneOnOne, ["1:1", "1on1", "one-on-one"]),
            (.interview, ["interview", "bewerbung"]),
            (.workshop, ["workshop", "brainstorm"]),
        ]

        for (type, keywords) in patterns {
            if keywords.contains(where: { lower.contains($0) }) {
                return type
            }
        }
        return .general
    }
}
