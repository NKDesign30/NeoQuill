import SwiftUI
import AVFoundation
import ApplicationServices

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
    @AppStorage(AppSettings.whisperModel) private var whisperModel: String = "openai_whisper-small"
    @AppStorage(AppSettings.micDeviceId)  private var micDeviceId: String = ""
    @AppStorage(AppSettings.language)     private var language: String = "de"
    @AppStorage(AppSettings.autoDetectMeetings) private var autoDetect: Bool = true
    @AppStorage(AppSettings.sidebarDensity) private var density: String = "regular"
    @AppStorage(AppSettings.ownerDisplayName) private var ownerDisplayName: String = ""
    @AppStorage(AppSettings.ownerRole) private var ownerRole: String = "Eigene Stimme"

    private let availableModels = [
        ("openai_whisper-tiny",   "Tiny (schnell, ~80 MB)"),
        ("openai_whisper-base",   "Base (schnell, ~150 MB)"),
        ("openai_whisper-small",  "Small (Standard, ~480 MB)"),
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

            Section("Eigenes Profil") {
                TextField("Name", text: $ownerDisplayName, prompt: Text(LocalSpeakerProfile.displayName))
                TextField("Rolle", text: $ownerRole)
                Text("Wird für deine Mikrofonspur verwendet. Interne Speaker-ID bleibt `ME`.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
    @AppStorage(AppSettings.liveCaptionCapture) private var liveCaptionCapture: Bool = false
    @AppStorage(AppSettings.autoWatchDownloadsForTranscripts) private var watchDownloads: Bool = false
    @AppStorage(AppSettings.voiceIdEnrolled) private var voiceIdEnrolled: Bool = false
    @AppStorage(AppSettings.calendarParticipantPool) private var calendarPool: Bool = true
    @EnvironmentObject private var state: AppState
    @State private var showVoiceIdSheet = false

    var body: some View {
        Form {
            Section("Eigene Stimme") {
                LabeledContent("Voice-ID Status") {
                    Text(voiceIdEnrolled ? "Eingerichtet" : "Nicht eingerichtet")
                        .foregroundStyle(voiceIdEnrolled ? Neon.brandPrimary : Neon.statusError)
                }
                Button(voiceIdEnrolled ? "Stimme neu einrichten" : "Stimme einrichten") {
                    showVoiceIdSheet = true
                }
                Text("Einmal vorlesen, dann erkennt NeoQuill deine Stimme automatisch in jedem Meeting — ersetzt anonyme S1-Marker mit deinem Namen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Kalender-Hinweise") {
                Toggle("Teilnehmer aus Kalender als Pool nutzen", isOn: $calendarPool)
                Text("Bei aktivem Meeting werden die Kalender-Teilnehmer als Hinweis-Pool fuer unklare Speaker verwendet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Speaker-Detection") {
                Toggle("Speaker-Diarization (FluidAudio)", isOn: $diarize)
                Text("Erkennt automatisch wer wann spricht. Modelle (~140 MB) werden beim ersten Aktivieren geladen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Live-Captions") {
                Toggle("Meeting-Captions lokal lesen", isOn: $liveCaptionCapture)
                Text("Liest sichtbare Captions aus Teams, Zoom oder Google Meet lokal per macOS Accessibility. Hilft bei echten Namen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Plattform-Transkripte") {
                Toggle("Transkripte im Downloads-Ordner automatisch erkennen", isOn: $watchDownloads)
                    .onChange(of: watchDownloads) { _, newValue in
                        if newValue {
                            TranscriptDownloadWatcher.startWatching()
                        } else {
                            TranscriptDownloadWatcher.stopWatching()
                        }
                    }
                Text("NeoQuill prüft Dateinamen wie teams-transcript-*.vtt oder zoom-timeline-*.json. Inhalte verlassen den Mac nicht.")
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
        .sheet(isPresented: $showVoiceIdSheet) {
            VoiceIdOnboardingSheet(
                enrollment: state.voiceIdEnrollment,
                onDismiss: { showVoiceIdSheet = false }
            )
        }
    }
}

private struct PermissionsTab: View {
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibilityGranted = AXIsProcessTrusted()
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
            Section("Accessibility") {
                LabeledContent("Status") {
                    Text(accessibilityGranted ? "Erteilt" : "Fehlt")
                        .foregroundStyle(accessibilityGranted ? Neon.brandPrimary : Neon.statusError)
                }
                Text("Wird für lokales Caption-Capture benötigt.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(accessibilityGranted ? "Status neu prüfen" : "Accessibility erlauben") {
                    requestAccessibility()
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

    private func requestAccessibility() {
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            accessibilityGranted = AXIsProcessTrusted()
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
