import AppKit
import Combine

// Schreibt während einer Aufnahme den Dock-Badge ("●" oder "MM:SS").
// Reine Read-Only-Anbindung an RecordingController.

@MainActor
final class DockBadgeService {

    private var cancellables: Set<AnyCancellable> = []

    init() {}

    func bind(to controller: RecordingController) {
        controller.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.updateForState(state, elapsed: controller.elapsed)
            }
            .store(in: &cancellables)

        controller.$elapsed
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] elapsed in
                self?.updateForState(controller.state, elapsed: elapsed)
            }
            .store(in: &cancellables)
    }

    private func updateForState(_ state: RecordingState, elapsed: TimeInterval) {
        let tile = NSApp.dockTile
        switch state {
        case .recording:
            tile.badgeLabel = formatBadge(elapsed: elapsed)
        case .preparing:
            tile.badgeLabel = "…"
        case .processing:
            tile.badgeLabel = "✓"
        case .detected, .idle, .error:
            tile.badgeLabel = nil
        }
        tile.display()
    }

    private func formatBadge(elapsed: TimeInterval) -> String {
        DurationFormat.short(elapsed)
    }
}
