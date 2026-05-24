import Foundation
import AuthenticationServices

// Generischer OAuth 2.0 PKCE-Flow über ASWebAuthenticationSession.
// Provider-agnostisch — Endpunkte + Scopes kommen aus CloudOAuthConfig.
//
// Token-Refresh läuft transparent: jede `accessToken(for:)` Anfrage prüft
// Expiry und holt bei Bedarf via refresh_token einen neuen Access-Token.

@MainActor
final class CloudOAuthService: NSObject, ObservableObject {

    enum AuthError: LocalizedError {
        case notConfigured(CloudProvider)
        case userCancelled
        case malformedCallback
        case missingState
        case tokenExchangeFailed(String)
        case refreshFailed(String)
        case noRefreshToken

        var errorDescription: String? {
            switch self {
            case .notConfigured(let p): return "\(p.displayName)-Client-ID fehlt in der App-Config."
            case .userCancelled:        return "Anmeldung wurde abgebrochen."
            case .malformedCallback:    return "Ungültige OAuth-Antwort vom Provider."
            case .missingState:         return "OAuth-State stimmt nicht (CSRF-Schutz griff)."
            case .tokenExchangeFailed(let m): return "Token-Austausch fehlgeschlagen: \(m)"
            case .refreshFailed(let m): return "Token-Refresh fehlgeschlagen: \(m)"
            case .noRefreshToken:       return "Kein Refresh-Token vorhanden — bitte erneut anmelden."
            }
        }
    }

    @Published private(set) var connectedProviders: Set<CloudProvider> = []

    private let tokenStore: CloudTokenPersisting
    private let urlSession: URLSession
    private let configResolver: (CloudProvider) -> CloudOAuthConfig

    init(
        tokenStore: CloudTokenPersisting = CloudTokenStore(),
        urlSession: URLSession = .shared,
        configResolver: @escaping (CloudProvider) -> CloudOAuthConfig = { CloudOAuthCatalog.config(for: $0) }
    ) {
        self.tokenStore = tokenStore
        self.urlSession = urlSession
        self.configResolver = configResolver
        super.init()
        refreshConnectedSnapshot()
    }

    // MARK: - Public API

    func isConnected(_ provider: CloudProvider) -> Bool {
        tokenStore.load(provider: provider) != nil
    }

    func signIn(_ provider: CloudProvider) async throws {
        let config = configResolver(provider)
        guard config.isConfigured else { throw AuthError.notConfigured(provider) }

        let verifier = PKCEUtils.makeCodeVerifier()
        let challenge = PKCEUtils.makeCodeChallenge(from: verifier)
        let state = PKCEUtils.makeState()

        let authURL = buildAuthorizeURL(config: config, challenge: challenge, state: state)
        let callbackURL = try await present(authURL: authURL, callbackScheme: config.callbackScheme)
        let parsed = try parseCallback(callbackURL, expectedState: state)
        let tokens = try await exchangeCode(parsed.code, verifier: verifier, config: config)
        try tokenStore.save(provider: provider, tokens: tokens)
        refreshConnectedSnapshot()
    }

    func signOut(_ provider: CloudProvider) {
        tokenStore.clear(provider: provider)
        refreshConnectedSnapshot()
    }

    /// Liefert einen frischen Access-Token, refreshed bei Bedarf.
    func accessToken(for provider: CloudProvider) async throws -> String {
        guard var tokens = tokenStore.load(provider: provider) else {
            throw AuthError.noRefreshToken
        }
        if !tokens.isExpired { return tokens.accessToken }
        guard let refreshToken = tokens.refreshToken else { throw AuthError.noRefreshToken }
        let config = configResolver(provider)
        let refreshed = try await refreshTokens(refreshToken: refreshToken, config: config, currentScope: tokens.scope)
        tokens = refreshed
        try tokenStore.save(provider: provider, tokens: tokens)
        refreshConnectedSnapshot()
        return tokens.accessToken
    }

    // MARK: - URL building

    nonisolated static func authorizeURL(
        config: CloudOAuthConfig,
        codeChallenge: String,
        state: String
    ) -> URL {
        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        // Microsoft braucht "response_mode=query" damit der Code als Querystring kommt.
        if config.provider == .teams {
            items.append(URLQueryItem(name: "response_mode", value: "query"))
        }
        // Google braucht "access_type=offline" um Refresh-Tokens zu liefern.
        if config.provider == .meet {
            items.append(URLQueryItem(name: "access_type", value: "offline"))
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        }
        components.queryItems = items
        return components.url!
    }

    nonisolated func buildAuthorizeURL(config: CloudOAuthConfig, challenge: String, state: String) -> URL {
        Self.authorizeURL(config: config, codeChallenge: challenge, state: state)
    }

    nonisolated static func parseCallback(_ url: URL, expectedState: String) throws -> (code: String, state: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw AuthError.malformedCallback
        }
        let code = queryItems.first(where: { $0.name == "code" })?.value
        let state = queryItems.first(where: { $0.name == "state" })?.value
        guard let code, let state, !code.isEmpty else { throw AuthError.malformedCallback }
        guard state == expectedState else { throw AuthError.missingState }
        return (code, state)
    }

    nonisolated func parseCallback(_ url: URL, expectedState: String) throws -> (code: String, state: String) {
        try Self.parseCallback(url, expectedState: expectedState)
    }

    // MARK: - Web session

    private func present(authURL: URL, callbackScheme: String) async throws -> URL {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let error {
                    if let auth = error as? ASWebAuthenticationSessionError, auth.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callback else {
                    continuation.resume(throwing: AuthError.malformedCallback)
                    return
                }
                continuation.resume(returning: callback)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                continuation.resume(throwing: AuthError.malformedCallback)
            }
        }
        return result
    }

    // MARK: - Token exchange + refresh

    private func exchangeCode(
        _ code: String,
        verifier: String,
        config: CloudOAuthConfig
    ) async throws -> CloudTokenSet {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": config.redirectURI.absoluteString,
            "client_id":    config.clientId,
            "code_verifier": verifier,
        ]
        request.httpBody = Self.urlEncoded(params).data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateHttp(response: response, body: data, errorMap: AuthError.tokenExchangeFailed)
        return try Self.decodeTokenResponse(data: data, fallbackScope: config.scopes.joined(separator: " "))
    }

    private func refreshTokens(
        refreshToken: String,
        config: CloudOAuthConfig,
        currentScope: String?
    ) async throws -> CloudTokenSet {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params: [String: String] = [
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "client_id":     config.clientId,
        ]
        if let currentScope { params["scope"] = currentScope }
        request.httpBody = Self.urlEncoded(params).data(using: .utf8)
        let (data, response) = try await urlSession.data(for: request)
        try Self.validateHttp(response: response, body: data, errorMap: AuthError.refreshFailed)
        var result = try Self.decodeTokenResponse(data: data, fallbackScope: currentScope)
        // Manche Provider geben kein neues refresh_token zurück. Dann altes behalten.
        if result.refreshToken == nil { result.refreshToken = refreshToken }
        return result
    }

    nonisolated static func urlEncoded(_ params: [String: String]) -> String {
        params.map { key, value in
            let encodedKey   = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private static func validateHttp(
        response: URLResponse,
        body: Data,
        errorMap: (String) -> AuthError
    ) throws {
        guard let http = response as? HTTPURLResponse else { throw errorMap("Keine HTTP-Antwort") }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: body, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw errorMap("HTTP \(http.statusCode): \(text.prefix(200))")
        }
    }

    nonisolated static func decodeTokenResponse(data: Data, fallbackScope: String?) throws -> CloudTokenSet {
        struct Payload: Decodable {
            let access_token: String
            let token_type: String?
            let refresh_token: String?
            let expires_in: Int?
            let scope: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let lifetime = TimeInterval(payload.expires_in ?? 3_300)
        return CloudTokenSet(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(lifetime),
            scope: payload.scope ?? fallbackScope,
            tokenType: payload.token_type ?? "Bearer"
        )
    }

    private func refreshConnectedSnapshot() {
        connectedProviders = Set(CloudProvider.allCases.filter { tokenStore.load(provider: $0) != nil })
    }
}

extension CloudOAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                Self.presentationAnchorOnMainActor()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                Self.presentationAnchorOnMainActor()
            }
        }
    }

    @MainActor
    private static func presentationAnchorOnMainActor() -> ASPresentationAnchor {
        if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? NSApplication.shared.mainWindow {
            return window
        }
        return ASPresentationAnchor()
    }
}
