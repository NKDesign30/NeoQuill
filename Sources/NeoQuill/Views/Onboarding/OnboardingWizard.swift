import SwiftUI

// First-Run-Wizard. Begleitet Niko durch alle Pflicht-Settings + Permissions
// in 7 Schritten. Sidebar zeigt Fortschritt, Hauptbereich rendert den Step.

struct OnboardingWizard: View {

    @StateObject private var state = OnboardingState()
    @EnvironmentObject private var appState: AppState
    var onFinish: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Divider().background(Neon.strokeHairline)
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(36)
                Divider().background(Neon.strokeHairline)
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 760, height: 560)
        .background(Neon.surfaceBackground)
        .onAppear { state.refreshPermissionStates() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Avatar(initials: "Q", color: Neon.brandPrimary, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NeoQuill")
                        .font(.neonBody(15, weight: .semibold))
                        .foregroundStyle(Neon.textPrimary)
                    Text("Erste Einrichtung")
                        .font(.neonMono(10))
                        .foregroundStyle(Neon.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(OnboardingState.Step.allCases) { step in
                    sidebarRow(step)
                }
            }
            Spacer()
            Text("Alles bleibt lokal — keine Konten, keine Cloud, keine Telemetrie ausser du erlaubst sie explizit.")
                .font(.neonBody(11))
                .foregroundStyle(Neon.textTertiary)
                .lineSpacing(2)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.18))
    }

    private func sidebarRow(_ step: OnboardingState.Step) -> some View {
        let isCurrent = step == state.currentStep
        let isPast = step.rawValue < state.currentStep.rawValue
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Neon.brandPrimary : isPast ? Neon.brandPrimary.opacity(0.3) : Color.white.opacity(0.05))
                    .frame(width: 22, height: 22)
                if isPast {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.neonMono(10, weight: .semibold))
                        .foregroundStyle(isCurrent ? .white : Neon.textTertiary)
                }
            }
            Text(step.title)
                .font(.neonBody(13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Neon.textPrimary : Neon.textTertiary)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch state.currentStep {
        case .welcome:     OnboardingStepWelcome(state: state)
        case .profile:     OnboardingStepProfile(state: state)
        case .microphone:  OnboardingStepMicrophone(state: state)
        case .voiceId:     OnboardingStepVoiceId(state: state, enrollment: appState.voiceIdEnrollment)
        case .permissions: OnboardingStepPermissions(state: state)
        case .cloud:       OnboardingStepCloud(state: state, oauth: appState.cloudOAuth)
        case .ready:       OnboardingStepReady(state: state)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if state.canGoBack {
                Button("Zurueck") { state.goBack() }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if let skip = state.skipLabel {
                Button(skip) { state.advance() }
                    .buttonStyle(.bordered)
            }
            Button(state.nextLabel) {
                if state.currentStep == .ready {
                    state.persistAll()
                    onFinish()
                } else {
                    state.advance()
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!state.canGoNext)
        }
    }
}

// MARK: - Step: Welcome

struct OnboardingStepWelcome: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Willkommen bei NeoQuill")
                .font(.neonDisplay(28))
                .foregroundStyle(Neon.textPrimary)
            Text("Meeting-Recording, das deine Speaker erkennt — auch wenn keiner in Teams oder Zoom auf 'Aufzeichnen' drueckt.")
                .font(.neonBody(15))
                .foregroundStyle(Neon.textSecondary)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(symbol: "waveform", title: "Lokale Transkription",
                           detail: "WhisperKit + Final-STT laufen on-device. Audio verlaesst deinen Mac nicht.")
                FeatureRow(symbol: "person.3.fill", title: "Speaker-Erkennung",
                           detail: "FluidAudio + dein Voice-Onboarding ergeben echte Namen statt S1/S2.")
                FeatureRow(symbol: "calendar", title: "Auto-Detect",
                           detail: "Erkennt Teams/Meet/Zoom-Calls automatisch und startet die Aufnahme.")
                FeatureRow(symbol: "lock.shield", title: "Klarer Permission-Pfad",
                           detail: "Wir holen dich Schritt fuer Schritt durch alle macOS-Freigaben.")
            }

            Spacer()
            Text("Dauert ca. 2 Minuten. Du kannst jeden Schritt spaeter in den Einstellungen aendern.")
                .font(.neonBody(12))
                .foregroundStyle(Neon.textTertiary)
        }
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .foregroundStyle(Neon.brandPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.neonBody(13, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                Text(detail)
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textSecondary)
            }
        }
    }
}

// MARK: - Step: Profile

struct OnboardingStepProfile: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wer bist du?")
                    .font(.neonDisplay(24))
                    .foregroundStyle(Neon.textPrimary)
                Text("Wird fuer deine Mikrofonspur verwendet (interne ID bleibt 'ME').")
                    .font(.neonBody(13))
                    .foregroundStyle(Neon.textSecondary)
            }
            Form {
                TextField("Vor- und Nachname", text: $state.name)
                TextField("Rolle (optional)", text: $state.role, prompt: Text("Eigene Stimme"))
                Picker("Sprache", selection: $state.language) {
                    Text("Deutsch").tag("de")
                    Text("Englisch").tag("en")
                    Text("Auto-Detect").tag("auto")
                }
            }
            .formStyle(.grouped)
            Spacer()
        }
    }
}

// MARK: - Step: Microphone

struct OnboardingStepMicrophone: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welches Mikrofon?")
                    .font(.neonDisplay(24))
                    .foregroundStyle(Neon.textPrimary)
                Text("USB-Mics (PodMic, Yeti, NT-USB) liefern deutlich bessere Diarization als das eingebaute MacBook-Mic.")
                    .font(.neonBody(13))
                    .foregroundStyle(Neon.textSecondary)
                    .lineSpacing(3)
            }

            Form {
                Section("Mikrofon-Berechtigung") {
                    LabeledContent("Status") {
                        Text(state.micStatus.label)
                            .foregroundStyle(state.micStatus.color)
                    }
                    if state.micStatus != .granted {
                        Button("Mikrofon-Zugriff anfragen") {
                            Task { await state.requestMicPermission() }
                        }
                    }
                }
                Section("Eingabegeraet") {
                    Picker("Mic", selection: $state.selectedMicId) {
                        Text("Standard (auto)").tag("")
                        ForEach(state.availableMics, id: \.id) { mic in
                            Text(mic.name).tag(mic.id)
                        }
                    }
                    Button("Mic-Liste neu laden") {
                        state.refreshMicList()
                    }
                }
            }
            .formStyle(.grouped)
            Spacer()
        }
    }
}

// MARK: - Step: Voice-ID

struct OnboardingStepVoiceId: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var enrollment: VoiceIdEnrollmentService
    @State private var didStart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Stimme einrichten")
                    .font(.neonDisplay(24))
                    .foregroundStyle(Neon.textPrimary)
                Text("8 Sekunden Vorlesen — danach erkennt NeoQuill deine Stimme automatisch in jedem Meeting. Du kannst das auch ueberspringen und spaeter in den Einstellungen nachholen.")
                    .font(.neonBody(13))
                    .foregroundStyle(Neon.textSecondary)
                    .lineSpacing(3)
            }

            switch enrollment.phase {
            case .idle, .failed:
                inlineStartCard
            case .requestingPermission, .processing:
                inlineStatusCard(text: "Bitte warten…")
            case .recording(let remaining):
                inlineRecordingCard(remaining: remaining)
            case .saved:
                inlineSuccessCard
            }
            Spacer()
        }
    }

    private var inlineStartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vorlesetext")
                .font(.neonMono(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Neon.textTertiary)
            Text("Hi, ich bin \(state.name.isEmpty ? LocalSpeakerProfile.displayName : state.name). Diese Aufnahme nutzt NeoQuill, um meine Stimme automatisch zu erkennen.")
                .font(.neonBody(15))
                .foregroundStyle(Neon.textPrimary)
                .lineSpacing(4)
            HStack {
                Button("Aufnahme starten") {
                    didStart = true
                    Task { await enrollment.startEnrollment() }
                }
                .buttonStyle(.borderedProminent)
                if case .failed(let message) = enrollment.phase {
                    Text(message)
                        .font(.neonBody(12))
                        .foregroundStyle(Neon.statusError)
                }
            }
        }
        .padding(18)
        .background(card)
    }

    private func inlineRecordingCard(remaining: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Aufnahme laeuft…")
                    .font(.neonBody(15, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                Spacer()
                Text(String(format: "%.1fs", remaining))
                    .font(.neonMono(13, weight: .semibold))
                    .foregroundStyle(Neon.brandPrimary)
            }
            GeometryReader { geo in
                let progress = max(0, min(1, 1 - remaining / VoiceIdEnrollmentService.recordingDuration))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.05))
                    Capsule().fill(Neon.brandPrimary).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 4)
        }
        .padding(18)
        .background(card)
    }

    private func inlineStatusCard(text: String) -> some View {
        Text(text)
            .font(.neonBody(13))
            .foregroundStyle(Neon.textSecondary)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
    }

    private var inlineSuccessCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Neon.brandPrimary)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text("Stimme gespeichert")
                    .font(.neonBody(14, weight: .semibold))
                    .foregroundStyle(Neon.textPrimary)
                Text("Du wirst ab jetzt automatisch als \(state.name.isEmpty ? LocalSpeakerProfile.displayName : state.name) erkannt.")
                    .font(.neonBody(12))
                    .foregroundStyle(Neon.textSecondary)
            }
        }
        .padding(18)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
    }
}

// MARK: - Step: Permissions

struct OnboardingStepPermissions: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Berechtigungen")
                    .font(.neonDisplay(24))
                    .foregroundStyle(Neon.textPrimary)
                Text("macOS fragt einmal pro Permission. Was du hier ueberspringst kannst du jederzeit in den Systemeinstellungen nachholen.")
                    .font(.neonBody(13))
                    .foregroundStyle(Neon.textSecondary)
                    .lineSpacing(3)
            }

            Form {
                permissionRow(
                    title: "Bildschirm- & System-Audio",
                    detail: "Wird beim ersten Teams/Zoom-Tap automatisch angefragt. Pflicht fuer Speaker-Diarization.",
                    status: state.screenCaptureStatus,
                    actionLabel: "Systemeinstellungen oeffnen",
                    action: state.openScreenCaptureSettings
                )
                permissionRow(
                    title: "Accessibility (Live-Captions)",
                    detail: "Liest sichtbare Captions aus Teams/Meet/Zoom. Empfehlung: aktivieren wenn die App-eigenen Captions an sind.",
                    status: state.accessibilityStatus,
                    actionLabel: "Systemeinstellungen oeffnen",
                    action: state.openAccessibilitySettings
                )
                permissionRow(
                    title: "Kalender",
                    detail: "Liest Teilnehmer des aktuellen Termins als Pool fuer unklare Speaker.",
                    status: state.calendarStatus,
                    actionLabel: "Anfragen",
                    action: { Task { await state.requestCalendarPermission() } }
                )
                permissionRow(
                    title: "Notifications",
                    detail: "Schickt einen Hinweis wenn ein Cloud-Transkript im Downloads-Ordner landet.",
                    status: state.notificationStatus,
                    actionLabel: "Anfragen",
                    action: { Task { await state.requestNotificationPermission() } }
                )

                Section("Verhalten") {
                    Toggle("Auto-Detection: Teams · Zoom · Google Meet", isOn: $state.autoDetect)
                    Toggle("Live-Captions lokal lesen", isOn: $state.liveCaptions)
                    Toggle("Transkripte im Downloads-Ordner automatisch erkennen", isOn: $state.watchDownloads)
                    Toggle("Kalender-Teilnehmer als Pool nutzen", isOn: $state.calendarPool)
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        detail: String,
        status: OnboardingState.PermissionStatus,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Section(title) {
            LabeledContent("Status") {
                Text(status.label).foregroundStyle(status.color)
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            if status != .granted {
                Button(actionLabel, action: action)
            }
        }
    }
}

// MARK: - Step: Cloud (optional)

struct OnboardingStepCloud: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var oauth: CloudOAuthService
    @State private var lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cloud-Integrationen (optional)")
                    .font(.neonDisplay(24))
                    .foregroundStyle(Neon.textPrimary)
                Text("Wenn deine Org Cloud-Recordings nutzt, kann NeoQuill das offizielle Transkript automatisch holen. Komplett ueberspringbar — die App funktioniert auch ohne.")
                    .font(.neonBody(13))
                    .foregroundStyle(Neon.textSecondary)
                    .lineSpacing(3)
            }
            Form {
                ForEach(CloudProvider.allCases, id: \.self) { provider in
                    let connected = oauth.connectedProviders.contains(provider)
                    let configured = CloudOAuthCatalog.config(for: provider).isConfigured
                    Section(provider.displayName) {
                        LabeledContent("Status") {
                            Text(connected ? "Verbunden" : configured ? "Nicht verbunden" : "App-Registrierung fehlt")
                                .foregroundStyle(connected ? Neon.brandPrimary : Neon.textTertiary)
                        }
                        if connected {
                            Button("Trennen") { oauth.signOut(provider) }
                                .foregroundStyle(Neon.statusError)
                        } else if configured {
                            Button("Mit \(provider.displayName) anmelden") {
                                Task { await connect(provider) }
                            }
                        } else {
                            Text("Client-ID muss in Info.plist hinterlegt werden — siehe Cloud-Tab in den Einstellungen.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let lastError {
                    Section("Fehler") {
                        Text(lastError)
                            .font(.callout)
                            .foregroundStyle(Neon.statusError)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func connect(_ provider: CloudProvider) async {
        do {
            try await oauth.signIn(provider)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - Step: Ready

struct OnboardingStepReady: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Alles bereit, \(displayedFirstName).")
                .font(.neonDisplay(28))
                .foregroundStyle(Neon.textPrimary)
            Text("NeoQuill startet jetzt. Im Menue-Bar siehst du den Aufnahme-Status, ueber das Plus-Icon startest du manuell.")
                .font(.neonBody(14))
                .foregroundStyle(Neon.textSecondary)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow(symbol: "person.fill",     label: "Profil",        value: displayedName)
                summaryRow(symbol: "mic.fill",        label: "Mikrofon",      value: state.selectedMicId.isEmpty ? "Standard (auto)" : selectedMicName)
                summaryRow(symbol: "waveform",        label: "Voice-ID",      value: VoiceIdEnrollmentService.isEnrolled ? "Eingerichtet" : "Spaeter")
                summaryRow(symbol: "calendar",        label: "Kalender-Pool", value: state.calendarPool ? "An" : "Aus")
                summaryRow(symbol: "captions.bubble", label: "Live-Captions", value: state.liveCaptions ? "An" : "Aus")
                summaryRow(symbol: "bolt.fill",       label: "Auto-Detect",   value: state.autoDetect ? "An" : "Aus")
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                    )
            )

            Spacer()
            Text("Du kannst jeden Punkt jederzeit in den Einstellungen aendern.")
                .font(.neonBody(12))
                .foregroundStyle(Neon.textTertiary)
        }
    }

    private var displayedName: String {
        let trimmed = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Niko" : trimmed
    }

    private var displayedFirstName: String {
        displayedName.split(separator: " ").first.map(String.init) ?? displayedName
    }

    private var selectedMicName: String {
        state.availableMics.first { $0.id == state.selectedMicId }?.name ?? "Eigene Wahl"
    }

    private func summaryRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(Neon.brandPrimary)
            Text(label)
                .font(.neonBody(13, weight: .medium))
                .foregroundStyle(Neon.textPrimary)
            Spacer()
            Text(value)
                .font(.neonMono(11))
                .foregroundStyle(Neon.textSecondary)
        }
    }
}
