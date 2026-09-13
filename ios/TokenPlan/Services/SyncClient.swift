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

struct PrewarmRun: Codable, Equatable, Sendable {
    let id: UInt64
    let triggeredAt: UInt64
    let source: String
    let success: Bool
    let httpStatus: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, source, success, error
        case triggeredAt = "triggered_at"
        case httpStatus = "http_status"
    }
}

struct PrewarmState: Codable, Equatable, Sendable {
    let enabled: Bool
    let model: String
    let schedule: String
    let timezone: String
    let hasAPIKey: Bool
    let lastRun: PrewarmRun?

    enum CodingKeys: String, CodingKey {
        case enabled, model, schedule, timezone
        case hasAPIKey = "has_api_key"
        case lastRun = "last_run"
    }
}

private struct PrewarmConfigRequest: Codable {
    let enabled: Bool
    let apiKey: String?
    let model: String

    enum CodingKeys: String, CodingKey {
        case enabled, model
        case apiKey = "api_key"
    }
}

private struct RotateCredentialsRequest: Codable {
    let newToken: String
    let envelope: VaultEnvelope

    enum CodingKeys: String, CodingKey {
        case envelope
        case newToken = "new_token"
    }
}

struct SyncClient {
    let token: String
    var session: URLSession = .shared

    init(username: String, password: String, session: URLSession? = nil) throws {
        try SyncCredentials.validate(username: username, password: password)
        self.token = SyncCredentials.authToken(username: username, password: password)
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

    func rotateCredentials(newToken: String, envelope: VaultEnvelope, revision: UInt64) async throws -> UInt64 {
        var request = URLRequest(url: credentialsURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(revision)\"", forHTTPHeaderField: "If-Match")
        request.httpBody = try JSONEncoder().encode(
            RotateCredentialsRequest(newToken: newToken, envelope: envelope)
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, allowing: [200])
        return try JSONDecoder().decode(UpdateResponse.self, from: data).revision
    }

    func getPrewarm() async throws -> PrewarmState {
        var request = authorizedRequest(url: prewarmURL)
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        try validate(response, allowing: [200])
        return try JSONDecoder().decode(PrewarmState.self, from: data)
    }

    func savePrewarm(enabled: Bool, apiKey: String, model: String) async throws -> PrewarmState {
        var request = authorizedRequest(url: prewarmURL)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PrewarmConfigRequest(
                enabled: enabled,
                apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : apiKey,
                model: model
            )
        )
        let (data, response) = try await session.data(for: request)
        try validate(response, allowing: [200])
        return try JSONDecoder().decode(PrewarmState.self, from: data)
    }

    func runPrewarm() async throws -> PrewarmRun {
        var request = authorizedRequest(url: prewarmRunURL)
        request.httpMethod = "POST"
        let (data, response) = try await session.data(for: request)
        try validate(response, allowing: [200])
        return try JSONDecoder().decode(PrewarmRun.self, from: data)
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private var vaultURL: URL {
        SyncCredentials.endpoint.appendingPathComponent("api/v1/vault")
    }

    private var credentialsURL: URL {
        SyncCredentials.endpoint.appendingPathComponent("api/v1/vault/credentials")
    }

    private var prewarmURL: URL {
        SyncCredentials.endpoint.appendingPathComponent("api/v1/prewarm")
    }

    private var prewarmRunURL: URL {
        SyncCredentials.endpoint.appendingPathComponent("api/v1/prewarm/run")
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
