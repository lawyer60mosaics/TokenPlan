import Foundation

enum PlanUsageStatus: String, Codable, Hashable, Sendable {
    case waiting
    case loading
    case success
    case failed
    case paused
}

struct PlanUsageTier: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let utilization: Double
    let resetsAt: String?
    let usedValueUSD: Double?
    let maxValueUSD: Double?

    var title: String {
        switch name {
        case "five_hour": "5 小时"
        case "weekly_limit": "近 1 周"
        case "monthly": "近 1 月"
        default: name
        }
    }
}

struct PlanBalance: Codable, Hashable, Identifiable, Sendable {
    var id: String { currency }
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String
}

struct PlanUsage: Codable, Hashable, Sendable {
    let status: PlanUsageStatus
    let tiers: [PlanUsageTier]
    let balances: [PlanBalance]
    let isAvailable: Bool?
    let plan: String?
    let queriedAt: Date?
    let error: String?

    static let waiting = PlanUsage(
        status: .waiting,
        tiers: [],
        balances: [],
        isAvailable: nil,
        plan: nil,
        queriedAt: nil,
        error: nil
    )
}
