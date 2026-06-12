import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices

// In-App Settings-Overlay im NeoWispr-Stil: Sidebar + grouped Forms.
// Der Inhalt bleibt native macOS-Form, die Präsentation liegt im Hauptfenster.

enum QuillSettingsSection: String, CaseIterable, Identifiable {
    case audio
    case ai
    case actions
    case cloud
    case data
    case permissions
    case license
    case version

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: return "Audio"
        case .ai: return "KI"
        case .actions: return "Aktionen"
        case .cloud: return "Cloud"
        case .data: return "Daten"
        case .permissions: return "Berechtigungen"
        case .license: return "Lizenz"
        case .version: return "Version"
        }
    }

    var icon: String {
        switch self {
        case .audio: return "mic.fill"
        case .ai: return "sparkles"
        case .actions: return "bolt.fill"
        case .cloud: return "cloud.fill"
        case .data: return "externaldrive.fill"
        case .permissions: return "lock.shield"
        case .license: return "key.fill"
        case .version: return "number"
        }
    }
}

struct SettingsView: View {
    @Binding private var selection: QuillSettingsSection
    var onClose: (() -> Void)?
    private let version = AppVersionInfo.current()

    init(selection: Binding<QuillSettingsSection>, onClose: (() -> Void)? = nil) {
        _selection = selection
        self.onClose = onClose
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar

            VStack(spacing: 0) {
                settingsHeader
                Divider().background(Neon.strokeHairline)
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider().background(Neon.strokeHairline)
                versionFooter
            }
            .background(Neon.surfaceBackground)
        }
        .frame(minWidth: 780, idealWidth: 940, maxWidth: 1080, minHeight: 560, idealHeight: 660)
        .background(Neon.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
        )
        .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 18)
        .preferredColorScheme(.dark)
        .tint(Neon.brandPrimary)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETTINGS")
                .font(.neonMono(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Neon.textQuaternary)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 12)

            VStack(spacing: 4) {
                ForEach(QuillSettingsSection.allCases) { section in
                    sidebarRow(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .frame(width: 214)
        .background(Neon.surfaceSunken)
    }

    private func sidebarRow(_ section: QuillSettingsSection) -> some View {
        let isSelected = selection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isSelected ? Neon.textPrimary : Neon.textSecondary)
                    .frame(width: 18)

                Text(section.title)
                    .font(.neonBody(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Neon.textPrimary : Neon.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.07) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var settingsHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.title)
                    .font(.neonDisplay(30))
                    .foregroundStyle(Neon.textPrimary)
                Text("NeoQuill")
                    .neonEyebrow(Neon.textQuaternary)
            }
            Spacer(minLength: 0)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Neon.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                                .overlay(Circle().stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .audio:
            AudioSettingsTab()
        case .ai:
            AIIntelligenceTab()
        case .actions:
            ActionConnectorsTab()
        case .cloud:
            CloudIntegrationsTab()
        case .data:
            DataPrivacyTab()
        case .permissions:
            PermissionsTab()
        case .license:
            LicenseSettingsTab()
        case .version:
            BuildInfoTab()
        }
    }

    private var versionFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.caption)
            Text("NeoQuill \(version.displayVersion)")
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Neon.textSecondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }
}

private struct CloudIntegrationsTab: View {
    @AppStorage(AppSettings.localOnlyMode) private var localOnlyMode = false
    @AppStorage(AppSettings.cloudTeamsClientId) private var teamsClientId = ""
    @AppStorage(AppSettings.cloudTeamsScopes) private var teamsScopes = ""
    @AppStorage(AppSettings.cloudMeetClientId) private var meetClientId = ""
    @AppStorage(AppSettings.cloudMeetScopes) private var meetScopes = ""
    @AppStorage(AppSettings.cloudZoomClientId) private var zoomClientId = ""
    @AppStorage(AppSettings.cloudZoomScopes) private var zoomScopes = ""
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
                    let config = CloudOAuthCatalog.config(for: provider)
                    let connected = state.cloudOAuth.connectedProviders.contains(provider)
                    let configured = config.isConfigured
                    LabeledContent("Status") {
                        Text(statusLabel(connected: connected, configured: configured))
                            .foregroundStyle(connected ? Neon.brandPrimary : Neon.statusError)
                    }
                    TextField("Client-ID", text: clientIdBinding(for: provider), prompt: Text("OAuth Client ID"))
                    LabeledContent("Redirect URI") {
                        HStack(spacing: 8) {
                            Text(config.redirectURI.absoluteString)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Kopieren") {
                                copy(config.redirectURI.absoluteString)
                            }
                        }
                    }
                    TextField("Scopes überschreiben", text: scopesBinding(for: provider), prompt: Text("Standard-Scopes verwenden"))
                    Text("Aktive Scopes: \(config.scopes.joined(separator: ", "))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        if connected {
                            Button("Verbindung trennen") {
                                state.cloudOAuth.signOut(provider)
                            }
                            .foregroundStyle(Neon.statusError)
                        } else {
                            Button(configured ? "Mit \(provider.displayName) anmelden" : "Client-ID fehlt") {
                                Task { await signIn(provider) }
                            }
                            .disabled(!configured || localOnlyMode)
                        }
                    }
                    if !configured {
                        Text(setupHint(provider: provider))
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
        if !configured { return "Client-ID fehlt" }
        return "Nicht verbunden"
    }

    private func setupHint(provider: CloudProvider) -> String {
        switch provider {
        case .teams:
            return "Microsoft Entra App registrieren, Redirect-URI eintragen, Client-ID hier speichern. Kein Secret nötig."
        case .meet:
            return "Google Cloud OAuth-Client anlegen, Redirect-URI eintragen, Client-ID hier speichern. Kein Secret nötig."
        case .zoom:
            return "Zoom Marketplace OAuth-App anlegen, Redirect-URI eintragen, Client-ID hier speichern. Kein Secret nötig."
        }
    }

    private func clientIdBinding(for provider: CloudProvider) -> Binding<String> {
        switch provider {
        case .teams: return $teamsClientId
        case .meet: return $meetClientId
        case .zoom: return $zoomClientId
        }
    }

    private func scopesBinding(for provider: CloudProvider) -> Binding<String> {
        switch provider {
        case .teams: return $teamsScopes
        case .meet: return $meetScopes
        case .zoom: return $zoomScopes
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
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
    @AppStorage(AppSettings.appLanguage)  private var appLanguage: String = "system"
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
            Section(Loc.t("settings.appLanguage.title")) {
                Picker(Loc.t("settings.appLanguage.picker"), selection: $appLanguage) {
                    ForEach(Loc.selectableLanguages, id: \.code) { lang in
                        Text(Loc.t(lang.labelKey)).tag(lang.code)
                    }
                }
                Text(Loc.t("settings.appLanguage.hint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

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
            SummaryProviderSettingsSection()
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

private struct ActionConnectorsTab: View {
    @AppStorage(AppSettings.actionDefaultRecipient) private var defaultRecipient = ""
    @AppStorage(AppSettings.actionJiraBaseURL) private var jiraBaseURL = ""
    @AppStorage(AppSettings.actionWebhookURL) private var webhookURL = ""
    @AppStorage(AppSettings.actionNeoSkillBridgeEnabled) private var inboxBridgeEnabled = false
    @AppStorage(AppSettings.actionInboxEndpoint) private var inboxEndpoint = ""
    @AppStorage(AppSettings.actionJiraMCPEnabled) private var jiraMCPEnabled = false
    @AppStorage(AppSettings.actionJiraMCPPackage) private var jiraMCPPackage = ""
    @AppStorage(AppSettings.actionJiraMCPCommand) private var jiraMCPCommand = NeonJiraMCPInstaller.defaultCommand
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

            Section("Action-Inbox") {
                Toggle("Aktionen an eine Action-Inbox senden", isOn: $inboxBridgeEnabled)
                if inboxBridgeEnabled {
                    TextField("Action-Inbox-Endpoint", text: $inboxEndpoint, prompt: Text(NeonInboxClient.endpointPlaceholder))
                    if inboxEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Trage einen Endpoint ein, bevor du Action-Inbox-Aktionen nutzt.")
                            .font(.callout)
                            .foregroundStyle(Neon.statusWarning)
                    }
                    Text("POSTet Meeting-Aktionen als JSON an deinen lokalen oder selbst gehosteten Action-Inbox-Endpoint. Ohne Endpoint bleibt die Integration aus und es wird nichts an einen vorgegebenen Neon-Stack gesendet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Jira MCP") {
                Toggle("Jira-MCP-Integration verwenden", isOn: $jiraMCPEnabled)
                if jiraMCPEnabled {
                    TextField(
                        "npm-Paket oder GitHub-Quelle",
                        text: $jiraMCPPackage,
                        prompt: Text("github:company/jira-mcp oder @company/jira-mcp")
                    )
                    TextField("Command", text: $jiraMCPCommand, prompt: Text(NeonJiraMCPInstaller.defaultCommand))
                    if jiraMCPPackageTrimmed.isEmpty {
                        Text("Trage eine Paketquelle ein, bevor NeoQuill den MCP installiert.")
                            .font(.callout)
                            .foregroundStyle(Neon.statusWarning)
                    }

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
                        .disabled(jiraMCPPackageTrimmed.isEmpty || !jiraMCPStatus.canInstall || jiraMCPInstalling)

                        Button("MCP-Config kopieren") {
                            copyJiraMCPConfig()
                        }
                    }

                    Text("Installiert die konfigurierte MCP-Paketquelle global über npm. Für echtes Ticket-Erstellen braucht der Nutzer lokal `jira login`; NeoQuill speichert keine Jira-Secrets.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
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
            return "MCP-Binary: \(jiraMCPStatus.mcpPath ?? normalizedJiraMCPCommand)"
        }
        if jiraMCPPackageTrimmed.isEmpty {
            return "Paketquelle fehlt. Beispiel: ein internes npm-Paket oder ein GitHub-Package deiner Firma."
        }
        if !jiraMCPStatus.canInstall {
            return "npm wurde nicht gefunden. Installiere Node.js/npm, danach kann NeoQuill den MCP einrichten."
        }
        return "Bereit für Installation über npm. Jira CLI: \(jiraMCPStatus.jiraPath ?? "nicht gefunden")"
    }

    private var jiraMCPPackageTrimmed: String {
        jiraMCPPackage.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedJiraMCPCommand: String {
        let trimmed = jiraMCPCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? NeonJiraMCPInstaller.defaultCommand : trimmed
    }

    private func refreshJiraMCPStatus() async {
        jiraMCPRefreshing = true
        jiraMCPStatus = await NeonJiraMCPInstaller.currentStatus(command: normalizedJiraMCPCommand)
        jiraMCPRefreshing = false
    }

    private func installJiraMCP() async {
        jiraMCPInstalling = true
        jiraMCPMessage = "Installation läuft ..."
        do {
            let output = try await NeonJiraMCPInstaller.install(package: jiraMCPPackageTrimmed)
            jiraMCPMessage = output.isEmpty ? "Jira MCP installiert." : output
            jiraMCPStatus = await NeonJiraMCPInstaller.currentStatus(command: normalizedJiraMCPCommand)
        } catch {
            jiraMCPMessage = error.localizedDescription
        }
        jiraMCPInstalling = false
    }

    private func copyJiraMCPConfig() {
        let snippet = NeonJiraMCPInstaller.mcpConfigSnippet(command: jiraMCPStatus.mcpPath ?? normalizedJiraMCPCommand)
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

    @EnvironmentObject private var updater: AppUpdater
    @AppStorage("SUEnableAutomaticChecks") private var autoCheck: Bool = true

    var body: some View {
        Form {
            Section("App") {
                LabeledContent("Version", value: version.displayVersion)
                LabeledContent("Build-Datum", value: version.buildDate)
            }

            Section("Updates") {
                Toggle("Automatisch nach Updates suchen", isOn: $autoCheck)
                LabeledContent("Update-Kanal") {
                    Text("Stable · signierter Sparkle-Appcast")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Jetzt nach Updates suchen") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
                Text("NeoQuill nutzt Sparkle 2 und verifiziert jedes Update über die EdDSA-Signatur in `Info.plist`.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
