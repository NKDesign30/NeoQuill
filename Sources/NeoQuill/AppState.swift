import SwiftUI
import Combine

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
        dockBadge.bind(to: recorder)
        menuBar.install(with: recorder)
        pill.bind(to: recorder)

        // Whisper- und Diarizer-Modelle im Hintergrund laden damit der erste
        // Recording-Start nahezu sofort funktioniert.
        Task { [weak recorder] in await recorder?.prewarmModels() }
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

    func showEmpty() {
        viewMode = .empty
        selectedMeetingId = nil
    }

    var statusLabel: String { recorder.statusText }
    var isRecording: Bool { recorder.state.isRecording }
}
