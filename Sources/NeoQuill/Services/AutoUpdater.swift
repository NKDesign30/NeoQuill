import Combine
import SwiftUI
import Sparkle

/// Sparkle 2 integration for NeoQuill's Direct-Sale updater.
///
/// The updater is configured via `Info.plist`:
/// - `SUFeedURL` points at the EdDSA-signed `appcast.xml` on `main` of the
///   public `NKDesign30/NeoQuill` repo — the repo must stay public, otherwise
///   every installed app loses update checks (the URL is baked into the bundle).
/// - `SUPublicEDKey` is the EdDSA public key matching the private key in the
///   macOS Keychain and 1Password (Automation Vault).
/// - `SUEnableAutomaticChecks` enables Sparkle's first-launch prompt asking the
///   user whether to check for updates automatically.
///
/// `AppUpdater` is created once at app launch and owns the
/// `SPUStandardUpdaterController`. `CheckForUpdatesMenuButton` is the menu item
/// wired into `CommandGroup(after: .appInfo)`.
@MainActor
final class AppUpdater: ObservableObject {

    let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Bound to a `Toggle` in Settings.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

/// Menu item view that disables itself while Sparkle is busy.
struct CheckForUpdatesMenuButton: View {

    @ObservedObject var updater: AppUpdater

    var body: some View {
        Button("Nach Updates suchen…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
