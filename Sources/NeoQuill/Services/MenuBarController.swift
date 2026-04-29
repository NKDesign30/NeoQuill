import AppKit
import Combine
import SwiftUI

// NSStatusItem oben rechts neben Apple-Menü — zusätzlich zum Dock-Icon.
// Kompakt: Mic-Icon (rot wenn aktiv), Click öffnet App, Right-Click → Quick-Menu.

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private weak var recorder: RecordingController?
    private var cancellables: Set<AnyCancellable> = []

    func install(with recorder: RecordingController) {
        self.recorder = recorder
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = symbol(.idle)
            button.target = self
            button.action = #selector(onClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        item.menu = buildMenu()

        recorder.$state
            .removeDuplicates()
            .sink { [weak self] state in
                self?.refreshIcon(for: state)
                self?.refreshMenu()
            }
            .store(in: &cancellables)

        recorder.$elapsed
            .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &cancellables)
    }

    // MARK: - UI

    private enum IconState { case idle, recording, processing }

    private func symbol(_ state: IconState) -> NSImage? {
        let name: String
        let tint: NSColor
        switch state {
        case .idle:       name = "mic"; tint = .secondaryLabelColor
        case .recording:  name = "mic.fill"; tint = NSColor.systemRed
        case .processing: name = "waveform"; tint = .secondaryLabelColor
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "NeoQuill")?.withSymbolConfiguration(cfg)
        img?.isTemplate = state != .recording
        if state == .recording, let base = img {
            return tinted(base, color: tint)
        }
        return img
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        rect.fill(using: .sourceIn)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    private func refreshIcon(for state: RecordingState) {
        guard let button = statusItem?.button else { return }
        switch state {
        case .recording:  button.image = symbol(.recording)
        case .processing: button.image = symbol(.processing)
        default:          button.image = symbol(.idle)
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let toggle = NSMenuItem(title: "Aufnahme starten", action: #selector(onToggle(_:)), keyEquivalent: "r")
        toggle.target = self
        toggle.keyEquivalentModifierMask = [.command]
        toggle.tag = 1
        menu.addItem(toggle)

        let elapsed = NSMenuItem(title: "—", action: nil, keyEquivalent: "")
        elapsed.tag = 2
        elapsed.isEnabled = false
        menu.addItem(elapsed)

        menu.addItem(.separator())

        let openApp = NSMenuItem(title: "NeoQuill öffnen", action: #selector(onOpenApp(_:)), keyEquivalent: "")
        openApp.target = self
        menu.addItem(openApp)

        let settings = NSMenuItem(title: "Einstellungen …", action: #selector(onSettings(_:)), keyEquivalent: ",")
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "NeoQuill beenden", action: #selector(onQuit(_:)), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        return menu
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu, let recorder else { return }
        if let toggle = menu.item(withTag: 1) {
            toggle.title = recorder.state.isRecording ? "Aufnahme stoppen" : "Aufnahme starten"
        }
        if let elapsed = menu.item(withTag: 2) {
            switch recorder.state {
            case .recording:
                elapsed.title = "Läuft · " + format(recorder.elapsed)
            case .preparing:
                elapsed.title = "Vorbereiten …"
            case .processing:
                elapsed.title = "Verarbeiten …"
            case .detected(let app):
                elapsed.title = "Erkannt: " + app.rawValue
            case .error(let msg):
                elapsed.title = "Fehler: " + msg.prefix(40)
            case .idle:
                elapsed.title = "Bereit"
            }
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let total = Int(max(0, s))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Actions

    @objc private func onClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem?.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        } else {
            // Linksklick: App nach vorne holen, Toggle nur via Menü.
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    @objc private func onToggle(_ sender: Any?) {
        guard let recorder else { return }
        Task { @MainActor in await recorder.toggle() }
    }

    @objc private func onOpenApp(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }

    @objc private func onSettings(_ sender: Any?) {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func onQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}
