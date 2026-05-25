import Foundation
import CoreText

enum FontRegistrar {

    // PostScript-Namen liegen meist anders als die Datei. Wir registrieren stumpf alles
    // was im Fonts/-Ordner liegt — CoreText liest den PostScript-Namen aus der Datei.
    private static let files: [String] = [
        "DMSerifDisplay-Regular",
        "DMSerifDisplay-Italic",
        "SpaceGrotesk-Variable",
        "InterVariable",
        "GeistMono-Variable",
    ]

    static func registerAll() {
        let bundles = candidateBundles()
        var registered = 0
        for name in files {
            for bundle in bundles {
                let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                    ?? bundle.url(forResource: name, withExtension: "ttf")
                guard let url else { continue }
                var error: Unmanaged<CFError>?
                if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    registered += 1
                    NSLog("[NeoQuill·Fonts] registered \(name)")
                } else if let cfError = error?.takeRetainedValue() {
                    let desc = CFErrorCopyDescription(cfError) as String? ?? "unknown error"
                    NSLog("[NeoQuill·Fonts] failed \(name): \(desc)")
                }
                break
            }
        }
        NSLog("[NeoQuill·Fonts] \(registered)/\(files.count) registered")
    }

    private static func candidateBundles() -> [Bundle] {
        AppResourceBundle.candidates()
    }
}
