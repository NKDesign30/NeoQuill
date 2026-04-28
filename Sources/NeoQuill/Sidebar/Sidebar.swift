import SwiftUI

// 280px Aside: Wordmark + StatusPill, SearchField, gruppierte Meeting-Liste, Footer.

struct Sidebar: View {

    @EnvironmentObject private var state: AppState

    private var grouped: [(String, [MeetingSummary])] {
        let filtered: [MeetingSummary]
        if state.query.isEmpty {
            filtered = state.meetings
        } else {
            let q = state.query.lowercased()
            filtered = state.meetings.filter {
                $0.title.lowercased().contains(q)
                    || $0.date.lowercased().contains(q)
                    || $0.platform.rawValue.lowercased().contains(q)
            }
        }
        var dict: [String: [MeetingSummary]] = [:]
        var order: [String] = []
        for m in filtered {
            if dict[m.group] == nil { order.append(m.group); dict[m.group] = [] }
            dict[m.group]?.append(m)
        }
        return order.map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
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
                                    active: m.id == state.selectedMeetingId,
                                    isRecording: state.isRecording && m.id == state.selectedMeetingId,
                                    density: state.density,
                                    onTap: { state.select(m.id) }
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
            Text("\(state.meetings.count) Meetings")
                .font(.neonMono(10))
                .tracking(0.4)
                .foregroundStyle(Neon.textTertiary)
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
}
