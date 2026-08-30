import Foundation

enum Provider: String, CaseIterable, Identifiable, Codable, Sendable {
    case volcengine
    case kimi
    case zhipu
    case zhipuTeam = "zhipu_team"
    case minimax
    case zenmux
    case opencodeGo = "opencode_go"
    case deepseek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volcengine: "火山方舟"
        case .kimi: "Kimi For Coding"
        case .zhipu: "智谱 GLM"
        case .zhipuTeam: "智谱 GLM 团队"
        case .minimax: "MiniMax"
        case .zenmux: "ZenMux"
        case .opencodeGo: "OpenCode Go"
        case .deepseek: "DeepSeek 余额"
        }
    }
}

struct Profile: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var provider: String
    var type: String
    var accessKey: String
    var secretKey: String
    var apiKey: String
    var region: String
    var baseURL: String
    var organizationID: String
    var projectID: String
    var enabled: Bool

    init(provider: Provider = .volcengine) {
        id = UUID().uuidString.lowercased()
        name = provider.title
        self.provider = provider.rawValue
        type = "auto"
        accessKey = ""
        secretKey = ""
        apiKey = ""
        region = "cn"
        baseURL = ""
        organizationID = ""
        projectID = ""
        enabled = true
    }

    enum CodingKeys: String, CodingKey {
        case id, name, provider, type, region, enabled
        case accessKey = "access_key"
        case secretKey = "secret_key"
        case apiKey = "api_key"
        case baseURL = "base_url"
        case organizationID = "organization_id"
        case projectID = "project_id"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? "Token Plan"
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? Provider.volcengine.rawValue
        type = try values.decodeIfPresent(String.self, forKey: .type) ?? "auto"
        accessKey = try values.decodeIfPresent(String.self, forKey: .accessKey) ?? ""
        secretKey = try values.decodeIfPresent(String.self, forKey: .secretKey) ?? ""
        apiKey = try values.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        region = try values.decodeIfPresent(String.self, forKey: .region) ?? "cn"
        baseURL = try values.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        organizationID = try values.decodeIfPresent(String.self, forKey: .organizationID) ?? ""
        projectID = try values.decodeIfPresent(String.self, forKey: .projectID) ?? ""
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    func validate() throws {
        guard !id.isEmpty, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let provider = Provider(rawValue: provider), ["cn", "global"].contains(region) else {
            throw TokenPlanError.invalidProfiles
        }
        guard enabled else { return }
        if provider == .volcengine {
            guard !accessKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TokenPlanError.missingProfileCredentials
            }
        } else if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TokenPlanError.missingProfileCredentials
        }
        if provider == .zhipuTeam,
           organizationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
           projectID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TokenPlanError.missingProfileCredentials
        }
        if provider == .zenmux {
            guard let components = URLComponents(string: baseURL),
                  components.scheme == "https", let host = components.host?.lowercased(),
                  host == "zenmux.ai" || host == "zenmux.com" ||
                  host.hasSuffix(".zenmux.ai") || host.hasSuffix(".zenmux.com"),
                  components.user == nil, components.password == nil,
                  components.fragment == nil, components.port == nil || components.port == 443 else {
                throw TokenPlanError.invalidEndpoint
            }
        }
    }
}
