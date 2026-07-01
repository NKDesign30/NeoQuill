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
                .environmentObject(updater)
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
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen …") {
                    state.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesMenuButton(updater: updater)
            }
        }
    }
}

struct RootView: View {

    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            QuillWindow {
                Sidebar()
                VStack(spacing: 0) {
                    LicenseTrialBanner(license: state.license) {
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
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .allowsHitTesting(!state.isSettingsPresented)

            if state.isSettingsPresented {
                settingsOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: state.isSettingsPresented)
    }

    /// Beobachtet den LicenseService direkt — RootView hält keine
    /// handgespiegelte Snapshot-Kopie mehr (vorher: @State + for-await-Loop,
    /// ein zweiter Read-Pfad neben den direkten `license.snapshot`-Lesern).
    private struct LicenseTrialBanner: View {
        @ObservedObject var license: LicenseService
        let onTap: () -> Void

        var body: some View {
            TrialBannerView(snapshot: license.snapshot, onTap: onTap)
        }
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture {
                    state.closeSettings()
                }

            SettingsView(selection: $state.settingsSelection, onClose: {
                state.closeSettings()
            })
            .environmentObject(state)
            .padding(34)
        }
    }
}
