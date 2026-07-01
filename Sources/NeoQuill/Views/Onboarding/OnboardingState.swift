import Foundation
import AVFoundation
import ApplicationServices
import EventKit
import SwiftUI
import UserNotifications

// State des First-Run-Wizards. 6 Schritte nach Design:
// 01 Willkommen · 02 Mikrofon · 03 Stimme & Name · 04 KI-Engine ·
// 05 Quellen · 06 Startklar.

@MainActor
final class OnboardingState: ObservableObject {

    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case microphone
        case voice
        case engine
        case capture
        case ready

        var id: Int { rawValue }

        var eyebrow: String {
            switch self {
            case .welcome:    return "WILLKOMMEN"
            case .microphone: return "MIKROFON"
            case .voice:      return "STIMME & NAME"
            case .engine:     return "KI-ENGINE"
            case .capture:    return "QUELLEN"
            case .ready:      return "STARTKLAR"
            }
        }
    }

    enum PermissionStatus {
        case granted
        case denied
        case notDetermined
        case unknown

        var label: String {
            switch self {
            case .granted:       return "Erlaubt"
            case .denied:        return "Verweigert"
            case .notDetermined: return "Ausstehend"
            case .unknown:       return "Unbekannt"
            }
        }

        var color: Color {
            switch self {
            case .granted:       return Neon.brandPrimary
            case .denied:        return Neon.statusError
            case .notDetermined: return Color(hex: 0xFFB340)
            case .unknown:       return Neon.textTertiary
            }
        }
    }

    enum Engine: String, CaseIterable, Identifiable {
        case ane    = "ane"
        case cloud  = "cloud"
        var id: String { rawValue }
    }

    @Published var currentStep: Step = .welcome

    // Profil
    @Published var name: String = ""
    @Published var language: String = "auto"

    // Mikrofon
    @Published var micStatus: PermissionStatus = .unknown
    @Published var availableMics: [(id: String, name: String)] = []
    @Published var selectedMicId: String = ""

    // Engine
    @Published var engine: Engine = .ane
    @Published var claudeAnalysisEnabled: Bool = true
    @Published var summaryProviderVerified: Bool = false

    // Quellen
    @Published var captureTeams:  Bool = true
    @Published var captureZoom:   Bool = true
    @Published var captureMeet:   Bool = true
    @Published var captureSystem: Bool = true
    @Published var captureLocal:  Bool = true

    // Hotkey + Verhalten
    @Published var hotkeyParts: [String] = ["⌥", "R"]
    @Published var autoDetect: Bool = true
    @Published var liveCaptions: Bool = true
    @Published var calendarPool: Bool = true
    @Published var watchDownloads: Bool = false

    // Sekundäre Permissions
    @Published var accessibilityStatus: PermissionStatus = .unknown
    @Published var calendarStatus: PermissionStatus = .unknown
    @Published var notificationStatus: PermissionStatus = .unknown
    @Published var runtimePrepared: Bool = false

    init() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: AppSettings.ownerDisplayName.key) ?? ""
        let suggestion = NSFullUserName()
        self.name = stored.isEmpty ? suggestion : stored
        self.language = defaults.value(for: AppSettings.language)
        self.autoDetect = defaults.value(for: AppSettings.autoDetectMeetings)
        self.liveCaptions = defaults.value(for: AppSettings.liveCaptionCapture)
        self.calendarPool = defaults.value(for: AppSettings.calendarParticipantPool)
        self.watchDownloads = defaults.value(for: AppSettings.autoWatchDownloadsForTranscripts)
        self.claudeAnalysisEnabled = defaults.value(for: AppSettings.claudeAnalysisEnabled)
        self.captureTeams  = defaults.value(for: AppSettings.captureSourceTeams)
        self.captureZoom   = defaults.value(for: AppSettings.captureSourceZoom)
        self.captureMeet   = defaults.value(for: AppSettings.captureSourceMeet)
        self.captureSystem = defaults.value(for: AppSettings.captureSourceSystem)
        self.captureLocal  = defaults.value(for: AppSettings.captureSourceLocal)
        self.selectedMicId = defaults.string(forKey: AppSettings.micDeviceId.key) ?? ""
        if let raw = defaults.string(forKey: AppSettings.recordHotkey.key), !raw.isEmpty {
            self.hotkeyParts = raw.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        refreshMicList()
    }

    // MARK: - Navigation

    var canGoNext: Bool {
        switch currentStep {
        case .voice: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .microphone: return micStatus == .granted
        case .engine: return !claudeAnalysisEnabled || summaryProviderVerified
        case .ready: return runtimePrepared
        default: return true
        }
    }

    var primaryLabel: String {
        switch currentStep {
        case .welcome:    return "Loslegen"
        case .microphone: return micStatus == .granted ? "Weiter" : "Mikrofon erlauben"
        case .ready:      return runtimePrepared ? "NeoQuill öffnen" : "Runtime vorbereiten ..."
        default:          return "Weiter"
        }
    }

    var secondaryLabel: String? {
        switch currentStep {
        case .welcome:    return "Tour überspringen"
        case .microphone: return micStatus == .granted ? nil : "Später"
        case .voice:      return "Sample überspringen"
        case .engine:     return claudeAnalysisEnabled && !summaryProviderVerified ? "KI später einrichten" : nil
        default:          return nil
        }
    }

    var canGoBack: Bool { currentStep.rawValue > 0 }

    func advance() {
        if let next = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func skip() {
        if currentStep == .welcome {
            currentStep = .ready
        } else if currentStep == .engine {
            claudeAnalysisEnabled = false
            summaryProviderVerified = false
            advance()
        } else {
            advance()
        }
    }

    func goBack() {
        if let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    // MARK: - Persistence

    func persistAll() {
        let defaults = UserDefaults.standard
        defaults.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppSettings.ownerDisplayName.key)
        defaults.set(language, forKey: AppSettings.language.key)
        defaults.set(autoDetect, forKey: AppSettings.autoDetectMeetings.key)
        defaults.set(liveCaptions, forKey: AppSettings.liveCaptionCapture.key)
        defaults.set(calendarPool, forKey: AppSettings.calendarParticipantPool.key)
        defaults.set(watchDownloads, forKey: AppSettings.autoWatchDownloadsForTranscripts.key)
        defaults.set(claudeAnalysisEnabled, forKey: AppSettings.claudeAnalysisEnabled.key)
        defaults.set(captureTeams,  forKey: AppSettings.captureSourceTeams.key)
        defaults.set(captureZoom,   forKey: AppSettings.captureSourceZoom.key)
        defaults.set(captureMeet,   forKey: AppSettings.captureSourceMeet.key)
        defaults.set(captureSystem, forKey: AppSettings.captureSourceSystem.key)
        defaults.set(captureLocal,  forKey: AppSettings.captureSourceLocal.key)
        defaults.set(selectedMicId, forKey: AppSettings.micDeviceId.key)
        defaults.set(hotkeyParts.joined(separator: "+"), forKey: AppSettings.recordHotkey.key)
        defaults.set(true, forKey: AppSettings.profileOnboarded.key)
    }

    // MARK: - Permission queries

    func refreshMicList() {
        availableMics = MicEnumerator.list().map { ($0.id, $0.name) }
    }

    func refreshPermissionStates() {
        micStatus = mapMic(AVCaptureDevice.authorizationStatus(for: .audio))
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .notDetermined
        calendarStatus = mapCalendar(EKEventStore.authorizationStatus(for: .event))
        Task { await refreshNotificationState() }
    }

    func refreshNotificationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let mapped: PermissionStatus
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: mapped = .granted
        case .denied: mapped = .denied
        case .notDetermined: mapped = .notDetermined
        @unknown default: mapped = .unknown
        }
        notificationStatus = mapped
    }

    // MARK: - Permission requests

    func requestMicPermission() async {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        micStatus = mapMic(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestCalendarPermission() async {
        let store = EKEventStore()
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            _ = try? await store.requestFullAccessToEvents()
        }
        calendarStatus = mapCalendar(EKEventStore.authorizationStatus(for: .event))
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshNotificationState()
    }

    // MARK: - Mapping

    private func mapMic(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }

    private func mapCalendar(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: return .granted
        case .denied, .restricted, .writeOnly: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }
}
