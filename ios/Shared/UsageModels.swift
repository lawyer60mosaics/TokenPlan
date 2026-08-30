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

    var clampedUtilization: Double { min(max(utilization, 0), 100) }

    var percentageText: String { "\(Int(clampedUtilization.rounded()))%" }

    var resetDate: Date? {
        guard let resetsAt, !resetsAt.isEmpty else { return nil }
        if let numeric = Double(resetsAt) {
            return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1_000 : numeric)
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: resetsAt)
    }

    var resetText: String? {
        guard let resetDate else { return nil }
        return "\(resetDate.formatted(.dateTime.month(.abbreviated).day().hour().minute())) 重置"
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

    var hasDetails: Bool { !tiers.isEmpty || !balances.isEmpty }

    var primaryTier: PlanUsageTier? { tiers.first }

    var headline: String {
        if let balance = balances.first {
            return "\(balance.currency) \(balance.totalBalance)"
        }
        if let tier = tiers.first { return tier.percentageText }
        switch status {
        case .loading: return "刷新中"
        case .failed: return "刷新失败"
        case .paused: return "已暂停"
        case .success: return "已更新"
        case .waiting: return "等待刷新"
        }
    }

    var compactDetail: String {
        if let balance = balances.first {
            return "\(balance.currency) 余额 \(balance.totalBalance)"
        }
        return tiers.prefix(2)
            .map { "\($0.title) \($0.percentageText)" }
            .joined(separator: " · ")
    }
}
