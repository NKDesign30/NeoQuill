import SwiftUI
import AppKit
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

            ActionConnectorsTab()
                .tabItem { Label("Aktionen", systemImage: "bolt.fill") }

            CloudIntegrationsTab()
                .tabItem { Label("Cloud", systemImage: "cloud.fill") }

            DataPrivacyTab()
                .tabItem { Label("Daten", systemImage: "externaldrive.fill") }

            PermissionsTab()
                .tabItem { Label("Berechtigungen", systemImage: "lock.shield") }

            BuildInfoTab()
                .tabItem { Label("Version", systemImage: "number") }
        }
        .frame(width: 660, height: 540)
    }
}

private struct CloudIntegrationsTab: View {
    @AppStorage(AppSettings.localOnlyMode) private var localOnlyMode = false
    @EnvironmentObject private var state: AppState
    @State private var lastError: String?

    var body: some View {
        Form {
            if localOnlyMode {
                Section("Cloud gesperrt") {
                    Text("Lokaler Modus ist aktiv. Cloud-Logins und Provider-Anfragen sind deaktiviert.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(CloudProvider.allCases, id: \.self) { provider in
                Section(provider.displayName) {
                    let connected = state.cloudOAuth.connectedProviders.contains(provider)
                    let configured = CloudOAuthCatalog.config(for: provider).isConfigured
                    LabeledContent("Status") {
                        Text(statusLabel(connected: connected, configured: configured))
                            .foregroundStyle(connected ? Neon.brandPrimary : Neon.statusError)
                    }
                    HStack {
                        if connected {
                            Button("Verbindung trennen") {
                                state.cloudOAuth.signOut(provider)
                            }
                            .foregroundStyle(Neon.statusError)
                        } else {
                            Button(configured ? "Mit \(provider.displayName) anmelden" : "App-Registrierung fehlt") {
                                Task { await signIn(provider) }
                            }
                            .disabled(!configured || localOnlyMode)
                        }
                    }
                    if !configured {
                        Text(configHintText(provider: provider))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(scopeText(provider: provider))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let lastError {
                Section("Letzter Fehler") {
                    Text(lastError)
                        .font(.callout)
                        .foregroundStyle(Neon.statusError)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
    }

    private func statusLabel(connected: Bool, configured: Bool) -> String {
        if connected { return "Verbunden" }
        if !configured { return "App-Registrierung fehlt" }
        return "Nicht verbunden"
    }

    private func configHintText(provider: CloudProvider) -> String {
        switch provider {
        case .teams:
            return "Microsoft Entra App registrieren, Client-ID als Info.plist-Key 'NeoQuillTeamsClientId' eintragen + Redirect-URI 'neoquill://oauth/teams'."
        case .meet:
            return "Google Cloud OAuth-Client (macOS) anlegen, Client-ID als 'NeoQuillMeetClientId' eintragen + Redirect-URI 'neoquill://oauth/meet'."
        case .zoom:
            return "Zoom Marketplace OAuth-App anlegen, Client-ID als 'NeoQuillZoomClientId' eintragen + Redirect-URI 'neoquill://oauth/zoom'."
        }
    }

    private func scopeText(provider: CloudProvider) -> String {
        let scopes = CloudOAuthCatalog.config(for: provider).scopes.joined(separator: ", ")
        return "Scopes: \(scopes)"
    }

    private func signIn(_ provider: CloudProvider) async {
        guard !localOnlyMode else {
            lastError = "Lokaler Modus ist aktiv."
            return
        }
        do {
            try await state.cloudOAuth.signIn(provider)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private struct AudioSettingsTab: View {
    @AppStorage(AppSettings.whisperModel) private var whisperModel: String = "openai_whisper-small"
    @AppStorage(AppSettings.micDeviceId)  private var micDeviceId: String = ""
    @AppStorage(AppSettings.language)     private var language: String = "auto"
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
                    Text("Auto-Detect (mehrsprachig)").tag("auto")
                    Text("Deutsch").tag("de")
                    Text("Englisch").tag("en")
                }
                Text("Für Meetings mit 2-4 Sprachen Auto-Detect nutzen. Whisper erkennt die Sprache segmentweise besser als ein hart gesetztes Deutsch-Modell.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
    @AppStorage(AppSettings.claudeAnalysisEnabled) private var claudeAnalysisEnabled: Bool = true
    @AppStorage(AppSettings.aiSummaryProvider) private var summaryProviderRaw: String = AIProviderSettings.defaultProvider
    @AppStorage(AppSettings.aiSummaryBaseURL) private var aiSummaryBaseURL: String = AIProviderSettings.defaultOpenAIBaseURL
    @AppStorage(AppSettings.aiSummaryModel) private var aiSummaryModel: String = AIProviderSettings.defaultOpenAIModel
    @AppStorage(AppSettings.speakerDiarization) private var diarize: Bool = true
    @AppStorage(AppSettings.liveCaptionCapture) private var liveCaptionCapture: Bool = false
    @AppStorage(AppSettings.autoWatchDownloadsForTranscripts) private var watchDownloads: Bool = false
    @AppStorage(AppSettings.voiceIdEnrolled) private var voiceIdEnrolled: Bool = false
    @AppStorage(AppSettings.calendarParticipantPool) private var calendarPool: Bool = true
    @EnvironmentObject private var state: AppState
    @State private var showVoiceIdSheet = false
    @State private var apiKeyInput = ""
    @State private var hasStoredAPIKey = false
    @State private var apiKeyStatus: String?

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
                Text("Bei aktivem Meeting werden die Kalender-Teilnehmer als Hinweis-Pool für unklare Speaker verwendet.")
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
                Toggle("KI-Zusammenfassung aktivieren", isOn: $claudeAnalysisEnabled)
                Picker("Provider", selection: $summaryProviderRaw) {
                    ForEach(AISummaryProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }
                if selectedSummaryProvider == .claudeCLI {
                    LabeledContent("Account", value: claudeAnalysisEnabled ? "lokaler Claude-Login" : "Aus")
                    Text("Nutzt den lokal eingeloggten Claude-Account über die Claude CLI. Kein API-Key wird in NeoQuill gespeichert.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Base URL", text: $aiSummaryBaseURL)
                    TextField("Modell", text: $aiSummaryModel)
                    LabeledContent("API-Key", value: hasStoredAPIKey ? "In Keychain gespeichert" : "Fehlt")
                    SecureField("Neuen API-Key eintragen", text: $apiKeyInput)
                    HStack {
                        Button("API-Key speichern") { saveOpenAIAPIKey() }
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("API-Key löschen") { clearOpenAIAPIKey() }
                            .disabled(!hasStoredAPIKey)
                    }
                    if let apiKeyStatus {
                        Text(apiKeyStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("OpenAI, OpenRouter, lokale Server oder andere Chat-Completions-kompatible Endpunkte. Secrets bleiben in der macOS Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            refreshAISecretState()
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

    private var selectedSummaryProvider: AISummaryProvider {
        AISummaryProvider(rawValue: summaryProviderRaw) ?? .claudeCLI
    }

    private func refreshAISecretState() {
        hasStoredAPIKey = AIProviderSecretStore().loadOpenAICompatibleAPIKey() != nil
    }

    private func saveOpenAIAPIKey() {
        do {
            try AIProviderSecretStore().saveOpenAICompatibleAPIKey(apiKeyInput)
            apiKeyInput = ""
            apiKeyStatus = "API-Key gespeichert."
            refreshAISecretState()
        } catch {
            apiKeyStatus = "API-Key konnte nicht gespeichert werden."
        }
    }

    private func clearOpenAIAPIKey() {
        AIProviderSecretStore().clearOpenAICompatibleAPIKey()
        apiKeyInput = ""
        apiKeyStatus = "API-Key gelöscht."
        refreshAISecretState()
    }
}

private struct ActionConnectorsTab: View {
    @AppStorage(AppSettings.actionDefaultRecipient) private var defaultRecipient = ""
    @AppStorage(AppSettings.actionJiraBaseURL) private var jiraBaseURL = ""
    @AppStorage(AppSettings.actionWebhookURL) private var webhookURL = ""
    @AppStorage(AppSettings.actionNeoSkillBridgeEnabled) private var neoSkillBridgeEnabled = false
    @State private var jiraMCPStatus = NeonJiraMCPStatus.empty
    @State private var jiraMCPMessage = ""
    @State private var jiraMCPInstalling = false
    @State private var jiraMCPRefreshing = false

    var body: some View {
        Form {
            Section("Review & Execute") {
                Text("NeoQuill schlägt nach dem Meeting Aktionen vor. Ausgeführt wird erst nach Klick: Mail-Draft, Kalenderdatei, Jira-Draft, Inbox-Payload oder Webhook-JSON.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Neo Skill-Bridge") {
                Toggle("Actions an Neo schicken", isOn: $neoSkillBridgeEnabled)
                Text("Nutzt die lokale Neo Action Inbox. Daraus kann Neo mit `gog`, Jira-CLI oder Skills echte Gmail-, Kalender- und Jira-Aktionen ausführen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Neon Jira MCP") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(jiraMCPStatus.installed ? Neon.statusSuccess : Neon.statusWarning)
                            .frame(width: 8, height: 8)
                        Text(jiraMCPStatus.installed ? "Installiert" : "Nicht installiert")
                            .font(.headline)
                        Spacer()
                        if jiraMCPRefreshing || jiraMCPInstalling {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text(jiraMCPStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if !jiraMCPMessage.isEmpty {
                        Text(jiraMCPMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Status prüfen") {
                        Task { await refreshJiraMCPStatus() }
                    }
                    .disabled(jiraMCPRefreshing || jiraMCPInstalling)

                    Button(jiraMCPStatus.installed ? "Neu installieren" : "Installieren") {
                        Task { await installJiraMCP() }
                    }
                    .disabled(!jiraMCPStatus.canInstall || jiraMCPInstalling)

                    Button("MCP-Config kopieren") {
                        copyJiraMCPConfig()
                    }
                    .disabled(!jiraMCPStatus.installed)
                }

                Text("Installiert `neon-jira-mcp` aus GitHub. Für echtes Ticket-Erstellen braucht der Nutzer lokal `jira login`; NeoQuill speichert keine Jira-Secrets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Google Workspace / Mail") {
                TextField("Standard-Empfänger", text: $defaultRecipient)
                Text("Mail-Aktionen öffnen einen lokalen `mailto:` Draft. Kalender-Aktionen erzeugen eine `.ics` Datei, die Google Calendar, Apple Calendar oder Outlook importieren können.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Jira") {
                TextField("Jira Base URL", text: $jiraBaseURL, prompt: Text("https://firma.atlassian.net"))
                Text("Jira-Aktionen kopieren einen Ticket-Draft mit Meeting-Kontext. Wenn eine Base URL gesetzt ist, wird Jira zusätzlich geöffnet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Webhook / Automation") {
                TextField("Webhook URL", text: $webhookURL)
                Text("Webhook-Aktionen erzeugen aktuell kopierbares JSON für Make, Zapier, n8n oder eigene APIs. Direktes POST kommt nach Auth- und Retry-Slice.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .task { await refreshJiraMCPStatus() }
    }

    private var jiraMCPStatusDetail: String {
        if jiraMCPStatus.installed {
            return "MCP-Binary: \(jiraMCPStatus.mcpPath ?? "neon-jira-mcp")"
        }
        if !jiraMCPStatus.canInstall {
            return "npm wurde nicht gefunden. Installiere Node.js/npm, danach kann NeoQuill den MCP einrichten."
        }
        return "Bereit für Installation über npm. Jira CLI: \(jiraMCPStatus.jiraPath ?? "nicht gefunden")"
    }

    private func refreshJiraMCPStatus() async {
        jiraMCPRefreshing = true
        jiraMCPStatus = await NeonJiraMCPInstaller.currentStatus()
        jiraMCPRefreshing = false
    }

    private func installJiraMCP() async {
        jiraMCPInstalling = true
        jiraMCPMessage = "Installation läuft ..."
        do {
            let output = try await NeonJiraMCPInstaller.install()
            jiraMCPMessage = output.isEmpty ? "Neon Jira MCP installiert." : output
            jiraMCPStatus = await NeonJiraMCPInstaller.currentStatus()
        } catch {
            jiraMCPMessage = error.localizedDescription
        }
        jiraMCPInstalling = false
    }

    private func copyJiraMCPConfig() {
        let snippet = NeonJiraMCPInstaller.mcpConfigSnippet(command: jiraMCPStatus.mcpPath ?? "neon-jira-mcp")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        jiraMCPMessage = "MCP-Config kopiert."
    }
}

private struct DataPrivacyTab: View {
    @AppStorage(AppSettings.localOnlyMode) private var localOnlyMode = false
    @AppStorage(AppSettings.deleteAudioAfterTranscription) private var deleteAudioAfterTranscription = false
    @EnvironmentObject private var state: AppState
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteAudioConfirm = false

    var body: some View {
        Form {
            Section("Lokale Daten") {
                LabeledContent("Datenordner", value: MeetingStore.applicationSupportDirectory().path)
                Button("Datenordner öffnen") {
                    PrivacyDataService.openLocalDataFolder()
                }
                Text("Meetings, Transkripte und Audio liegen lokal in Application Support. API-Keys liegen separat in der macOS Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Datenschutzmodus") {
                Toggle("Nur lokale Verarbeitung", isOn: $localOnlyMode)
                Text("Blockiert Cloud-Logins und KI-Provider-Aufrufe. Transkript, Export und lokale Actions bleiben nutzbar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Export") {
                Button("Alle Meetings als Markdown exportieren") {
                    exportArchive()
                }
                Text("Erstellt einen Ordner auf dem Desktop mit einer Markdown-Datei pro Meeting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnose") {
                Button("Privacy-safe Diagnosepaket exportieren") {
                    exportDiagnostics()
                }
                Text("Erstellt einen Support-Report ohne Meeting-Titel, Transkripte, Audio-Inhalte, Namen, URLs, API-Keys oder Keychain-Werte.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Audio-Retention") {
                Toggle("Audio nach fertigem Transkript löschen", isOn: $deleteAudioAfterTranscription)
                Button("Alle gespeicherten Audio-Dateien löschen") {
                    showDeleteAudioConfirm = true
                }
                .foregroundStyle(Neon.statusWarning)
                Text("Löscht nur WAV-Dateien. Meetings, Transkripte und Zusammenfassungen bleiben erhalten.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Gefahrenzone") {
                Button("Alle lokalen Meetings und Audio löschen") {
                    showDeleteAllConfirm = true
                }
                .foregroundStyle(Neon.statusError)
                Text("Dieser Kunden-Reset löscht echte Meeting-Daten ohne Demo-Re-Seed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
        .confirmationDialog(
            "Alle Audio-Dateien löschen?",
            isPresented: $showDeleteAudioConfirm,
            titleVisibility: .visible
        ) {
            Button("Audio löschen", role: .destructive) {
                deleteAudio()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Playback ist danach für bestehende Meetings nicht mehr verfügbar.")
        }
        .confirmationDialog(
            "Alle lokalen Meeting-Daten löschen?",
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Alles lokal löschen", role: .destructive) {
                deleteAll()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Meetings, Transkripte, Tasks und Audio werden gelöscht. API-Keys in Keychain bleiben erhalten.")
        }
    }

    private func exportArchive() {
        let details = state.store.meetings.compactMap { state.store.detail(for: $0.id) }
        do {
            let folder = try MeetingExporter.exportArchiveToDesktop(details)
            state.notify("Export erstellt: \(folder.lastPathComponent)")
        } catch {
            state.notify("Export fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func exportDiagnostics() {
        do {
            let folder = try SupportDiagnosticsService.exportBundleToDesktop()
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            state.notify("Diagnosepaket erstellt: \(folder.lastPathComponent)")
        } catch {
            state.notify("Diagnosepaket fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private func deleteAudio() {
        do {
            let count = try PrivacyDataService.deleteAudioFiles()
            state.store.clearAudioURLs()
            state.notify("\(count) Audio-Dateien gelöscht.")
        } catch {
            state.notify("Audio konnte nicht gelöscht werden: \(error.localizedDescription)")
        }
    }

    private func deleteAll() {
        do {
            let result = try PrivacyDataService.deleteAllLocalMeetingData(store: state.store)
            state.notify("Lokale Daten gelöscht. Audio-Dateien: \(result.audioFilesDeleted).")
        } catch {
            state.notify("Lokale Daten konnten nicht gelöscht werden: \(error.localizedDescription)")
        }
    }
}

private struct PermissionsTab: View {
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibilityGranted = AXIsProcessTrusted()

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
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
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

private struct BuildInfoTab: View {
    private let version = AppVersionInfo.current()

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: version.displayVersion)
                LabeledContent("Build-Datum", value: version.buildDate)
            }

            Section("GitHub-Stand") {
                LabeledContent("Commit", value: version.gitCommit)
                LabeledContent("Branch", value: version.gitBranch)
                LabeledContent("Status", value: version.gitDirty == "dirty" ? "Lokale Änderungen" : version.gitDirty)
                Text("Die App-Version kommt aus `VERSION`; das Build-Script schreibt Commit, Branch und Dirty-State in das App-Bundle.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 16)
    }
}

enum MicEnumerator {
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
