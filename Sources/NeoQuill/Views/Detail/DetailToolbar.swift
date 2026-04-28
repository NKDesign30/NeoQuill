import SwiftUI
import AppKit

// 44h Toolbar oben über dem Detail-Content. Links Title, mittig Layout-Switch,
// rechts Copy/Export/Share + More.

struct DetailToolbar: View {
    let title: String
    var meeting: MeetingDetail? = nil
    var showLayoutSwitch: Bool = true

    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.neonBody(12, weight: .medium))
                .foregroundStyle(Neon.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: 8)

            if showLayoutSwitch {
                LayoutSwitcher(layout: $state.detailLayout, accent: Neon.brandPrimary)
                Rectangle().fill(Neon.strokeHairline).frame(width: 1, height: 18).padding(.horizontal, 4)
            }

            ToolbarButton(icon: .copy,   label: "Kopieren") { copyAction() }
            ToolbarButton(icon: .export, label: "Export")   { exportAction() }
            ToolbarButton(icon: .share,  label: "Teilen")   { shareAction() }

            Rectangle()
                .fill(Neon.strokeHairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 4)

            ToolbarButton(icon: .more) { /* TODO: Context-Menu (Phase 7) */ }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
    }

    private func copyAction() {
        guard let m = meeting else { return }
        MeetingExporter.copyToPasteboard(m)
    }

    private func exportAction() {
        guard let m = meeting else { return }
        _ = MeetingExporter.exportToDesktop(m)
    }

    private func shareAction() {
        guard let m = meeting,
              let window = NSApp.keyWindow,
              let view = window.contentView
        else { return }
        MeetingExporter.share(m, from: view)
    }
}

private struct LayoutSwitcher: View {
    @Binding var layout: DetailLayout
    let accent: Color

    var body: some View {
        HStack(spacing: 0) {
            choice(.editorial, sf: "rectangle.portrait")
            choice(.split,     sf: "rectangle.split.2x1")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func choice(_ value: DetailLayout, sf: String) -> some View {
        Button {
            layout = value
        } label: {
            Image(systemName: sf)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(layout == value ? accent : Neon.textTertiary)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(layout == value ? Color.white.opacity(0.06) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
