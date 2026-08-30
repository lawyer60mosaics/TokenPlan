import Foundation

struct WidgetProfileSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let provider: String
    let enabled: Bool
    let usage: PlanUsage
}

struct TokenPlanWidgetSnapshot: Codable, Hashable, Sendable {
    let profiles: [WidgetProfileSummary]
    let updatedAt: Date

    var enabledCount: Int { profiles.filter(\.enabled).count }
    var totalCount: Int { profiles.count }
    var enabledProfiles: [WidgetProfileSummary] { profiles.filter(\.enabled) }
    var featuredProfile: WidgetProfileSummary? {
        enabledProfiles.first(where: { $0.usage.hasDetails }) ?? enabledProfiles.first
    }

    static let empty = TokenPlanWidgetSnapshot(profiles: [], updatedAt: .distantPast)

    static let placeholder = TokenPlanWidgetSnapshot(
        profiles: [
            WidgetProfileSummary(id: "one", name: "Kimi For Coding", provider: "Kimi", enabled: true, usage: PlanUsage(
                status: .success,
                tiers: [PlanUsageTier(name: "five_hour", utilization: 34, resetsAt: nil, usedValueUSD: nil, maxValueUSD: nil)],
                balances: [], isAvailable: nil, plan: nil, queriedAt: Date(), error: nil
            )),
            WidgetProfileSummary(id: "two", name: "火山方舟", provider: "火山方舟", enabled: true, usage: PlanUsage(
                status: .success,
                tiers: [PlanUsageTier(name: "weekly_limit", utilization: 62, resetsAt: nil, usedValueUSD: nil, maxValueUSD: nil)],
                balances: [], isAvailable: nil, plan: "Coding Plan", queriedAt: Date(), error: nil
            )),
            WidgetProfileSummary(id: "three", name: "DeepSeek 余额", provider: "DeepSeek", enabled: false, usage: .waiting),
        ],
        updatedAt: Date()
    )
}

enum WidgetSnapshotStore {
    static let appGroup = "group.com.xuwenxu.tokenplan"
    private static let snapshotFileName = "widget-snapshot-v3.json"
    private static let snapshotKey = "widget.snapshot.v2"
    private static let legacySnapshotKey = "widget.snapshot.v1"

    private struct LegacyProfile: Codable {
        let id: String
        let name: String
        let provider: String
        let enabled: Bool
    }

    private struct LegacySnapshot: Codable {
        let profiles: [LegacyProfile]
        let updatedAt: Date
    }

    static func save(_ snapshot: TokenPlanWidgetSnapshot) throws {
        guard let container = sharedContainerURL else { throw WidgetSnapshotError.missingAppGroup }
        let data = try JSONEncoder().encode(snapshot)
        let fileURL = container.appendingPathComponent(snapshotFileName, isDirectory: false)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        guard let verified = try? Data(contentsOf: fileURL), decode(verified) == snapshot else {
            throw WidgetSnapshotError.verificationFailed
        }
        UserDefaults(suiteName: appGroup)?.set(data, forKey: snapshotKey)
    }

    static func load() -> TokenPlanWidgetSnapshot {
        guard let container = sharedContainerURL else { return .empty }
        let fileURL = container.appendingPathComponent(snapshotFileName, isDirectory: false)
        if let data = try? Data(contentsOf: fileURL), let snapshot = decode(data) {
            return snapshot
        }
        guard let defaults = UserDefaults(suiteName: appGroup) else { return .empty }
        if let data = defaults.data(forKey: snapshotKey), let snapshot = decode(data) {
            return snapshot
        }
        if let data = defaults.data(forKey: legacySnapshotKey), let snapshot = decode(data) {
            return snapshot
        }
        return .empty
    }

    static var isAppGroupAvailable: Bool { sharedContainerURL != nil }

    static var diagnosticText: String {
        guard isAppGroupAvailable else { return "签名缺少 App Group 权限" }
        let count = load().profiles.count
        return count > 0 ? "已共享 \(count) 个套餐" : "App Group 可用，尚未写入套餐"
    }

    private static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    static func decode(_ data: Data) -> TokenPlanWidgetSnapshot? {
        if let snapshot = try? JSONDecoder().decode(TokenPlanWidgetSnapshot.self, from: data) {
            return snapshot
        }
        guard let legacy = try? JSONDecoder().decode(LegacySnapshot.self, from: data) else {
            return nil
        }
        return TokenPlanWidgetSnapshot(
            profiles: legacy.profiles.map {
                WidgetProfileSummary(
                    id: $0.id,
                    name: $0.name,
                    provider: $0.provider,
                    enabled: $0.enabled,
                    usage: .waiting
                )
            },
            updatedAt: legacy.updatedAt
        )
    }
}

enum WidgetSnapshotError: LocalizedError {
    case missingAppGroup
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .missingAppGroup:
            "小组件无法共享数据：当前签名未包含 App Group \(WidgetSnapshotStore.appGroup)"
        case .verificationFailed:
            "小组件共享数据写入后校验失败"
        }
    }
}
