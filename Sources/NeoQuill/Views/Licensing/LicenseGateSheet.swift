import SwiftUI

/// Modal-Sheet das aufpoppt bei `.trialExpired` / `.invalidated` oder über
/// die Settings-Aktion. Bietet "Lizenz kaufen" + "Lizenz aktivieren".
/// MVP-Variante — Detail-Polish in späterem Slice.
struct LicenseGateSheet: View {

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var licenseKey: String = ""
    @State private var activating = false
    @State private var activationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            buyBlock

            Divider()

            activateBlock

            Spacer()
        }
        .padding(28)
        .frame(width: 520, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NeoQuill freischalten").font(.title).bold()
            Text("Pro-Features (TL;DR, Action-Items, Highlights, Chapters, Speaker-ID cross-meeting, Platform-Imports) brauchen eine Lizenz. Recording und lokales Transkript bleiben weiterhin frei.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var buyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lizenz kaufen").font(.headline)
            VariantRow(label: "Lifetime (1.x)", price: "89 €", url: Self.checkoutURL(variantID: VariantIDMap.lifetime))
            VariantRow(label: "Major Upgrade auf 2.0", price: "39 €", url: Self.checkoutURL(variantID: VariantIDMap.majorUpgrade))
            VariantRow(label: "Team — 5 Plätze", price: "349 €", url: Self.checkoutURL(variantID: VariantIDMap.team5))
            VariantRow(label: "Team — 10 Plätze", price: "599 €", url: Self.checkoutURL(variantID: VariantIDMap.team10))
        }
    }

    private var activateBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lizenz aktivieren").font(.headline)
            Text("Schlüssel aus der Bestellbestätigung einsetzen.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("ABCD-1234-EFGH-5678", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button(activating ? "Aktiviere…" : "Aktivieren") {
                    Task { await activate() }
                }
                .disabled(activating || licenseKey.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            if let err = activationError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
    }

    // MARK: - Actions

    private func activate() async {
        activating = true
        activationError = nil
        defer { activating = false }
        do {
            let machine = Host.current().localizedName ?? "Mac"
            _ = try await state.license.activate(
                licenseKey: licenseKey.trimmingCharacters(in: .whitespaces),
                machineName: machine
            )
            dismiss()
        } catch let LicenseValidatorError.activationFailed(message) {
            activationError = message
        } catch LicenseValidatorError.activationMissingInstanceID {
            activationError = "Antwort von Lemon Squeezy unvollständig. Bitte erneut versuchen."
        } catch LicenseValidatorError.unknownVariant(let id) {
            activationError = "Unbekannte Produkt-Variante (\(id))."
        } catch {
            activationError = "Aktivierung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Checkout URLs

    static func checkoutURL(variantID: Int) -> URL {
        LicenseCheckoutURLs.buyURL(variantID: variantID)
            ?? LicenseCheckoutURLs.storeFallback
    }
}

private struct VariantRow: View {
    let label: String
    let price: String
    let url: URL

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(price).foregroundStyle(.secondary)
            Link(destination: url) {
                Label("Kaufen", systemImage: "arrow.up.right.square")
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(.vertical, 4)
    }
}
