import SwiftUI

// Container für Sidebar + Detail. Window-Chrome (Traffic Lights, Window-Drag-Region)
// macht macOS — wir zeichnen das nicht selbst. Die Title-Bar bleibt versteckt
// (`windowStyle(.hiddenTitleBar)` in App.swift), Traffic Lights ranken oben links.

struct QuillWindow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Neon.surfaceBackground.ignoresSafeArea())
    }
}
