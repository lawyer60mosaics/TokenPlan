import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct TokenPlanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let enabledCount: Int
        let totalCount: Int
        let primaryName: String
        let updatedAt: Date
    }

    let title: String
}
