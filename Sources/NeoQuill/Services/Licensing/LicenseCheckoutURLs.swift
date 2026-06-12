import Foundation

/// Mapping von Lemon-Squeezy Variant-IDs auf öffentliche Checkout-URLs.
///
/// LS generiert pro Variant einen UUID-`slug`. Die Buy-URL hat das Format
/// `https://<store>.lemonsqueezy.com/checkout/buy/<slug>` (mit optionalem
/// `?embed=1` für das Overlay-Widget). Slugs werden in
/// `Tools/LSAdmin/state.json` gepflegt und müssen hier mit der Quelle
/// synchron bleiben — wenn in LS eine Variant gelöscht und neu angelegt wird,
/// ändert sich der Slug.
enum LicenseCheckoutURLs {

    /// Store-Subdomain (aus `product.buy_now_url` abgeleitet).
    static let storeBase = "https://neon-studio.lemonsqueezy.com"

    /// Slug pro Variant — Source of Truth ist
    /// `Tools/LSAdmin/state.json` → `variants[].slug`.
    static let slugByVariantID: [Int: String] = [
        VariantIDMap.lifetime:     "715a69f4-bfd8-4841-8f3f-4747d5fc1e46",
        VariantIDMap.majorUpgrade: "87a07ac9-2346-482a-8120-338a85bc60ab",
        VariantIDMap.team5:        "3c0e6ae1-4012-40fa-a207-89c55f9bed73",
        VariantIDMap.team10:       "f9c42edd-b339-4a80-bb29-3533389c8dc2",
    ]

    /// Liefert die direkte Buy-URL für ein Variant oder `nil`, wenn der Slug
    /// fehlt. Caller können auf die Store-Startseite (`storeFallback`)
    /// zurückfallen.
    static func buyURL(variantID: Int) -> URL? {
        guard let slug = slugByVariantID[variantID] else { return nil }
        return URL(string: "\(storeBase)/checkout/buy/\(slug)")
    }

    /// Sicherer Fallback wenn der Slug-Lookup fehlschlägt — zeigt mindestens
    /// die Store-Seite. Sollte in der Praxis nie passieren, weil alle vier
    /// Variants gemappt sind.
    static var storeFallback: URL {
        URL(string: storeBase)!
    }
}
