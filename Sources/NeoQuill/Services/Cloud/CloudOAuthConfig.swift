import Foundation

// Provider-Konfigurationen. Client-IDs sind PFLICHT-Felder die Niko in einer
// `CloudCredentials.plist` oder via Build-Setting setzt. Default-Wert ist
// leer → der Sign-In-Pfad zeigt einen klaren Onboarding-Hinweis statt zu krachen.

struct CloudOAuthConfig {
    let provider: CloudProvider
    let clientId: String
    let authorizeURL: URL
    let tokenURL: URL
    let scopes: [String]
    let redirectURI: URL
    /// macOS URL-Scheme der App (ohne "://"). Pflicht fuer ASWebAuthenticationSession.
    let callbackScheme: String

    var isConfigured: Bool { !clientId.isEmpty }
}

enum CloudOAuthCatalog {
    /// Wird aus Bundle/Defaults geladen. Niko traegt seine Client-IDs in
    /// `Info.plist`-Keys ein:
    /// - NeoQuillTeamsClientId
    /// - NeoQuillMeetClientId
    /// - NeoQuillZoomClientId
    /// Wenn leer → `isConfigured == false`, UI sagt "Plattform-Account
    /// einrichten" mit Link zur Doku.
    static func config(for provider: CloudProvider, bundle: Bundle = .main) -> CloudOAuthConfig {
        switch provider {
        case .teams:
            return CloudOAuthConfig(
                provider: .teams,
                clientId: bundle.string(forKey: "NeoQuillTeamsClientId") ?? "",
                authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
                tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
                scopes: [
                    "openid", "profile", "offline_access",
                    "OnlineMeetings.Read", "OnlineMeetingTranscript.Read.All"
                ],
                redirectURI: URL(string: "neoquill://oauth/teams")!,
                callbackScheme: "neoquill"
            )
        case .meet:
            return CloudOAuthConfig(
                provider: .meet,
                clientId: bundle.string(forKey: "NeoQuillMeetClientId") ?? "",
                authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: [
                    "https://www.googleapis.com/auth/meetings.space.readonly",
                    "https://www.googleapis.com/auth/calendar.readonly"
                ],
                redirectURI: URL(string: "neoquill://oauth/meet")!,
                callbackScheme: "neoquill"
            )
        case .zoom:
            return CloudOAuthConfig(
                provider: .zoom,
                clientId: bundle.string(forKey: "NeoQuillZoomClientId") ?? "",
                authorizeURL: URL(string: "https://zoom.us/oauth/authorize")!,
                tokenURL: URL(string: "https://zoom.us/oauth/token")!,
                scopes: ["recording:read", "meeting:read", "user:read"],
                redirectURI: URL(string: "neoquill://oauth/zoom")!,
                callbackScheme: "neoquill"
            )
        }
    }
}

private extension Bundle {
    func string(forKey key: String) -> String? {
        guard let raw = object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
