import SwiftUI

@main
struct NeoQuillApp: App {

    @StateObject private var state: AppState

    init() {
        FontRegistrar.registerAll()
        AppSettings.registerDefaults()
        _state = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup("NeoQuill") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1080, idealWidth: 1280, minHeight: 700, idealHeight: 820)
                .preferredColorScheme(.dark)
                .background(Neon.windowBackdrop.ignoresSafeArea())
                .sheet(isPresented: $state.showProfileOnboarding) {
                    ProfileOnboardingView { name, role in
                        state.completeProfileOnboarding(name: name, role: role)
                    }
                    .preferredColorScheme(.dark)
                }
                .sheet(item: $state.pendingTranscriptDetection) { event in
                    MatchTranscriptSheet(
                        fileURL: event.fileURL,
                        hint: event.hint,
                        detectedAt: event.detectedAt,
                        candidateMeetingIds: state.candidateMeetingIds(for: event)
                    )
                    .environmentObject(state)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neue Aufnahme") {
                    Task { @MainActor in await state.recorder.toggle() }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Aufnahme starten / stoppen") {
                    Task { @MainActor in await state.recorder.toggle() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Editorial") { state.detailLayout = .editorial }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Split") { state.detailLayout = .split }
                    .keyboardShortcut("2", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        QuillWindow {
            Sidebar()
            ZStack {
                switch state.viewMode {
                case .empty:
                    EmptyView()
                case .detail:
                    if let meeting = state.activeMeeting {
                        switch state.detailLayout {
                        case .editorial: DetailEditorial(meeting: meeting)
                        case .split:     DetailSplit(meeting: meeting)
                        }
                    } else {
                        EmptyView()
                    }
                case .recording:
                    RecordingView(recorder: state.recorder, onStop: state.stopRecording)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// Übergangs-Stub bis Phase C/D Detail- und Recording-Views landen.
private struct PlaceholderDetail: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            Text("AKTIVES MEETING")
                .neonEyebrow(Neon.brandPrimary)
            Text(title)
                .font(.neonDisplay(28))
                .foregroundStyle(Neon.textPrimary)
                .multilineTextAlignment(.center)
            Text("Detail-Editorial / -Split / Recording-View kommen in Phase C+D.")
                .font(.neonBody15)
                .foregroundStyle(Neon.textSecondary)
        }
        .padding(48)
    }
}
