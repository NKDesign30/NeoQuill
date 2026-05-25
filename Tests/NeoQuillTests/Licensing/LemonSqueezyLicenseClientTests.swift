import XCTest
@testable import NeoQuill

/// Fake HTTP-Layer für die Client-Tests. Speichert die letzte Request und
/// liefert eine programmierbare Response.
final class FakeHTTPDataFetcher: HTTPDataFetching {
    var nextResponse: Result<(Data, URLResponse), Error> = .failure(LSLicenseError.nonHTTPResponse)
    private(set) var lastRequest: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        return try nextResponse.get()
    }

    func enqueue(json: String, status: Int = 200, url: URL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!) {
        let data = Data(json.utf8)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        nextResponse = .success((data, response))
    }
}

final class LemonSqueezyLicenseClientTests: XCTestCase {

    private var fake: FakeHTTPDataFetcher!
    private var client: LemonSqueezyLicenseClient!

    override func setUp() {
        super.setUp()
        fake = FakeHTTPDataFetcher()
        client = LemonSqueezyLicenseClient(session: fake)
    }

    // MARK: - Activate

    func test_activate_postsFormBodyWithKeyAndInstanceName() async throws {
        fake.enqueue(json: """
        {
          "activated": true,
          "error": null,
          "license_key": {"id": 42, "status": "active", "key": "ABCD-1234-EFGH-5678",
                          "activation_limit": 1, "activation_usage": 1, "expires_at": null},
          "instance": {"id": "inst-xyz", "name": "MacBook Pro 14", "created_at": "2026-05-25T10:00:00Z"},
          "meta": {"store_id": 386920, "order_id": 9000, "order_item_id": 1, "product_id": 1086348,
                   "product_name": "NeoQuill", "variant_id": 1702242, "variant_name": "Lifetime (1.x)",
                   "customer_email": "test@example.com"}
        }
        """)

        let result = try await client.activate(licenseKey: "ABCD-1234-EFGH-5678", instanceName: "MacBook Pro 14")

        XCTAssertTrue(result.activated)
        XCTAssertEqual(result.instance?.id, "inst-xyz")
        XCTAssertEqual(result.meta?.variantID, 1702242)

        let req = try XCTUnwrap(fake.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertEqual(req.url?.path, "/v1/licenses/activate")

        let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("license_key=ABCD-1234-EFGH-5678"))
        XCTAssertTrue(body.contains("instance_name=MacBook%20Pro%2014"))
    }

    func test_activate_returnsErrorMessage_whenLSReportsFailure() async throws {
        fake.enqueue(json: """
        {"activated": false, "error": "license_key not found", "license_key": null, "instance": null, "meta": null}
        """, status: 200)

        let result = try await client.activate(licenseKey: "FAKE", instanceName: "Mac")
        XCTAssertFalse(result.activated)
        XCTAssertEqual(result.errorMessage, "license_key not found")
    }

    // MARK: - Validate

    func test_validate_returnsValidForActiveLicense() async throws {
        fake.enqueue(json: """
        {
          "valid": true,
          "error": null,
          "license_key": {"id": 42, "status": "active", "key": "ABCD-1234-EFGH-5678",
                          "activation_limit": 1, "activation_usage": 1, "expires_at": null},
          "instance": {"id": "inst-xyz", "name": "MacBook", "created_at": "2026-05-25T10:00:00Z"},
          "meta": {"store_id": 386920, "order_id": 9000, "order_item_id": 1, "product_id": 1086348,
                   "product_name": "NeoQuill", "variant_id": 1702242, "variant_name": "Lifetime (1.x)",
                   "customer_email": "t@e.com"}
        }
        """)

        let result = try await client.validate(licenseKey: "ABCD-1234-EFGH-5678", instanceID: "inst-xyz")
        XCTAssertTrue(result.valid)
        XCTAssertEqual(result.licenseKey?.status, "active")
        XCTAssertEqual(result.meta?.variantID, 1702242)
    }

    func test_validate_returnsInvalidForRefundedLicense() async throws {
        fake.enqueue(json: """
        {
          "valid": false,
          "error": "license_key has been disabled",
          "license_key": {"id": 42, "status": "disabled", "key": null,
                          "activation_limit": 1, "activation_usage": 1, "expires_at": null},
          "instance": null,
          "meta": null
        }
        """)

        let result = try await client.validate(licenseKey: "ABCD", instanceID: "inst")
        XCTAssertFalse(result.valid)
        XCTAssertEqual(result.licenseKey?.status, "disabled")
    }

    // MARK: - Deactivate

    func test_deactivate_returnsTrueOnSuccess() async throws {
        fake.enqueue(json: """
        {"deactivated": true, "error": null}
        """)

        let result = try await client.deactivate(licenseKey: "ABCD", instanceID: "inst-xyz")
        XCTAssertTrue(result.deactivated)
        XCTAssertNil(result.errorMessage)
    }

    // MARK: - HTTP-Fehler

    func test_throws_onNon2xxStatus() async {
        fake.enqueue(json: "{\"error\":\"not found\"}", status: 404)

        do {
            _ = try await client.validate(licenseKey: "X", instanceID: "Y")
            XCTFail("Expected throw")
        } catch let LSLicenseError.httpStatus(code, body) {
            XCTAssertEqual(code, 404)
            XCTAssertTrue(body?.contains("not found") ?? false)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_throws_onMalformedJSON() async {
        fake.enqueue(json: "not even close to json", status: 200)
        do {
            _ = try await client.validate(licenseKey: "X", instanceID: "Y")
            XCTFail("Expected throw")
        } catch LSLicenseError.invalidJSON {
            // ok
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
