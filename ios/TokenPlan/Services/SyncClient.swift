import Foundation

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct VaultResponse: Codable {
    let revision: UInt64
    let updatedAt: UInt64
    let envelope: VaultEnvelope

    enum CodingKeys: String, CodingKey {
        case revision, envelope
        case updatedAt = "updated_at"
    }
}

struct UpdateResponse: Codable {
    let revision: UInt64
}

struct SyncClient {
    let endpoint: URL
    let token: String
    var session: URLSession = .shared

    init(endpoint: String, token: String, session: URLSession? = nil) throws {
        guard let components = URLComponents(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", components.host != nil,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.port == nil || components.port == 443,
              let baseURL = components.url,
              token.trimmingCharacters(in: .whitespacesAndNewlines).count >= 32 else {
            throw TokenPlanError.invalidEndpoint
        }
        self.endpoint = baseURL
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            self.session = URLSession(
                configuration: configuration,
                delegate: NoRedirectDelegate(),
                delegateQueue: nil
            )
        }
    }

    func pull() async throws -> VaultResponse {
        var request = URLRequest(url: vaultURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        try validate(response, allowing: [200])
        return try JSONDecoder().decode(VaultResponse.self, from: data)
    }

    func push(_ envelope: VaultEnvelope, revision: UInt64) async throws -> UInt64 {
        var request = URLRequest(url: vaultURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(revision)\"", forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(envelope)
        let (data, response) = try await session.data(for: request)
        try validate(response, allowing: [200])
        return try JSONDecoder().decode(UpdateResponse.self, from: data).revision
    }

    private var vaultURL: URL {
        endpoint.appendingPathComponent("api/v1/vault")
    }

    private func validate(_ response: URLResponse, allowing statuses: Set<Int>) throws {
        guard let response = response as? HTTPURLResponse else { throw TokenPlanError.http(0) }
        if statuses.contains(response.statusCode) { return }
        switch response.statusCode {
        case 401: throw TokenPlanError.unauthorized
        case 404: throw TokenPlanError.cloudEmpty
        case 409: throw TokenPlanError.conflict
        default: throw TokenPlanError.http(response.statusCode)
        }
    }
}
