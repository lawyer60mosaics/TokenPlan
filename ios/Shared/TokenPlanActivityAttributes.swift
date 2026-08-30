import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct TokenPlanActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let enabledCount: Int
        let totalCount: Int
        let primaryName: String
        let primaryDetail: String
        let updatedAt: Date
    }

    let title: String
}
