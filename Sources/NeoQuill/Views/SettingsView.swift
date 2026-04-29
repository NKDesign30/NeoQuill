import SwiftUI
import AVFoundation

// Settings-Scene: Audio (Mic+Whisper-Modell) · KI (Diarization) · Permissions.
// Apple-HIG-Form mit Neon-Tokens für Status, sonst Standard-Look.

struct SettingsView: View {
    var body: some View {
        TabView {
            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "mic.fill") }

            AIIntelligenceTab()
                .tabItem { Label("KI", systemImage: "sparkles") }

            PermissionsTab()
                .tabItem { Label("Berechtigungen", systemImage: "lock.shield") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct AudioSettingsTab: View {
    @AppStorage(AppSettings.whisperModel) private var whisperModel: String = "openai_whisper-base"
    @AppStorage(AppSettings.micDeviceId)  private var micDeviceId: String = ""
    @AppStorage(AppSettings.language)     private var language: String = "de"
    @AppStorage(AppSettings.autoDetectMeetings) private var autoDetect: Bool = true
    @AppStorage(AppSettings.sidebarDensity) private var density: String = "regular"

    private let availableModels = [
        ("openai_whisper-tiny",   "Tiny (schnell, ~80 MB)"),
        ("openai_whisper-base",   "Base (Standard, ~150 MB)"),
        ("openai_whisper-small",  "Small (~480 MB)"),
        ("openai_whisper-medium", "Medium (~1.5 GB)"),
    ]

    var body: some View {
        Form {
            Section("Mikrofon") {
                Picker("Eingabegerät", selection: $micDeviceId) {
                    Text("Standard").tag("")
                    ForEach(MicEnumerator.list(), id: \.id) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                Toggle("Auto-Detection: Teams · Zoom · Google Meet", isOn: $autoDetect)
            }

            Section("Transkription") {
                Picker("WhisperKit-Modell", selection: $whisperModel) {
                    ForEach(availableModels, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                Picker("Sprache", selection: $language) {
                    Text("Deutsch").tag("de")
                    Text("Englisch").tag("en")
                    Text("Auto-Detect").tag("auto")
                }
            }

            Section("Sidebar") {
                Picker("Dichte", selection: $density) {
                    Text("Kompakt").tag("compact")
                    Text("Standard").tag("regular")
                    Text("Komfort").tag("comfy")
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
    }
}

private struct AIIntelligenceTab: View {
    @AppStorage(AppSettings.speakerDiarization) private var diarize: Bool = true

    var body: some View {
        Form {
            Section("Speaker-Detection") {
                Toggle("Speaker-Diarization (FluidAudio)", isOn: $diarize)
                Text("Erkennt automatisch wer wann spricht. Modelle (~140 MB) werden beim ersten Aktivieren geladen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Zusammenfassung") {
                LabeledContent("Provider", value: "Apple Foundation Models · on-device")
                Text("In Kürze: TLDR, Highlights, Action-Items via lokales LLM.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
    }
}

private struct PermissionsTab: View {
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @EnvironmentObject private var state: AppState
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Mikrofon") {
                LabeledContent("Status") {
                    Text(micGranted ? "Erteilt" : "Fehlt")
                        .foregroundStyle(micGranted ? Neon.brandPrimary : Neon.statusError)
                }
                Button("Status neu prüfen") {
                    micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                }
            }
            Section("Bildschirm- & System-Audio") {
                Text("Wird beim ersten Teams-/Zoom-Tap automatisch angefragt. Falls verweigert: Systemeinstellungen → Datenschutz → System-Audio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Systemeinstellungen öffnen") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section("Daten") {
                Text("Setzt alle Aufnahmen zurück und re-seedet die Mock-Daten.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Aufnahmen zurücksetzen") {
                    showResetConfirm = true
                }
                .foregroundStyle(Neon.statusError)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .confirmationDialog(
            "Alle Aufnahmen löschen?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Ja, alles wischen", role: .destructive) {
                state.store.resetAllMeetings()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Setzt die Sidebar auf die Mock-Daten zurück. Real aufgenommene Meetings gehen verloren.")
        }
    }
}

private enum MicEnumerator {
    struct Device: Identifiable { let id: String; let name: String }

    static func list() -> [Device] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.map { Device(id: $0.uniqueID, name: $0.localizedName) }
    }
}
