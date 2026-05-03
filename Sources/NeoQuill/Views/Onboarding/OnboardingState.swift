import Foundation
import AVFoundation
import ApplicationServices
import EventKit
import SwiftUI
import UserNotifications

// Zentrale Logik des First-Run-Wizards. Schritte sind eine Aufzaehlung,
// Permissions werden hier konsolidiert abgefragt + reportiert.

@MainActor
final class OnboardingState: ObservableObject {

    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case profile
        case microphone
        case voiceId
        case permissions
        case cloud
        case ready

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome:     return "Willkommen"
            case .profile:     return "Profil"
            case .microphone:  return "Mikrofon"
            case .voiceId:     return "Stimme"
            case .permissions: return "Berechtigungen"
            case .cloud:       return "Cloud (optional)"
            case .ready:       return "Fertig"
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
            case .granted:       return "Erteilt"
            case .denied:        return "Verweigert"
            case .notDetermined: return "Noch nicht angefragt"
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

    @Published var currentStep: Step = .welcome
    @Published var name: String = ""
    @Published var role: String = ""
    @Published var language: String = "de"
    @Published var autoDetect: Bool = true
    @Published var liveCaptions: Bool = true
    @Published var watchDownloads: Bool = false
    @Published var calendarPool: Bool = true

    @Published var micStatus: PermissionStatus = .unknown
    @Published var accessibilityStatus: PermissionStatus = .unknown
    @Published var calendarStatus: PermissionStatus = .unknown
    @Published var notificationStatus: PermissionStatus = .unknown
    @Published var screenCaptureStatus: PermissionStatus = .unknown

    @Published var availableMics: [(id: String, name: String)] = []
    @Published var selectedMicId: String = ""

    init() {
        // Vorbelegen aus Defaults damit der Wizard wie ein Re-Configure wirkt,
        // falls Niko ihn aus den Settings nochmal oeffnet.
        let defaults = UserDefaults.standard
        let storedName = defaults.string(forKey: AppSettings.ownerDisplayName) ?? ""
        let suggestion = NSFullUserName()
        self.name = storedName.isEmpty ? suggestion : storedName
        self.role = defaults.string(forKey: AppSettings.ownerRole) ?? "Eigene Stimme"
        self.language = defaults.string(forKey: AppSettings.language) ?? "de"
        self.autoDetect = defaults.boolOr(AppSettings.autoDetectMeetings, default: true)
        self.liveCaptions = defaults.boolOr(AppSettings.liveCaptionCapture, default: true)
        self.watchDownloads = defaults.boolOr(AppSettings.autoWatchDownloadsForTranscripts, default: false)
        self.calendarPool = defaults.boolOr(AppSettings.calendarParticipantPool, default: true)
        self.selectedMicId = defaults.string(forKey: AppSettings.micDeviceId) ?? ""
        refreshMicList()
        refreshPermissionStates()
    }

    // MARK: - Navigation

    var canGoNext: Bool {
        switch currentStep {
        case .profile: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:       return true
        }
    }

    var nextLabel: String {
        switch currentStep {
        case .ready: return "App starten"
        case .voiceId, .cloud: return "Weiter"
        default: return "Weiter"
        }
    }

    var skipLabel: String? {
        switch currentStep {
        case .voiceId, .cloud: return "Später"
        default: return nil
        }
    }

    func advance() {
        if let next = Step(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        }
    }

    func goBack() {
        if let prev = Step(rawValue: currentStep.rawValue - 1) {
            currentStep = prev
        }
    }

    var canGoBack: Bool { currentStep != .welcome && currentStep != .ready }

    // MARK: - Persistence

    func persistAll() {
        let defaults = UserDefaults.standard
        defaults.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppSettings.ownerDisplayName)
        defaults.set(role.trimmingCharacters(in: .whitespacesAndNewlines), forKey: AppSettings.ownerRole)
        defaults.set(language, forKey: AppSettings.language)
        defaults.set(autoDetect, forKey: AppSettings.autoDetectMeetings)
        defaults.set(liveCaptions, forKey: AppSettings.liveCaptionCapture)
        defaults.set(watchDownloads, forKey: AppSettings.autoWatchDownloadsForTranscripts)
        defaults.set(calendarPool, forKey: AppSettings.calendarParticipantPool)
        defaults.set(selectedMicId, forKey: AppSettings.micDeviceId)
        defaults.set(true, forKey: AppSettings.profileOnboarded)
    }

    // MARK: - Permission queries

    func refreshMicList() {
        availableMics = MicEnumerator.list().map { ($0.id, $0.name) }
    }

    func refreshPermissionStates() {
        micStatus = mapMic(AVCaptureDevice.authorizationStatus(for: .audio))
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .notDetermined
        calendarStatus = mapCalendar(EKEventStore.authorizationStatus(for: .event))
        screenCaptureStatus = .notDetermined  // SCK liefert keinen synchronen Status
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
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            _ = try? await store.requestFullAccessToEvents()
        default: break
        }
        calendarStatus = mapCalendar(EKEventStore.authorizationStatus(for: .event))
    }

    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // ignore — refresh below liest den finalen Status
        }
        await refreshNotificationState()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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
