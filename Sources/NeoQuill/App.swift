import SwiftUI
import KeyboardShortcuts

@main
struct NeoQuillApp: App {

    @StateObject private var state = AppState()

    init() {
        FontRegistrar.registerAll()
    }

    var body: some Scene {
        WindowGroup("NeoQuill") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1080, idealWidth: 1280, minHeight: 700, idealHeight: 820)
                .preferredColorScheme(.dark)
                .background(Neon.windowBackdrop.ignoresSafeArea())
                .onAppear {
                    KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak state] in
                        Task { @MainActor in await state?.recorder.toggle() }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
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
                    switch state.detailLayout {
                    case .editorial: DetailEditorial(meeting: state.activeMeeting)
                    case .split:     DetailSplit(meeting: state.activeMeeting)
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
