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

    @Published var viewMode: ViewMode = .detail
    @Published var detailLayout: DetailLayout = AppState.loadLayout()
    @Published var density: SidebarDensity = AppState.loadDensity()
    @Published var selectedMeetingId: String? = MockData.activeMeeting.id
    @Published var query: String = ""

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
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var meetings: [MeetingSummary] = MockData.meetings
    @Published private(set) var liveSession: LiveSession = MockData.liveSession

    var activeMeeting: MeetingDetail {
        if let id = selectedMeetingId, let detail = store.detail(for: id) {
            return detail
        }
        return MockData.activeMeeting
    }

    init() {
        recorder.store = store
        recorder.speakerStore = speakerStore
        store.$meetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, !$0.isEmpty else { return }
                self.meetings = $0
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

        // Recorder-State spiegelt sich in viewMode: recording → RecordingView, sonst Detail.
        recorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isRecording {
                    self.viewMode = .recording
                } else if case .processing = state {
                    self.viewMode = .recording
                } else if case .recording = state {
                    self.viewMode = .recording
                } else if self.viewMode == .recording {
                    self.viewMode = .detail
                }
            }
            .store(in: &cancellables)
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

    func showEmpty() {
        viewMode = .empty
        selectedMeetingId = nil
    }

    var statusLabel: String { recorder.statusText }
    var isRecording: Bool { recorder.state.isRecording }
}
