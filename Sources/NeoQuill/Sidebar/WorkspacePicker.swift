import SwiftUI

struct WorkspacePicker: View {
    @EnvironmentObject private var state: AppState
    @State private var showingCreateSheet = false

    private var title: String {
        switch state.workspaceSelection {
        case .all:
            return "Alle Meetings"
        case .unassigned:
            return "Kein Workspace"
        case .workspace:
            return state.activeWorkspace?.name ?? "Workspace"
        }
    }

    private var subtitle: String {
        switch state.workspaceSelection {
        case .all:
            return "\(state.meetings.count) gesamt"
        case .unassigned:
            return "\(state.visibleMeetings.count) ohne Workspace"
        case .workspace:
            guard let workspace = state.activeWorkspace else { return "Projekt" }
            return "\(workspace.kind.label) · \(state.visibleMeetings.count) Meetings"
        }
    }

    var body: some View {
        Menu {
            Button {
                state.selectWorkspace(.all)
            } label: {
                Label("Alle Meetings", systemImage: "tray.full")
            }
            Button {
                state.selectWorkspace(.unassigned)
            } label: {
                Label("Kein Workspace", systemImage: "tray")
            }
            if !state.workspaces.isEmpty {
                Divider()
                ForEach(state.workspaces) { workspace in
                    Button {
                        state.selectWorkspace(.workspace(workspace.id))
                    } label: {
                        Label(workspace.name, systemImage: iconName(for: workspace.kind))
                    }
                }
            }
            Divider()
            Button {
                showingCreateSheet = true
            } label: {
                Label("Workspace anlegen…", systemImage: Glyph.Name.plus.rawValue)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Neon.brandPrimary.opacity(0.18))
                    .frame(width: 24, height: 24)
                    .overlay(GlyphView(name: .tag, size: 11, weight: .semibold, color: Neon.brandBright))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.neonBody(13).weight(.semibold))
                        .foregroundStyle(Neon.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.neonMono(10))
                        .foregroundStyle(Neon.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                GlyphView(name: .chevDown, size: 10, color: Neon.textTertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                    .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingCreateSheet) {
            NewWorkspaceSheet()
                .environmentObject(state)
        }
    }

    private func iconName(for kind: WorkspaceKind) -> String {
        switch kind {
        case .project:
            return Glyph.Name.tag.rawValue
        case .team:
            return Glyph.Name.people.rawValue
        case .organization:
            return "building.2"
        }
    }
}

private struct NewWorkspaceSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: WorkspaceKind = .project
    @State private var context = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Neuer Workspace")
                    .font(.neonDisplayCard22)
                    .foregroundStyle(Neon.textPrimary)
                Text("Für Kunden, Projekte, Teams oder Organisationen.")
                    .font(.neonBodySm)
                    .foregroundStyle(Neon.textTertiary)
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                Picker("Art", selection: $kind) {
                    ForEach(WorkspaceKind.allCases, id: \.self) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Text("Kontext")
                    .font(.neonMono(10))
                    .foregroundStyle(Neon.textTertiary)
                TextEditor(text: $context)
                    .font(.neonBody(13))
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                            .fill(Neon.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Neon.Radius.md, style: .continuous)
                            .stroke(Neon.strokeHairline, lineWidth: Neon.hairlineWidth)
                    )
            }

            HStack {
                Spacer()
                Button("Abbrechen") {
                    dismiss()
                }
                Button("Anlegen") {
                    if state.createWorkspace(name: name, kind: kind, context: context) != nil {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Neon.surfaceBackground)
    }
}
