import XCTest
@testable import TokenPlan

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class SyncClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testEndpointRejectsHTTPPathsAndCredentials() {
        let token = String(repeating: "a", count: 32)
        for endpoint in [
            "http://47.102.119.11",
            "https://user:pass@47.102.119.11",
            "https://47.102.119.11/path",
            "https://47.102.119.11?token=bad"
        ] {
            XCTAssertThrowsError(try SyncClient(endpoint: endpoint, token: token), endpoint)
        }
    }

    func testPushUsesBearerAndRevisionWithoutPlaintext() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let token = String(repeating: "b", count: 32)
        let envelope = VaultEnvelope(schemaVersion: 1, nonce: "nonce", ciphertext: "ciphertext")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://47.102.119.11/api/v1/vault")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"4\"")
            XCTAssertFalse(String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("api_key"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"revision":5}"#.utf8))
        }
        let client = try SyncClient(endpoint: "https://47.102.119.11", token: token, session: session)
        let revision = try await client.push(envelope, revision: 4)
        XCTAssertEqual(revision, 5)
    }

    func testConflictIsReported() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 409,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        let client = try SyncClient(
            endpoint: "https://47.102.119.11",
            token: String(repeating: "c", count: 32),
            session: session
        )
        do {
            _ = try await client.push(
                VaultEnvelope(schemaVersion: 1, nonce: "n", ciphertext: "c"),
                revision: 1
            )
            XCTFail("Expected conflict")
        } catch TokenPlanError.conflict {
            // Expected.
        }
    }
}
