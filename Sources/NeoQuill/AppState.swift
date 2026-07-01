import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

// Globaler App-State. ObservableObject bewusst — Swift 5 Mode, kein @Observable.
// Single Source of Truth für selektiertes Meeting, View-Modus, Layout-Variante.

enum ViewMode: String, CaseIterable {
    case empty
    case detail
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

    /// Selection-State-Machine als Value-Type — die Anchor-/Range-/Filter-
    /// Reduktion lebt (getestet) in `MeetingSelection`, AppState published nur.
    @Published private(set) var selection = MeetingSelection()
    @Published var detailLayout: DetailLayout = AppState.loadLayout()
    @Published var density: SidebarDensity = AppState.loadDensity()
    @Published var query: String = ""

    var viewMode: ViewMode { selection.viewMode }
    var selectedMeetingId: String? { selection.primaryId }
    var selectedMeetingIds: Set<String> { selection.ids }
    @Published var workspaceSelection: WorkspaceSelection = .all {
        didSet { syncSelectedMeetingForCurrentFilter() }
    }
    @Published var showProfileOnboarding: Bool = false
    @Published var pendingTranscriptDetection: TranscriptDetectionEvent?
    @Published var transientNotice: String?
    @Published var showLicenseGate: Bool = false
    @Published var showBetaGracePrompt: Bool = false
    @Published var isSettingsPresented: Bool = false
    @Published var settingsSelection: QuillSettingsSection = .audio

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
        DetailLayout(rawValue: UserDefaults.standard.value(for: AppSettings.detailLayout)) ?? .editorial
    }

    private static func loadDensity() -> SidebarDensity {
        SidebarDensity(rawValue: UserDefaults.standard.value(for: AppSettings.sidebarDensity)) ?? .regular
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
    @Published private(set) var workspaces: [MeetingWorkspace] = []

    var visibleMeetings: [MeetingSummary] {
        meetings.filter { workspaceSelection.includes($0) }
    }

    /// Aktives Meeting — nil wenn nichts selektiert oder Store leer.
    /// RootView zeigt dann EmptyView.
    var activeMeeting: MeetingDetail? {
        guard let id = selectedMeetingId else { return nil }
        return store.detail(for: id)
    }

    var activeWorkspace: MeetingWorkspace? {
        guard case .workspace(let id) = workspaceSelection else { return nil }
        return workspaces.first { $0.id == id }
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
            cutoffProvider: { nil }   // Cutoff wird erst beim Lizenz-Switch gesetzt.
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

        // Final-STT Runtime prüfen und optionale Modelle vorwärmen. Danach
        // hängengebliebene Transkripte (App während STT beendet/abgestürzt)
        // automatisch nachholen.
        Task { @MainActor [weak recorder] in
            await recorder?.prewarmModels()
            recorder?.recoverOrphanedTranscripts()
        }
        store.$meetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.meetings = list
                self.syncSelectedMeetingForCurrentFilter()
            }
            .store(in: &cancellables)

        store.$workspaces
            .receive(on: DispatchQueue.main)
            .sink { [weak self] list in
                guard let self else { return }
                self.workspaces = list
                if case .workspace(let id) = self.workspaceSelection,
                   !list.contains(where: { $0.id == id }) {
                    self.workspaceSelection = .all
                } else {
                    self.syncSelectedMeetingForCurrentFilter()
                }
            }
            .store(in: &cancellables)

        store.$details
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        $detailLayout
            .sink { UserDefaults.standard.set($0.rawValue, forKey: AppSettings.detailLayout.key) }
            .store(in: &cancellables)
        $density
            .sink { UserDefaults.standard.set($0.rawValue, forKey: AppSettings.sidebarDensity.key) }
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
        showProfileOnboarding = !UserDefaults.standard.value(for: AppSettings.profileOnboarded)
        CaptionDebugDumper.installIfEnabled()
        TranscriptDownloadWatcher.installIfEnabled()

        NotificationCenter.default.publisher(for: .transcriptCandidateDetected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                self?.handleDetection(note)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .openSettingsOverlay)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let section = (note.userInfo?["section"] as? String)
                    .flatMap(QuillSettingsSection.init(rawValue:)) ?? .audio
                self?.openSettings(section)
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
        selection.select(meetingId)
    }

    private func syncSelectedMeetingForCurrentFilter() {
        selection.sync(visible: visibleMeetings.map(\.id))
    }

    func toggleMeetingSelection(_ meetingId: String) {
        selection.toggle(meetingId, visible: visibleMeetings.map(\.id))
    }

    func extendMeetingSelection(to meetingId: String) {
        selection.extend(to: meetingId, visible: visibleMeetings.map(\.id))
    }

    func contextMeetingIds(anchorMeetingId: String) -> Set<String> {
        selection.contextIds(anchor: anchorMeetingId)
    }

    func selectWorkspace(_ selection: WorkspaceSelection) {
        workspaceSelection = selection
        recorder.activeWorkspaceId = selection.recordingWorkspaceId
    }

    @discardableResult
    func createWorkspace(name: String, kind: WorkspaceKind, context: String) -> MeetingWorkspace? {
        guard let workspace = store.createWorkspace(name: name, kind: kind, context: context) else {
            return nil
        }
        selectWorkspace(.workspace(workspace.id))
        return workspace
    }

    func assignWorkspace(meetingId: String, workspaceId: String?) {
        store.assignWorkspace(meetingId: meetingId, workspaceId: workspaceId)
        syncSelectedMeetingForCurrentFilter()
    }

    func assignWorkspace(meetingIds: Set<String>, workspaceId: String?) {
        store.assignWorkspace(meetingIds: meetingIds, workspaceId: workspaceId)
        syncSelectedMeetingForCurrentFilter()
    }

    func startRecording() {
        recorder.activeWorkspaceId = workspaceSelection.recordingWorkspaceId
        Task { await recorder.start() }
    }

    func stopRecording() {
        Task { await recorder.stop() }
    }

    func toggleRecording() {
        Task { await recorder.toggle() }
    }

    func prepareFirstRunAssets() async -> RuntimePreparationStatus {
        await recorder.prewarmModels()
    }

    func openSettings(_ section: QuillSettingsSection = .audio) {
        settingsSelection = section
        isSettingsPresented = true
    }

    func closeSettings() {
        isSettingsPresented = false
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
            self.recorder.activeWorkspaceId = self.workspaceSelection.recordingWorkspaceId
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
        selection.showEmpty()
    }

    var statusLabel: String { recorder.statusText }
    var isRecording: Bool { recorder.state.isRecording }
}

extension Notification.Name {
    static let openSettingsOverlay = Notification.Name("com.neon.quill.openSettingsOverlay")
}
