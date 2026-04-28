import AVFoundation
import ApplicationServices
import AppKit
import Foundation

@Observable
@MainActor
final class PermissionGate {

    enum PermissionStatus {
        case unknown, granted, denied, restricted
    }

    private(set) var microphoneStatus: PermissionStatus = .unknown
    private(set) var accessibilityStatus: PermissionStatus = .unknown

    var canRecord: Bool {
        microphoneStatus == .granted
    }

    var hasAccessibilityPermission: Bool {
        accessibilityStatus == .granted
    }

    func refreshAll() {
        refreshMicrophone()
        checkAccessibility()
    }

    func checkMicrophone() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneStatus = .granted
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = granted ? .granted : .denied
        case .denied:
            microphoneStatus = .denied
        case .restricted:
            microphoneStatus = .restricted
        @unknown default:
            microphoneStatus = .denied
        }
    }

    /// Synchroner Re-Check ohne Dialog. Für Refresh nach Settings-Änderungen.
    func refreshMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphoneStatus = .granted
        case .denied:     microphoneStatus = .denied
        case .restricted: microphoneStatus = .restricted
        case .notDetermined: microphoneStatus = .unknown
        @unknown default: microphoneStatus = .denied
        }
    }

    func checkAccessibility() {
        // AXIsProcessTrusted() ohne Prompt — thread-safe
        let trusted = AXIsProcessTrusted()
        accessibilityStatus = trusted ? .granted : .denied
    }

    func requestAccessibility() {
        // Nativer macOS-Dialog: trägt NeoWispr automatisch in die Accessibility-Liste ein
        // und zeigt den System-Prompt. User muss dann nur noch den Toggle aktivieren.
        // Apple-stabiler Raw-Key statt CFString-Konstante (Swift 6 Concurrency-safe)
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityStatus = trusted ? .granted : .denied

        // Falls Dialog nicht reicht: Settings-Pane öffnen für direkte Navigation
        if !trusted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
