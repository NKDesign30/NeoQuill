import SwiftUI

// 280px Aside: Wordmark + StatusPill, SearchField, gruppierte Meeting-Liste, Footer.

struct Sidebar: View {

    @EnvironmentObject private var state: AppState
    private let appVersion = AppVersionInfo.current()

    private var grouped: [(String, [MeetingSummary])] {
        let filtered: [MeetingSummary]
        if state.query.isEmpty {
            filtered = state.visibleMeetings
        } else {
            let q = state.query.lowercased()
            filtered = state.visibleMeetings.filter {
                $0.title.lowercased().contains(q)
                    || $0.date.lowercased().contains(q)
                    || $0.platform.rawValue.lowercased().contains(q)
            }
        }
        var dict: [String: [MeetingSummary]] = [:]
        for m in filtered {
            dict[m.group, default: []].append(m)
        }
        // Festgelegte Reihenfolge: aktuelles oben, älteres unten.
        let preferred = ["Heute", "Diese Woche", "Diesen Monat", "Früher"]
        var ordered: [(String, [MeetingSummary])] = preferred.compactMap { key in
            guard let group = dict[key], !group.isEmpty else { return nil }
            return (key, group)
        }
        // Unbekannte Gruppen hängen unten an, alphabetisch.
        let known = Set(preferred)
        for key in dict.keys.sorted() where !known.contains(key) {
            ordered.append((key, dict[key] ?? []))
        }
        return ordered
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            workspacePicker
            search
            list
            footer
        }
        .frame(width: 280)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Neon.strokeHairline)
                .frame(width: Neon.hairlineWidth)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Wordmark(size: 22)
            Spacer(minLength: 4)
            StatusPill(recording: state.isRecording, label: state.statusLabel)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var search: some View {
        SearchField(text: $state.query)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
    }

    private var workspacePicker: some View {
        WorkspacePicker()
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1, pinnedViews: [.sectionHeaders]) {
                if grouped.isEmpty {
                    Text("Keine Treffer.")
                        .font(.neonBodySm)
                        .foregroundStyle(Neon.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                ForEach(grouped, id: \.0) { (label, items) in
                    Section {
                        VStack(spacing: 1) {
                            ForEach(items) { m in
                                MeetingRow(
                                    meeting: m,
                                    active: state.selectedMeetingIds.contains(m.id),
                                    isRecording: state.isRecording && m.id == state.selectedMeetingId,
                                    density: state.density
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    } header: {
                        GroupHeader(label: label)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerCount)
                .font(.neonMono(10))
                .tracking(0.4)
                .foregroundStyle(Neon.textTertiary)
            Text(appVersion.displayVersion)
                .font(.neonMono(10))
                .tracking(0.4)
                .foregroundStyle(Neon.textTertiary.opacity(0.8))
                .lineLimit(1)
                .help(appVersion.displayGit)
            Spacer()
            NewRecordingButton(recording: state.isRecording) {
                state.isRecording ? state.stopRecording() : state.startRecording()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .top) {
            Rectangle().fill(Neon.strokeHairline).frame(height: Neon.hairlineWidth)
        }
    }

    private var footerCount: String {
        if state.workspaceSelection == .all {
            return "\(state.meetings.count) Meetings"
        }
        return "\(state.visibleMeetings.count) / \(state.meetings.count) Meetings"
    }
}
