import SwiftUI

@main
struct NeoQuillApp: App {

    @StateObject private var state: AppState
    @StateObject private var updater = AppUpdater()
    @AppStorage(AppSettings.appLanguage) private var appLanguage = "system"

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
                .environment(\.locale, Loc.locale)
                .id(appLanguage)
                .sheet(isPresented: $state.showProfileOnboarding) {
                    OnboardingWizard(onFinish: {
                        state.completeOnboardingFromWizard()
                    })
                    .environmentObject(state)
                    .preferredColorScheme(.dark)
                    .interactiveDismissDisabled()
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
                .sheet(isPresented: $state.showLicenseGate) {
                    LicenseGateSheet()
                        .environmentObject(state)
                        .preferredColorScheme(.dark)
                }
                .sheet(isPresented: $state.showBetaGracePrompt, onDismiss: {
                    BetaGracePrompt.markAsShown(defaults: .standard)
                }) {
                    BetaGracePromptView()
                        .preferredColorScheme(.dark)
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

                Button("Audio importieren…") {
                    state.importAudio()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Editorial") { state.detailLayout = .editorial }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Split") { state.detailLayout = .split }
                    .keyboardShortcut("2", modifiers: [.command, .option])
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuButton(updater: updater)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(updater)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {

    @EnvironmentObject private var state: AppState
    @State private var snapshot: LicenseSnapshot = LicenseSnapshot(
        status: .notRequired, mode: .disabled,
        firstLaunchDate: nil, cutoffDate: nil, activation: nil
    )

    var body: some View {
        QuillWindow {
            Sidebar()
            VStack(spacing: 0) {
                TrialBannerView(snapshot: snapshot) {
                    state.showLicenseGate = true
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
        .task {
            // Initial sync + dann auf License-Service-Änderungen reagieren.
            snapshot = state.license.snapshot
            for await s in state.license.$snapshot.values {
                snapshot = s
            }
        }
    }
}
