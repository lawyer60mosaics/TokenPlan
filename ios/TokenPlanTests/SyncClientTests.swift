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

    func testCredentialsAreValidated() {
        XCTAssertThrowsError(try SyncClient(username: "ab", password: "correct-horse-1234"))
        XCTAssertThrowsError(try SyncClient(username: "token plan", password: "correct-horse-1234"))
        XCTAssertThrowsError(try SyncClient(username: "tokenplan", password: "short"))
    }

    private func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    func testPushUsesBearerAndRevisionWithoutPlaintext() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let token = "oNgFfFG1T4-ATA1kPkTCHqMSqXyDfZraNWRv4l0vNBY"
        let envelope = VaultEnvelope(schemaVersion: 2, nonce: "nonce", ciphertext: "ciphertext")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://tokenplan.xuwenxu.com/api/v1/vault")
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
        let client = try SyncClient(username: "tokenplan", password: "correct-horse-1234", session: session)
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
        let client = try SyncClient(username: "tokenplan", password: "correct-horse-1234", session: session)
        do {
            _ = try await client.push(
                VaultEnvelope(schemaVersion: 2, nonce: "n", ciphertext: "c"),
                revision: 1
            )
            XCTFail("Expected conflict")
        } catch TokenPlanError.conflict {
            // Expected.
        }
    }

    func testCredentialRotationUsesOldAuthorizationAndEncryptedPayload() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let oldToken = "oNgFfFG1T4-ATA1kPkTCHqMSqXyDfZraNWRv4l0vNBY"
        let newToken = String(repeating: "z", count: 43)
        let envelope = VaultEnvelope(schemaVersion: 2, nonce: "new-nonce", ciphertext: "new-ciphertext")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://tokenplan.xuwenxu.com/api/v1/vault/credentials")
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(oldToken)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"7\"")
            let body = try self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["new_token"] as? String, newToken)
            XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("new-password"))
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"revision":8}"#.utf8))
        }
        let client = try SyncClient(username: "tokenplan", password: "correct-horse-1234", session: session)
        let revision = try await client.rotateCredentials(
            newToken: newToken,
            envelope: envelope,
            revision: 7
        )
        XCTAssertEqual(revision, 8)
    }
}
