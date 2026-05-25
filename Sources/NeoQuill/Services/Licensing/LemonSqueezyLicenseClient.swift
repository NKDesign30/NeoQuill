import Foundation

/// HTTP-Client gegen die Lemon-Squeezy-License-API.
///
/// Wichtig: License-Endpoints (im Gegensatz zum Rest der LS-API)
///   - akzeptieren `application/x-www-form-urlencoded`
///   - erwarten KEINEN Bearer-Token — der License-Key selbst ist das Secret
///   - liegen unter `https://api.lemonsqueezy.com/v1/licenses/...`
///
/// Doku: https://docs.lemonsqueezy.com/api/license-api
protocol LemonSqueezyLicensing {
    func activate(licenseKey: String, instanceName: String) async throws -> LSActivationResponse
    func validate(licenseKey: String, instanceID: String) async throws -> LSValidationResponse
    func deactivate(licenseKey: String, instanceID: String) async throws -> LSDeactivationResponse
}

// MARK: - Response Types

struct LSActivationResponse: Equatable {
    let activated: Bool
    let errorMessage: String?
    let licenseKey: LSLicenseKeyInfo?
    let instance: LSInstanceInfo?
    let meta: LSMeta?
}

struct LSValidationResponse: Equatable {
    let valid: Bool
    let errorMessage: String?
    let licenseKey: LSLicenseKeyInfo?
    let instance: LSInstanceInfo?
    let meta: LSMeta?
}

struct LSDeactivationResponse: Equatable {
    let deactivated: Bool
    let errorMessage: String?
}

struct LSLicenseKeyInfo: Equatable, Codable {
    let id: Int
    let status: String        // "active" | "inactive" | "expired" | "disabled"
    let key: String?
    let activationLimit: Int?
    let activationUsage: Int?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, status, key
        case activationLimit = "activation_limit"
        case activationUsage = "activation_usage"
        case expiresAt = "expires_at"
    }
}

struct LSInstanceInfo: Equatable, Codable {
    let id: String
    let name: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

struct LSMeta: Equatable, Codable {
    let storeID: Int?
    let orderID: Int?
    let orderItemID: Int?
    let productID: Int?
    let productName: String?
    let variantID: Int?
    let variantName: String?
    let customerEmail: String?

    enum CodingKeys: String, CodingKey {
        case storeID = "store_id"
        case orderID = "order_id"
        case orderItemID = "order_item_id"
        case productID = "product_id"
        case productName = "product_name"
        case variantID = "variant_id"
        case variantName = "variant_name"
        case customerEmail = "customer_email"
    }
}

enum LSLicenseError: Error, Equatable {
    case malformedURL
    case transport(String)
    case nonHTTPResponse
    case invalidJSON
    case httpStatus(Int, String?)
}

// MARK: - Live-Client

/// Protokoll für die HTTP-Schicht. `URLSession` adoptiert es per Extension.
protocol HTTPDataFetching {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPDataFetching {}

final class LemonSqueezyLicenseClient: LemonSqueezyLicensing {
    private let baseURL: URL
    private let session: HTTPDataFetching
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://api.lemonsqueezy.com")!,
        session: HTTPDataFetching = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: - Endpoints

    func activate(licenseKey: String, instanceName: String) async throws -> LSActivationResponse {
        let body = [
            "license_key": licenseKey,
            "instance_name": instanceName,
        ]
        let data = try await postForm(path: "/v1/licenses/activate", body: body)
        let raw = try parseRaw(data)
        return LSActivationResponse(
            activated: raw.activated ?? false,
            errorMessage: raw.error,
            licenseKey: raw.licenseKey,
            instance: raw.instance,
            meta: raw.meta
        )
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LSValidationResponse {
        let body = [
            "license_key": licenseKey,
            "instance_id": instanceID,
        ]
        let data = try await postForm(path: "/v1/licenses/validate", body: body)
        let raw = try parseRaw(data)
        return LSValidationResponse(
            valid: raw.valid ?? false,
            errorMessage: raw.error,
            licenseKey: raw.licenseKey,
            instance: raw.instance,
            meta: raw.meta
        )
    }

    func deactivate(licenseKey: String, instanceID: String) async throws -> LSDeactivationResponse {
        let body = [
            "license_key": licenseKey,
            "instance_id": instanceID,
        ]
        let data = try await postForm(path: "/v1/licenses/deactivate", body: body)
        let raw = try parseRaw(data)
        return LSDeactivationResponse(
            deactivated: raw.deactivated ?? false,
            errorMessage: raw.error
        )
    }

    // MARK: - Internal

    private func postForm(path: String, body: [String: String]) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw LSLicenseError.malformedURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = encodeForm(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LSLicenseError.transport(String(describing: error))
        }
        guard let http = response as? HTTPURLResponse else {
            throw LSLicenseError.nonHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyString = String(data: data, encoding: .utf8)
            throw LSLicenseError.httpStatus(http.statusCode, bodyString)
        }
        return data
    }

    private func encodeForm(_ pairs: [String: String]) -> Data {
        let body = pairs
            .map { "\(percentEscape($0.key))=\(percentEscape($0.value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private func percentEscape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private struct RawLSResponse: Decodable {
        let activated: Bool?
        let valid: Bool?
        let deactivated: Bool?
        let error: String?
        let licenseKey: LSLicenseKeyInfo?
        let instance: LSInstanceInfo?
        let meta: LSMeta?

        enum CodingKeys: String, CodingKey {
            case activated, valid, deactivated, error
            case licenseKey = "license_key"
            case instance, meta
        }
    }

    private func parseRaw(_ data: Data) throws -> RawLSResponse {
        do {
            return try decoder.decode(RawLSResponse.self, from: data)
        } catch {
            throw LSLicenseError.invalidJSON
        }
    }
}

// MARK: - Mock-Client

/// Mock-Implementierung für Tests. Speichert die letzten Argumente und gibt
/// vorbereitete Responses zurück.
final class MockLemonSqueezyLicenseClient: LemonSqueezyLicensing {
    var activateResult: Result<LSActivationResponse, Error> = .failure(LSLicenseError.nonHTTPResponse)
    var validateResult: Result<LSValidationResponse, Error> = .failure(LSLicenseError.nonHTTPResponse)
    var deactivateResult: Result<LSDeactivationResponse, Error> = .failure(LSLicenseError.nonHTTPResponse)

    private(set) var lastActivateArgs: (key: String, name: String)?
    private(set) var lastValidateArgs: (key: String, instance: String)?
    private(set) var lastDeactivateArgs: (key: String, instance: String)?

    func activate(licenseKey: String, instanceName: String) async throws -> LSActivationResponse {
        lastActivateArgs = (licenseKey, instanceName)
        return try activateResult.get()
    }

    func validate(licenseKey: String, instanceID: String) async throws -> LSValidationResponse {
        lastValidateArgs = (licenseKey, instanceID)
        return try validateResult.get()
    }

    func deactivate(licenseKey: String, instanceID: String) async throws -> LSDeactivationResponse {
        lastDeactivateArgs = (licenseKey, instanceID)
        return try deactivateResult.get()
    }
}
