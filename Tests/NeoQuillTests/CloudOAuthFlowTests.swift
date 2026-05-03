import XCTest
@testable import NeoQuill

final class CloudOAuthFlowTests: XCTestCase {

    // MARK: - PKCE

    func testCodeVerifierIsBase64URLAndCorrectLength() {
        let verifier = PKCEUtils.makeCodeVerifier(byteCount: 64)
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertNil(verifier.unicodeScalars.first(where: { !allowed.contains($0) }))
    }

    func testCodeChallengeIsDeterministic() {
        let verifier = "fixed-test-verifier-string-1234567890"
        let challenge1 = PKCEUtils.makeCodeChallenge(from: verifier)
        let challenge2 = PKCEUtils.makeCodeChallenge(from: verifier)
        XCTAssertEqual(challenge1, challenge2)
        XCTAssertFalse(challenge1.contains("="))
        XCTAssertFalse(challenge1.contains("+"))
        XCTAssertFalse(challenge1.contains("/"))
    }

    func testTwoVerifiersDoNotCollide() {
        var seen: Set<String> = []
        for _ in 0..<200 {
            let verifier = PKCEUtils.makeCodeVerifier()
            XCTAssertTrue(seen.insert(verifier).inserted, "Verifier kollidiert: \(verifier)")
        }
    }

    // MARK: - Authorize URL

    func testAuthorizeURLContainsAllRequiredParameters() {
        let config = CloudOAuthConfig(
            provider: .teams,
            clientId: "abc-123",
            authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            scopes: ["openid", "OnlineMeetings.Read"],
            redirectURI: URL(string: "neoquill://oauth/teams")!,
            callbackScheme: "neoquill"
        )
        let url = CloudOAuthService.authorizeURL(config: config, codeChallenge: "challenge-xyz", state: "state-42")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(items["client_id"], "abc-123")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["code_challenge"], "challenge-xyz")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["state"], "state-42")
        XCTAssertEqual(items["scope"], "openid OnlineMeetings.Read")
        XCTAssertEqual(items["redirect_uri"], "neoquill://oauth/teams")
        XCTAssertEqual(items["response_mode"], "query", "Teams braucht response_mode=query")
    }

    func testAuthorizeURLForMeetIncludesOfflineAccess() {
        let config = CloudOAuthConfig(
            provider: .meet,
            clientId: "meet-id",
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            scopes: ["meetings.space.readonly"],
            redirectURI: URL(string: "neoquill://oauth/meet")!,
            callbackScheme: "neoquill"
        )
        let url = CloudOAuthService.authorizeURL(config: config, codeChallenge: "x", state: "y")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertTrue(items.contains { $0.name == "access_type" && $0.value == "offline" })
        XCTAssertTrue(items.contains { $0.name == "prompt" && $0.value == "consent" })
    }

    // MARK: - Callback parsing

    func testParseCallbackExtractsCodeWhenStateMatches() throws {
        let url = URL(string: "neoquill://oauth/teams?code=abcd1234&state=state-42")!
        let parsed = try CloudOAuthService.parseCallback(url, expectedState: "state-42")
        XCTAssertEqual(parsed.code, "abcd1234")
        XCTAssertEqual(parsed.state, "state-42")
    }

    func testParseCallbackThrowsOnStateMismatch() {
        let url = URL(string: "neoquill://oauth/teams?code=abc&state=wrong")!
        XCTAssertThrowsError(try CloudOAuthService.parseCallback(url, expectedState: "right")) { error in
            guard case CloudOAuthService.AuthError.missingState = error else {
                return XCTFail("Erwartet missingState, war: \(error)")
            }
        }
    }

    func testParseCallbackThrowsWhenCodeMissing() {
        let url = URL(string: "neoquill://oauth/teams?state=anything")!
        XCTAssertThrowsError(try CloudOAuthService.parseCallback(url, expectedState: "anything"))
    }

    // MARK: - Token decoding

    func testDecodeTokenResponseExtractsAllFields() throws {
        let json = """
        {
          "access_token": "AT123",
          "refresh_token": "RT456",
          "expires_in": 3600,
          "scope": "openid OnlineMeetings.Read",
          "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let tokens = try CloudOAuthService.decodeTokenResponse(data: json, fallbackScope: "openid")
        XCTAssertEqual(tokens.accessToken, "AT123")
        XCTAssertEqual(tokens.refreshToken, "RT456")
        XCTAssertEqual(tokens.scope, "openid OnlineMeetings.Read")
        XCTAssertEqual(tokens.tokenType, "Bearer")
        XCTAssertGreaterThan(tokens.expiresAt, Date().addingTimeInterval(3500))
        XCTAssertLessThan(tokens.expiresAt, Date().addingTimeInterval(3700))
    }

    func testDecodeTokenResponseFallsBackToScopeWhenMissing() throws {
        let json = """
        {"access_token": "AT", "expires_in": 1800}
        """.data(using: .utf8)!
        let tokens = try CloudOAuthService.decodeTokenResponse(data: json, fallbackScope: "fallback-scope")
        XCTAssertEqual(tokens.scope, "fallback-scope")
        XCTAssertEqual(tokens.tokenType, "Bearer")
    }

    func testTokenSetExpiryIsConsideredImminent() {
        let almostExpired = CloudTokenSet(
            accessToken: "AT", refreshToken: "RT",
            expiresAt: Date().addingTimeInterval(30),
            scope: nil, tokenType: "Bearer"
        )
        XCTAssertTrue(almostExpired.isExpired, "Innerhalb der 60s-Grenze gilt Token als expired")
    }

    // MARK: - Form encoding

    func testUrlEncodedQueryEscapesSpecialCharacters() {
        let encoded = CloudOAuthService.urlEncoded([
            "scope": "openid offline_access",
            "redirect_uri": "neoquill://oauth/teams"
        ])
        XCTAssertTrue(encoded.contains("scope=openid%20offline_access"))
        XCTAssertTrue(encoded.contains("redirect_uri=neoquill://oauth/teams")
                      || encoded.contains("redirect_uri=neoquill%3A%2F%2Foauth%2Fteams"))
    }

    // MARK: - In-memory token store

    func testInMemoryTokenStoreRoundtripsTokens() throws {
        let store = InMemoryCloudTokenStore()
        let tokens = CloudTokenSet(
            accessToken: "AT", refreshToken: "RT",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "scope", tokenType: "Bearer"
        )
        try store.save(provider: .zoom, tokens: tokens)
        XCTAssertEqual(store.load(provider: .zoom), tokens)
        store.clear(provider: .zoom)
        XCTAssertNil(store.load(provider: .zoom))
    }
}
