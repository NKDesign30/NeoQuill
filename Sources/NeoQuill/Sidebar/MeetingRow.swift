import AppKit
import SwiftUI

// Eine Meeting-Zeile in der Sidebar.
// Active: weiß-Tint + bold Title + emerald-MicGlyph (KEINE Left-Border, KEIN green-bg-Glow!).

struct MeetingRow: View {

    @EnvironmentObject private var state: AppState

    let meeting: MeetingSummary
    let active: Bool
    let isRecording: Bool
    let density: SidebarDensity
    var accent: Color = Neon.brandPrimary

    @State private var hovering = false

    private var padY: CGFloat {
        switch density {
        case .compact: return 7
        case .regular: return 9
        case .comfy:   return 11
        }
    }

    private var background: Color {
        if active { return accent.opacity(0.08) }
        if hovering { return Color.white.opacity(0.04) }
        return .clear
    }

    private var titleColor: Color {
        active ? Neon.textPrimary : Neon.textSecondary
    }

    private var meetingDetail: MeetingDetail? {
        state.store.detail(for: meeting.id)
    }

    private var contextMeetingIds: Set<String> {
        state.contextMeetingIds(anchorMeetingId: meeting.id)
    }

    private var contextMeetingCount: Int {
        contextMeetingIds.count
    }

    private var isBatchContext: Bool {
        contextMeetingCount > 1
    }

    private var canRunProcessingAction: Bool {
        !isBatchContext && (meetingDetail.map { !$0.processing } ?? false)
    }

    private var hasWorkspaceAssignmentInContext: Bool {
        state.meetings.contains { item in
            contextMeetingIds.contains(item.id) && item.workspaceId != nil
        }
    }

    var body: some View {
        Button(action: selectFromClick) {
            HStack(spacing: 10) {
                MicGlyph(active: active, recording: isRecording, accent: accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(meeting.title)
                            .font(.neonBody(13, weight: active ? .semibold : .regular))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if meeting.unread {
                            Circle()
                                .fill(accent)
                                .frame(width: 5, height: 5)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(meeting.date), \(meeting.time)")
                            .font(.neonMono(10))
                            .foregroundStyle(Neon.textTertiary)
                        Text("·").foregroundStyle(Neon.textQuaternary).font(.neonMono(10))
                        Text(meeting.duration)
                            .font(.neonMono(10))
                            .foregroundStyle(Neon.textTertiary)
                        Text("·").foregroundStyle(Neon.textQuaternary).font(.neonMono(10))
                        PlatformBadge(platform: meeting.platform)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isRecording {
                    Text("● REC")
                        .font(.neonMono(9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Neon.recordingDotBright)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, padY)
            .background(
                RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                openMeeting()
            } label: {
                Label("Öffnen", systemImage: Glyph.Name.chevRight.rawValue)
            }

            Divider()

            Button {
                reprocessMeeting()
            } label: {
                Label("Final-STT erneut ausführen", systemImage: Glyph.Name.refresh.rawValue)
            }
            .disabled(!canRunProcessingAction)

            Button {
                mergeAudio()
            } label: {
                Label("Audio ergänzen…", systemImage: Glyph.Name.download.rawValue)
            }
            .disabled(!canRunProcessingAction)

            Divider()

            Menu {
                Button {
                    assignWorkspace(nil)
                } label: {
                    Label("Aus Workspace entfernen", systemImage: "tray")
                }
                .disabled(!hasWorkspaceAssignmentInContext)

                if state.workspaces.isEmpty {
                    Button("Keine Workspaces angelegt") {}
                        .disabled(true)
                } else {
                    Divider()
                    ForEach(state.workspaces) { workspace in
                        Button {
                            assignWorkspace(workspace.id)
                        } label: {
                            Label(
                                "\(workspace.kind.label) · \(workspace.name)",
                                systemImage: Glyph.Name.tag.rawValue
                            )
                        }
                        .disabled(allContextMeetingsAreAssigned(to: workspace.id))
                    }
                }
            } label: {
                Label(workspaceMenuTitle, systemImage: Glyph.Name.tag.rawValue)
            }

            Divider()

            Button {
                copyMarkdown()
            } label: {
                Label("Markdown kopieren", systemImage: Glyph.Name.copy.rawValue)
            }
            .disabled(isBatchContext || meetingDetail == nil)

            Button {
                exportMarkdown()
            } label: {
                Label("Auf Desktop exportieren", systemImage: Glyph.Name.export.rawValue)
            }
            .disabled(isBatchContext || meetingDetail == nil)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Neon.Duration.fast), value: hovering)
        .animation(.easeOut(duration: Neon.Duration.fast), value: active)
    }

    private var workspaceMenuTitle: String {
        isBatchContext ? "\(contextMeetingCount) Meetings verschieben" : "In Projekt/Team verschieben"
    }

    private func selectFromClick() {
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) {
            state.extendMeetingSelection(to: meeting.id)
        } else if flags.contains(.command) {
            state.toggleMeetingSelection(meeting.id)
        } else {
            state.select(meeting.id)
        }
    }

    private func openMeeting() {
        state.select(meeting.id)
    }

    private func reprocessMeeting() {
        guard canRunProcessingAction else { return }
        state.reprocessMeeting(meeting.id)
    }

    private func mergeAudio() {
        guard canRunProcessingAction else { return }
        state.mergeAudio(into: meeting.id)
    }

    private func assignWorkspace(_ workspaceId: String?) {
        state.assignWorkspace(meetingIds: contextMeetingIds, workspaceId: workspaceId)
    }

    private func allContextMeetingsAreAssigned(to workspaceId: String) -> Bool {
        let targets = state.meetings.filter { contextMeetingIds.contains($0.id) }
        return !targets.isEmpty && targets.allSatisfy { $0.workspaceId == workspaceId }
    }

    private func copyMarkdown() {
        guard let detail = meetingDetail else { return }
        MeetingExporter.copyToPasteboard(detail)
    }

    private func exportMarkdown() {
        guard let detail = meetingDetail else { return }
        _ = MeetingExporter.exportToDesktop(detail)
    }
}
