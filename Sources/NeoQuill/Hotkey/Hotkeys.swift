import Foundation
import KeyboardShortcuts

// Globale Shortcuts via sindresorhus/KeyboardShortcuts.
// Default: Option+R für Aufnahme-Toggle.

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self(
        "neoquill.toggle.recording",
        default: .init(.r, modifiers: [.option])
    )
}
