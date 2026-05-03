import Foundation
import CryptoKit

// PKCE Helper (RFC 7636). Verifier + Challenge für OAuth-Flows ohne Client-Secret.
// Beide Plattformen (Microsoft Graph, Google Identity) erwarten S256-Challenge.

enum PKCEUtils {
    /// Erzeugt einen 64-Byte Random-Verifier, Base64URL-kodiert.
    /// RFC 7636 verlangt 43-128 Zeichen [A-Z a-z 0-9 - . _ ~].
    static func makeCodeVerifier(byteCount: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64URL(Data(bytes))
    }

    /// SHA256(verifier) → Base64URL. Wird als `code_challenge` mit
    /// `code_challenge_method=S256` an die Authorize-URL gehaengt.
    static func makeCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return base64URL(Data(digest))
    }

    /// Generischer Random-State für CSRF-Schutz.
    static func makeState(byteCount: Int = 24) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
