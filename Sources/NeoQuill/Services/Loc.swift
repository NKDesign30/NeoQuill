import Foundation

/// Zentrale Lokalisierung mit umschaltbarer App-Sprache.
///
/// Warum nicht direkt `Text("key")`: SwiftUI sucht Localizations in
/// `Bundle.main`, die SPM-Resources liegen aber in `Bundle.module`
/// (`NeoQuill_NeoQuill.bundle`). Aller UI-Text geht deshalb über diesen Helper.
/// Zusätzlich erlaubt er eine vom Nutzer gewählte Sprache (`app_language`),
/// unabhängig von der System-Sprache — "system" folgt der System-Einstellung.
enum Loc {
    /// Lokalisierter String in der aktuell gewählten App-Sprache.
    /// Optionale `args` werden über `String(format:)` eingesetzt (z. B. `%@`).
    static func t(_ key: String, _ args: CVarArg...) -> String {
        let template = string(key, lang: currentLanguage)
        return args.isEmpty ? template : String(format: template, arguments: args)
    }

    /// Lokalisierter String in einer explizit angegebenen Sprache. Testbar,
    /// ohne globalen UserDefaults-Zustand anzufassen.
    static func string(_ key: String, lang: String) -> String {
        resolveBundle(for: lang).localizedString(forKey: key, value: key, table: nil)
    }

    static var currentLanguage: String {
        UserDefaults.standard.string(forKey: AppSettings.appLanguage) ?? "system"
    }

    private static func resolveBundle(for lang: String) -> Bundle {
        guard lang != "system",
              let path = Bundle.module.path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return .module
        }
        return bundle
    }
}
