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
    @Published var detailLayout: DetailLayout = .editorial
    @Published var density: SidebarDensity = .regular
    @Published var selectedMeetingId: String? = MockData.activeMeeting.id
    @Published var query: String = ""

    let store = MeetingStore()
    let recorder = RecordingController()
    private var cancellables: Set<AnyCancellable> = []

    @Published private(set) var meetings: [MeetingSummary] = MockData.meetings
    @Published private(set) var activeMeeting: MeetingDetail = MockData.activeMeeting
    @Published private(set) var liveSession: LiveSession = MockData.liveSession

    init() {
        store.$meetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, !$0.isEmpty else { return }
                self.meetings = $0
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
