import AppKit
import Combine
import SwiftUI

// Systemweites Floating-NSPanel — schwebt am oberen Bildrand, alle Spaces,
// klickbar ohne den aktiven Call zu unterbrechen (`.nonactivatingPanel`).
//
// Drei Anzeige-Modi, gesteuert vom `RecordingController.state`:
// - `.detected(app:)`  → Pille fragt "Aufnehmen?" + ✓ ✗
// - `.recording`       → roter Punkt + Timer + Stop
// - alles andere       → Pille versteckt
//
// Plus: `.processing` zeigt kurz "Wird transkribiert…" als Feedback,
// danach blendet sich die Pille aus.

@MainActor
final class FloatingPillController {

    private var panel: NSPanel?
    private var hosting: NSHostingView<MeetingPill>?
    private var stateCancellable: AnyCancellable?
    private var elapsedCancellable: AnyCancellable?
    private var levelCancellable: AnyCancellable?
    private weak var recorder: RecordingController?

    // Live-State fuer die SwiftUI-View — beobachtet die Pille via Bindings.
    private let pillState = MeetingPillState()

    func bind(to recorder: RecordingController) {
        self.recorder = recorder
        pillState.onAccept  = { [weak recorder] in Task { await recorder?.acceptDetection() } }
        pillState.onDismiss = { [weak recorder] in recorder?.dismissDetection() }
        pillState.onStop    = { [weak recorder] in Task { await recorder?.stop() } }

        stateCancellable = recorder.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.apply(state: state) }

        elapsedCancellable = recorder.$elapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] elapsed in
                self?.pillState.elapsedSeconds = Int(elapsed)
            }

        levelCancellable = recorder.$audioLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.pillState.audioLevel = level
            }
    }

    private func apply(state: RecordingState) {
        switch state {
        case .detected(let app):
            pillState.mode = .detected(app: app)
            show()
        case .recording:
            pillState.mode = .recording
            show()
        case .processing:
            pillState.mode = .processing
            show()
        case .preparing:
            pillState.mode = .preparing
            show()
        case .idle, .error:
            hide()
        }
    }

    private func show() {
        if panel == nil { buildPanel() }
        guard let panel else { return }
        if !panel.isVisible {
            positionAtTopCenter(panel: panel)
            panel.orderFrontRegardless()
        }
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func buildPanel() {
        let pill = MeetingPill(state: pillState)
        let host = NSHostingView(rootView: pill)
        host.translatesAutoresizingMaskIntoConstraints = false

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.hasShadow = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.isMovableByWindowBackground = true
        p.contentView = host
        // Auto-size auf SwiftUI-Inhalt
        host.frame = p.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]

        self.panel = p
        self.hosting = host
    }

    private func positionAtTopCenter(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let panelSize = panel.frame.size
        let x = visible.midX - panelSize.width / 2
        let y = visible.maxY - panelSize.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// MARK: - Pill-State (Bindings fuer SwiftUI-View)

@MainActor
final class MeetingPillState: ObservableObject {
    enum Mode: Equatable {
        case detected(app: CallApp)
        case preparing
        case recording
        case processing
    }

    @Published var mode: Mode = .preparing
    @Published var elapsedSeconds: Int = 0
    @Published var audioLevel: Float = 0

    var onAccept: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onStop: () -> Void = {}
}
