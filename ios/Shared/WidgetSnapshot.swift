import Foundation

struct WidgetProfileSummary: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let provider: String
    let enabled: Bool
}

struct TokenPlanWidgetSnapshot: Codable, Hashable {
    let profiles: [WidgetProfileSummary]
    let updatedAt: Date

    var enabledCount: Int { profiles.filter(\.enabled).count }
    var totalCount: Int { profiles.count }

    static let placeholder = TokenPlanWidgetSnapshot(
        profiles: [
            WidgetProfileSummary(id: "one", name: "Kimi For Coding", provider: "Kimi", enabled: true),
            WidgetProfileSummary(id: "two", name: "火山方舟", provider: "火山方舟", enabled: true),
            WidgetProfileSummary(id: "three", name: "DeepSeek 余额", provider: "DeepSeek", enabled: false),
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
            return .placeholder
        }
        return snapshot
    }
}
