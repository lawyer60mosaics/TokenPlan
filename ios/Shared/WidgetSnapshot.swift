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
    private static let snapshotKey = "widget.snapshot.v1"

    static func save(_ snapshot: TokenPlanWidgetSnapshot) throws {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defaults.set(try JSONEncoder().encode(snapshot), forKey: snapshotKey)
    }

    static func load() -> TokenPlanWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(TokenPlanWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }
}
