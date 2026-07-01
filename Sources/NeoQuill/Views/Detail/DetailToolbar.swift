import SwiftUI
import AppKit

// Detail-Toolbar oben über dem Content: links Meeting-Kontext,
// rechts kompakte Quick-Actions + More.

struct DetailToolbar: View {
    @EnvironmentObject private var state: AppState

    let title: String
    var meeting: MeetingDetail? = nil
    var showLayoutSwitch: Bool = true

    @State private var showImportSheet = false
    @State private var importError: String?

    private var workspaceName: String? {
        guard let workspaceId = meeting?.workspaceId else { return nil }
        return state.workspaces.first { $0.id == workspaceId }?.name
    }

    private var metadataItems: [String] {
        guard let meeting else { return [] }
        return [
            meeting.dateLong,
            meeting.timeRange,
            meeting.duration
        ].filter { !$0.isEmpty }
    }

    var body: some View {
        HStack(spacing: 14) {
            titleBlock

            Spacer(minLength: 12)

            actionCluster
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Neon.surfaceBackground.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
        .sheet(isPresented: $showImportSheet) {
            if let m = meeting {
                ImportTranscriptSheet(meetingId: m.id, meetingTitle: m.title) { result in
                    switch result {
                    case .success:
                        importError = nil
                    case .failure(let error):
                        importError = error.localizedDescription
                    }
                    showImportSheet = false
                }
            }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.neonBody(13, weight: .semibold))
                .foregroundStyle(Neon.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            if meeting != nil {
                HStack(spacing: 7) {
                    ForEach(metadataItems, id: \.self) { item in
                        ToolbarMetaText(item)
                    }

                    if let workspaceName {
                        WorkspaceBadge(name: workspaceName)
                    }
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
        .layoutPriority(1)
    }

    private var actionCluster: some View {
        HStack(spacing: 6) {
            if showLayoutSwitch {
                LayoutSwitcher(layout: $state.detailLayout, accent: Neon.brandPrimary)
                ToolbarDivider()
            }

            ToolbarButton(icon: .refresh, active: meeting?.processing == true) { reprocessAction() }
                .help("Final-STT erneut ausführen")
                .disabled(meeting == nil || meeting?.processing == true)

            ToolbarButton(icon: .copy) { copyAction() }
                .help("Markdown kopieren")
                .disabled(meeting == nil)

            Menu {
                Button("Final-STT erneut ausführen") { reprocessAction() }
                    .disabled(meeting == nil || meeting?.processing == true)
                Button("Transkript importieren") { importAction() }
                    .disabled(meeting == nil)
                Button("Audio ergänzen…") { mergeAudioAction() }
                    .disabled(meeting == nil || meeting?.processing == true)

                Divider()

                Menu("Workspace") {
                    Button("Kein Workspace") {
                        assignWorkspace(nil)
                    }
                    .disabled(meeting == nil || meeting?.workspaceId == nil)
                    if !state.workspaces.isEmpty {
                        Divider()
                        ForEach(state.workspaces) { workspace in
                            Button(workspace.name) {
                                assignWorkspace(workspace.id)
                            }
                            .disabled(meeting == nil || meeting?.workspaceId == workspace.id)
                        }
                    }
                }
                .disabled(meeting == nil)

                Divider()

                Button("Markdown kopieren") { copyAction() }
                    .disabled(meeting == nil)
                Button("Auf Desktop exportieren") { exportAction() }
                    .disabled(meeting == nil)
                Button("Teilen") { shareAction() }
                    .disabled(meeting == nil)

                Divider()

                Menu("An KI übergeben") {
                    aiHandoffSubmenu(.neo)
                    aiHandoffSubmenu(.chaty)
                    aiHandoffSubmenu(.generic)
                }
                .disabled(meeting == nil)
            } label: {
                ToolbarMenuLabel(icon: .more)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func copyAction() {
        guard let m = meeting else { return }
        MeetingExporter.copyToPasteboard(m)
    }

    @ViewBuilder
    private func aiHandoffSubmenu(_ target: MeetingExporter.AITarget) -> some View {
        Menu(target.label) {
            Button("Referenz-Prompt") { handoffAction(target, .reference) }
                .disabled(meeting == nil)
            Button("Voll-Prompt (mit Transkript)") { handoffAction(target, .full) }
                .disabled(meeting == nil)
        }
    }

    private func handoffAction(_ target: MeetingExporter.AITarget, _ mode: MeetingExporter.HandoffMode) {
        guard let m = meeting else { return }
        MeetingExporter.copyHandoffToPasteboard(m, target: target, mode: mode, workspace: workspaceName)
    }

    private func reprocessAction() {
        guard let m = meeting, !m.processing else { return }
        state.reprocessMeeting(m.id)
    }

    private func importAction() {
        guard meeting != nil else { return }
        showImportSheet = true
    }

    private func mergeAudioAction() {
        guard let m = meeting, !m.processing else { return }
        state.mergeAudio(into: m.id)
    }

    private func assignWorkspace(_ workspaceId: String?) {
        guard let m = meeting else { return }
        state.assignWorkspace(meetingId: m.id, workspaceId: workspaceId)
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

private struct ToolbarMetaText: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.neonBody(11, weight: .medium))
            .foregroundStyle(Neon.textTertiary)
    }
}

private struct WorkspaceBadge: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            GlyphView(name: .tag, size: 10, color: Neon.brandPrimary)
            Text(name)
                .font(.neonMono(10, weight: .medium))
                .foregroundStyle(Neon.brandBright)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(Neon.brandFaint)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Neon.brandMuted, lineWidth: Neon.hairlineWidth)
        )
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Neon.strokeHairline)
            .frame(width: Neon.hairlineWidth, height: 18)
            .padding(.horizontal, 3)
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

private struct ToolbarMenuLabel: View {
    let icon: Glyph.Name

    @State private var hovering = false

    var body: some View {
        GlyphView(name: icon, size: 14, color: Neon.textSecondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.06) : .clear)
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: Neon.Duration.fast), value: hovering)
    }
}
