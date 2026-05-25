import SwiftUI

/// Einmalig gezeigtes Sheet beim ersten App-Launch nachdem der Master-Switch
/// auf `.enforced` geflippt wurde und der User als Beta-User erkannt wurde.
///
/// Persistiert ein Flag in UserDefaults damit das Sheet nicht wiederholt
/// erscheint. Pure-Logik (`shouldShow(...)`) ist separat für Tests.
struct BetaGracePromptView: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Danke fürs Testen!").font(.title).bold()
                    Text("Du bist Beta-User der ersten Stunde.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Was das für dich bedeutet")
                    .font(.headline)
                bullet("Alle Pro-Features bleiben für dich **lebenslang frei**.")
                bullet("Keine versteckten Limits, kein Trial-Ablauf.")
                bullet("Updates für NeoQuill 1.x sind inklusive.")
                bullet("Falls 2.0 kommt, bekommst du den Beta-Loyalty-Preis.")
            }

            Spacer()

            HStack {
                Spacer()
                Button("Verstanden, weiter zur App") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 480, height: 380)
    }

    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").bold()
            Text(LocalizedStringKey(markdown))
        }
    }
}

enum BetaGracePrompt {

    static let userDefaultsKey = "beta_grace_prompt_shown"

    /// Entscheidet ob das Welcome-Sheet jetzt gezeigt werden soll.
    /// Bedingungen:
    ///   - Status ist `.betaGrace`
    ///   - Mode ist `.enforced` (im Beta-Modus ohne Switch gibt's keine Notice)
    ///   - Flag noch nicht gesetzt
    static func shouldShow(snapshot: LicenseSnapshot, defaults: UserDefaults) -> Bool {
        guard snapshot.mode == .enforced else { return false }
        guard snapshot.status == .betaGrace else { return false }
        return !defaults.bool(forKey: userDefaultsKey)
    }

    static func markAsShown(defaults: UserDefaults) {
        defaults.set(true, forKey: userDefaultsKey)
    }

    /// Nur für QA/Tests.
    static func reset(defaults: UserDefaults) {
        defaults.removeObject(forKey: userDefaultsKey)
    }
}
