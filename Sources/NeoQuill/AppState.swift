import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// Globaler App-State. ObservableObject bewusst — Swift 5 Mode, kein @Observable.
// Single Source of Truth für selektiertes Meeting, View-Modus, Layout-Variante.

enum ViewMode: String, CaseIterable {
    case empty
    case detail
    case recording
}

enum DetailLayout: String, CaseIterable {
    case editorial
    case split
}

enum SidebarDensity: String, CaseIterable {
    case compact
    case regular
    case comfy
}

@MainActor
final class AppState: ObservableObject {

    @Published var viewMode: ViewMode = .empty
    @Published var detailLayout: DetailLayout = AppState.loadLayout()
    @Published var density: SidebarDensity = AppState.loadDensity()
    @Published var selectedMeetingId: String? = nil
    @Published var query: String = ""
    @Published var showProfileOnboarding: Bool = false
    @Published var pendingTranscriptDetection: TranscriptDetectionEvent?
    @Published var transientNotice: String?
    @Published var showLicenseGate: Bool = false
    @Published var showBetaGracePrompt: Bool = false

    private var transientNoticeTask: Task<Void, Never>?

    func notify(_ message: String, dismissAfter seconds: TimeInterval = 4) {
        transientNotice = message
        transientNoticeTask?.cancel()
        transientNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.transientNotice = nil }
        }
    }

    func dismissNotice() {
        transientNoticeTask?.cancel()
        transientNotice = nil
    }

    struct TranscriptDetectionEvent: Identifiable, Equatable {
        let id = UUID()
        let fileURL: URL
        let hint: TranscriptDownloadWatcher.Hint
        let detectedAt: Date
    }

    private static func loadLayout() -> DetailLayout {
        let raw = UserDefaults.standard.string(forKey: AppSettings.detailLayout) ?? "editorial"
        return DetailLayout(rawValue: raw) ?? .editorial
    }

    private static func loadDensity() -> SidebarDensity {
        let raw = UserDefaults.standard.string(forKey: AppSettings.sidebarDensity) ?? "regular"
        return SidebarDensity(rawValue: raw) ?? .regular
    }

    let store = MeetingStore()
    let speakerStore = SpeakerStore()
    let recorder = RecordingController()
    let dockBadge = DockBadgeService()
    let menuBar = MenuBarController()
    let pill = FloatingPillController()
    let voiceIdEnrollment: VoiceIdEnrollmentService
    let calendar = CalendarParticipantsService()
    let cloudOAuth = CloudOAuthService()
    let cloudReconcile: PlatformReconcileService
    let license: LicenseService
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var meetings: [MeetingSummary] = []
    @Published private(set) var liveSession: LiveSession = MockData.liveSession

    /// Aktives Meeting — nil wenn nichts selektiert oder Store leer.
    /// RootView zeigt dann EmptyView.
    var activeMeeting: MeetingDetail? {
        guard let id = selectedMeetingId else { return nil }
        return store.detail(for: id)
    }

    init() {
        recorder.store = store
        recorder.speakerStore = speakerStore
        voiceIdEnrollment = VoiceIdEnrollmentService(diarizer: recorder.diarizer, speakerStore: speakerStore)
        cloudReconcile = PlatformReconcileService(oauth: cloudOAuth)

        // Lizenz-System: in Phase A (Master-Switch `disabled`) passiv — schreibt
        // nur den FirstLaunchMarker damit Beta-User später erkennbar bleiben.
        let licenseValidator = LicenseValidator(
            client: LemonSqueezyLicenseClient(),
            secretStore: KeychainLicenseSecretStore()
        )
        self.license = LicenseService(
            marker: KeychainFirstLaunchMarker(),
            trial: KeychainTrialTracker(),
            validator: licenseValidator,
            modeProvider: { LicenseEnforcement.currentMode() },
            cutoffProvider: { nil }   // Cutoff wird gesetzt wenn Niko den Switch macht
        )
        Task { [license] in await license.bootstrap() }

        // Lizenz-Gate in den Recorder verdrahten. Recorder ruft das Closure
        // pro PostProcessor-Lauf auf — bei `disabled` immer true (siehe
        // LicenseEnforcement.canUseSummary).
        recorder.licenseAllowsSummary = { [license] in
            LicenseEnforcement.canUseSummary(license.snapshot)
        }
        recorder.licenseAllowsCrossMeetingSpeakerID = { [license] in
            LicenseEnforcement.canCrossMeetingSpeakerID(license.snapshot)
        }

        // Beta-Grace-Prompt einmalig zeigen wenn der User als Beta-User
        // erkannt wurde und das Flag noch nicht gesetzt ist. Reagiert auf
        // jede Snapshot-Änderung — sobald `.betaGrace` im Enforced-Mode
        // erscheint, wird das Sheet aufgepoppt.
        license.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                if BetaGracePrompt.shouldShow(snapshot: snapshot, defaults: .standard) {
                    self.showBetaGracePrompt = true
                }
            }
            .store(in: &cancellables)
        dockBadge.bind(to: recorder)
        menuBar.install(with: recorder)
        pill.bind(to: recorder)

        // Whisper- und Diarizer-Modelle im Hintergrund laden damit der erste
        // Recording-Start nahezu sofort funktioniert. Danach hängengebliebene
        // Transkripte (App während STT beendet/abgestürzt) automatisch nachholen.
        Task { @MainActor [weak recorder] in
            await recorder?.prewarmModels()
            recorder?.recoverOrphanedTranscripts()
        }
        store.$meetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.meetings = list
                if list.isEmpty {
                    self.selectedMeetingId = nil
                    if self.viewMode == .detail { self.viewMode = .empty }
                } else if self.selectedMeetingId == nil
                          || !list.contains(where: { $0.id == self.selectedMeetingId }) {
                    self.selectedMeetingId = list.first?.id
                    if self.viewMode == .empty { self.viewMode = .detail }
                }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        store.$details
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        $detailLayout
            .sink { UserDefaults.standard.set($0.rawValue, forKey: AppSettings.detailLayout) }
            .store(in: &cancellables)
        $density
            .sink { UserDefaults.standard.set($0.rawValue, forKey: AppSettings.sidebarDensity) }
            .store(in: &cancellables)

        // Settings → AppState reaktiv (User schaltet Density in Settings, Sidebar reagiert).
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .throttle(for: .seconds(0.2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                guard let self else { return }
                let newDensity = AppState.loadDensity()
                let newLayout  = AppState.loadLayout()
                if self.density != newDensity { self.density = newDensity }
                if self.detailLayout != newLayout { self.detailLayout = newLayout }
            }
            .store(in: &cancellables)

        // Recorder-State beeinflusst viewMode NICHT mehr — User bleibt
        // in Detail/Empty waehrend des Recordings. Der Aufnahme-Status
        // wird ueber die Floating-Pille (NSPanel) angezeigt, nicht im
        // Hauptfenster.
        showProfileOnboarding = !UserDefaults.standard.boolOr(AppSettings.profileOnboarded, default: false)
        CaptionDebugDumper.installIfEnabled()
        TranscriptDownloadWatcher.installIfEnabled()

        NotificationCenter.default.publisher(for: .transcriptCandidateDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.handleDetection(note)
            }
            .store(in: &cancellables)
    }

    private func handleDetection(_ note: Notification) {
        guard let info = note.userInfo,
              let fileURL = info["fileURL"] as? URL,
              let rawHint = info["hint"] as? String,
              let hint = TranscriptDownloadWatcher.Hint(rawValue: rawHint)
        else { return }
        let detectedAt = info["detectedAt"] as? Date ?? Date()
        pendingTranscriptDetection = TranscriptDetectionEvent(
            fileURL: fileURL,
            hint: hint,
            detectedAt: detectedAt
        )
    }

    func dismissPendingTranscriptDetection() {
        pendingTranscriptDetection = nil
    }

    func candidateMeetingIds(for event: TranscriptDetectionEvent) -> [String] {
        TranscriptDownloadWatcher.candidateMeetingIds(for: event.detectedAt, meetings: meetings)
    }

    // MARK: - Actions

    func select(_ meetingId: String) {
        selectedMeetingId = meetingId
        viewMode = .detail
    }

    func startRecording() {
        Task { await recorder.start() }
    }

    func stopRecording() {
        Task { await recorder.stop() }
    }

    func toggleRecording() {
        Task { await recorder.toggle() }
    }

    func reprocessMeeting(_ meetingId: String) {
        recorder.reprocessMeeting(meetingId)
    }

    /// Öffnet einen Datei-Dialog für eine externe Audiodatei (iPhone-Sprachmemo,
    /// Diktiergerät etc.) und schickt sie durch die Import-Pipeline. Das neue
    /// Meeting erscheint sofort als "Wird transkribiert…" in der Liste und
    /// aktualisiert sich live, sobald Transkript + Summary fertig sind.
    func importAudio() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioImporter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "Importieren"
        panel.message = "Wähle eine Audiodatei (z. B. iPhone-Sprachmemo) zum Transkribieren."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        notify("Importiere „\(url.lastPathComponent)“ …", dismissAfter: 4)
        Task { [weak self] in
            guard let self else { return }
            if let error = await self.recorder.importAudioFile(url: url) {
                self.notify(error, dismissAfter: 8)
            } else {
                self.notify("„\(url.lastPathComponent)“ importiert und transkribiert.", dismissAfter: 5)
            }
        }
    }

    /// Ergänzt ein bestehendes Meeting um eine zweite Audioquelle. Öffnet den
    /// Datei-Dialog und mergt die transkribierten Zeilen ins vorhandene
    /// Transkript — füllt Lücken, die das Original nicht erfasst hat.
    func mergeAudio(into meetingId: String) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = AudioImporter.supportedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = "Einarbeiten"
        panel.message = "Wähle eine Zusatz-Aufnahme, die in dieses Meeting eingearbeitet werden soll."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        notify("Arbeite „\(url.lastPathComponent)“ ein …", dismissAfter: 4)
        Task { [weak self] in
            guard let self else { return }
            if let error = await self.recorder.mergeAudioIntoMeeting(meetingId: meetingId, url: url) {
                self.notify(error, dismissAfter: 8)
            } else {
                self.notify("Zusatz-Audio eingearbeitet.", dismissAfter: 5)
            }
        }
    }

    /// Importiert ein Plattform-Transkript (Teams VTT/Metadata, Meet Entries, Zoom Timeline/VTT)
    /// und triggert ein Reprocess des angegebenen Meetings, das die Plattform-Events in den
    /// Merger durchreicht. Wirft Fehler aus dem Format-Detektor; der eigentliche Re-Merge
    /// laeuft asynchron im RecordingController.
    @discardableResult
    func importPlatformTranscript(meetingId: String, fileURL: URL) throws -> PlatformImportService.Outcome {
        // Lizenz-Gate: Plattform-Imports sind Pro-Feature
        guard LicenseEnforcement.canImportTranscript(license.snapshot) else {
            throw PlatformImportService.ImportError.licenseBlocked
        }
        let fallback = store.detail(for: meetingId)?.platform ?? .meet
        let outcome = try PlatformImportService.detectAndParse(url: fileURL, fallbackPlatform: fallback)
        recorder.applyPlatformImport(meetingId: meetingId, events: outcome.events)
        return outcome
    }

    func completeProfileOnboarding(name: String, role: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRole = role.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            UserDefaults.standard.set(trimmedName, forKey: AppSettings.ownerDisplayName)
        }
        UserDefaults.standard.set(trimmedRole.isEmpty ? "Eigene Stimme" : trimmedRole, forKey: AppSettings.ownerRole)
        UserDefaults.standard.set(true, forKey: AppSettings.profileOnboarded)
        showProfileOnboarding = false
    }

    /// Wird vom OnboardingWizard aufgerufen — der State persistiert dort
    /// bereits selbst, wir muessen nur das Sheet schliessen + freundlich
    /// in den Default-View-Mode wechseln.
    func completeOnboardingFromWizard() {
        showProfileOnboarding = false
        // viewMode bleibt unverändert (EmptyView), das Recording startet der
        // User selbst — wir schließen hier nur das Onboarding-Sheet.
        notify("Setup abgeschlossen — bereit für dein erstes Meeting.", dismissAfter: 6)
    }

    func showEmpty() {
        viewMode = .empty
        selectedMeetingId = nil
    }

    var statusLabel: String { recorder.statusText }
    var isRecording: Bool { recorder.state.isRecording }
}
