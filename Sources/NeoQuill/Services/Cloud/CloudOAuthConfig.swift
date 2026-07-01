import Foundation

// Provider-Konfigurationen. Client-IDs sind Pflichtfelder, aber keine Secrets.
// Betreiber können sie in den App-Einstellungen setzen; Bundle-Keys bleiben nur
// als Enterprise-Build-Fallback erhalten.

struct CloudOAuthConfig {
    let provider: CloudProvider
    let clientId: String
    let authorizeURL: URL
    let tokenURL: URL
    let scopes: [String]
    let redirectURI: URL
    /// macOS URL-Scheme der App (ohne "://"). Pflicht für ASWebAuthenticationSession.
    let callbackScheme: String

    var isConfigured: Bool { !clientId.isEmpty }
}

enum CloudOAuthCatalog {
    static func config(
        for provider: CloudProvider,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> CloudOAuthConfig {
        switch provider {
        case .teams:
            let defaultScopes = [
                "openid", "profile", "offline_access",
                "OnlineMeetings.Read", "OnlineMeetingTranscript.Read.All"
            ]
            return CloudOAuthConfig(
                provider: .teams,
                clientId: clientId(
                    defaultsKey: AppSettings.cloudTeamsClientId,
                    bundleKey: "NeoQuillTeamsClientId",
                    bundle: bundle,
                    defaults: defaults
                ),
                authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
                tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
                scopes: scopes(defaultsKey: AppSettings.cloudTeamsScopes, defaults: defaults, fallback: defaultScopes),
                redirectURI: URL(string: "neoquill://oauth/teams")!,
                callbackScheme: "neoquill"
            )
        case .meet:
            let defaultScopes = [
                "https://www.googleapis.com/auth/meetings.space.readonly",
                "https://www.googleapis.com/auth/calendar.readonly"
            ]
            return CloudOAuthConfig(
                provider: .meet,
                clientId: clientId(
                    defaultsKey: AppSettings.cloudMeetClientId,
                    bundleKey: "NeoQuillMeetClientId",
                    bundle: bundle,
                    defaults: defaults
                ),
                authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
                scopes: scopes(defaultsKey: AppSettings.cloudMeetScopes, defaults: defaults, fallback: defaultScopes),
                redirectURI: URL(string: "neoquill://oauth/meet")!,
                callbackScheme: "neoquill"
            )
        case .zoom:
            let defaultScopes = ["recording:read", "meeting:read", "user:read"]
            return CloudOAuthConfig(
                provider: .zoom,
                clientId: clientId(
                    defaultsKey: AppSettings.cloudZoomClientId,
                    bundleKey: "NeoQuillZoomClientId",
                    bundle: bundle,
                    defaults: defaults
                ),
                authorizeURL: URL(string: "https://zoom.us/oauth/authorize")!,
                tokenURL: URL(string: "https://zoom.us/oauth/token")!,
                scopes: scopes(defaultsKey: AppSettings.cloudZoomScopes, defaults: defaults, fallback: defaultScopes),
                redirectURI: URL(string: "neoquill://oauth/zoom")!,
                callbackScheme: "neoquill"
            )
        }
    }

    private static func clientId(
        defaultsKey: AppSetting<String>,
        bundleKey: String,
        bundle: Bundle,
        defaults: UserDefaults
    ) -> String {
        if let configured = defaults.trimmedString(forKey: defaultsKey.key) {
            return configured
        }
        return bundle.string(forKey: bundleKey) ?? ""
    }

    private static func scopes(
        defaultsKey: AppSetting<String>,
        defaults: UserDefaults,
        fallback: [String]
    ) -> [String] {
        guard let configured = defaults.trimmedString(forKey: defaultsKey.key) else {
            return fallback
        }
        let parsed = configured
            .split { $0.isWhitespace || $0 == "," || $0 == ";" }
            .map(String.init)
        return parsed.isEmpty ? fallback : parsed
    }
}

private extension Bundle {
    func string(forKey key: String) -> String? {
        guard let raw = object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension UserDefaults {
    func trimmedString(forKey key: String) -> String? {
        guard let raw = string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
