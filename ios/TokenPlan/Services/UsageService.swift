import CryptoKit
import Foundation

enum UsageServiceError: LocalizedError {
    case request(String)

    var errorDescription: String? {
        switch self {
        case let .request(message): message
        }
    }
}

struct UsageService {
    private typealias JSON = [String: Any]
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 15
            configuration.urlCache = nil
            self.session = URLSession(configuration: configuration)
        }
    }

    func query(_ profile: Profile) async throws -> PlanUsage {
        try profile.validate()
        guard let provider = Provider(rawValue: profile.provider) else {
            throw UsageServiceError.request("不支持的套餐供应商")
        }
        switch provider {
        case .kimi: return try await queryKimi(profile)
        case .zhipu: return try await queryZhipu(profile, team: false)
        case .zhipuTeam: return try await queryZhipu(profile, team: true)
        case .minimax: return try await queryMiniMax(profile)
        case .zenmux: return try await queryZenMux(profile)
        case .opencodeGo: return try await queryOpenCode(profile)
        case .deepseek: return try await queryDeepSeek(profile)
        case .volcengine: return try await queryVolcengine(profile)
        }
    }

    private func queryKimi(_ profile: Profile) async throws -> PlanUsage {
        let (response, body) = try await jsonRequest(
            "https://api.kimi.com/coding/v1/usages",
            headers: ["Authorization": "Bearer \(profile.apiKey)", "Accept": "application/json"]
        )
        try validate(response)
        var tiers: [PlanUsageTier] = []
        for item in body["limits"] as? [JSON] ?? [] {
            guard let detail = item["detail"] as? JSON else { continue }
            tiers.append(percentTier(
                name: "five_hour",
                limit: number(detail["limit"]) ?? 1,
                remaining: number(detail["remaining"]) ?? 0,
                reset: detail["resetTime"]
            ))
        }
        if let usage = body["usage"] as? JSON {
            tiers.append(percentTier(
                name: "weekly_limit",
                limit: number(usage["limit"]) ?? 1,
                remaining: number(usage["remaining"]) ?? 0,
                reset: usage["resetTime"]
            ))
        }
        return try quota(tiers: tiers)
    }

    private func queryZhipu(_ profile: Profile, team: Bool) async throws -> PlanUsage {
        let host = team || profile.region == "cn" ? "https://open.bigmodel.cn" : "https://api.z.ai"
        var url = "\(host)/api/monitor/usage/quota/limit"
        var headers = [
            "Authorization": profile.apiKey,
            "Content-Type": "application/json",
            "Accept-Language": "en-US,en",
        ]
        if team {
            url += "?type=2"
            headers["bigmodel-organization"] = profile.organizationID
            headers["bigmodel-project"] = profile.projectID
        }
        let (response, body) = try await jsonRequest(url, headers: headers)
        try validate(response)
        if body["success"] as? Bool == false {
            throw UsageServiceError.request("智谱接口返回业务错误")
        }
        guard let data = body["data"] as? JSON else {
            throw UsageServiceError.request("智谱响应缺少套餐数据")
        }
        let tiers = parseZhipu(data)
        return try quota(tiers: tiers, plan: data["level"] as? String)
    }

    private func queryMiniMax(_ profile: Profile) async throws -> PlanUsage {
        let domain = profile.region == "global" ? "api.minimax.io" : "api.minimaxi.com"
        let (response, body) = try await jsonRequest(
            "https://\(domain)/v1/api/openplatform/coding_plan/remains",
            headers: ["Authorization": "Bearer \(profile.apiKey)", "Content-Type": "application/json"]
        )
        try validate(response)
        if let base = body["base_resp"] as? JSON, integer(base["status_code"]) != 0 {
            throw UsageServiceError.request("MiniMax 接口返回业务错误")
        }
        guard let general = (body["model_remains"] as? [JSON])?.first(where: { $0["model_name"] as? String == "general" }) else {
            throw UsageServiceError.request("MiniMax 未返回编程套餐")
        }
        var tiers: [PlanUsageTier] = []
        if let remaining = number(general["current_interval_remaining_percent"]) {
            tiers.append(tier("five_hour", 100 - remaining, general["end_time"]))
        }
        if integer(general["current_weekly_status"]) == 1,
           let remaining = number(general["current_weekly_remaining_percent"]) {
            tiers.append(tier("weekly_limit", 100 - remaining, general["weekly_end_time"]))
        }
        return try quota(tiers: tiers)
    }

    private func queryZenMux(_ profile: Profile) async throws -> PlanUsage {
        guard let components = URLComponents(string: profile.baseURL),
              components.scheme == "https", let host = components.host?.lowercased(),
              host == "zenmux.ai" || host == "zenmux.com" || host.hasSuffix(".zenmux.ai") || host.hasSuffix(".zenmux.com"),
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw UsageServiceError.request("ZenMux 用量地址无效")
        }
        let (response, body) = try await jsonRequest(
            profile.baseURL,
            headers: ["Authorization": "Bearer \(profile.apiKey)", "Accept": "application/json"]
        )
        try validate(response)
        guard body["success"] as? Bool == true, let data = body["data"] as? JSON else {
            throw UsageServiceError.request("ZenMux 未返回套餐数据")
        }
        var tiers: [PlanUsageTier] = []
        for (key, name) in [("quota_5_hour", "five_hour"), ("quota_7_day", "weekly_limit")] {
            guard let window = data[key] as? JSON else { continue }
            tiers.append(PlanUsageTier(
                name: name,
                utilization: (number(window["usage_percentage"]) ?? 0) * 100,
                resetsAt: resetTime(window["resets_at"]),
                usedValueUSD: number(window["used_value_usd"]),
                maxValueUSD: number(window["max_value_usd"])
            ))
        }
        let plan = ((data["plan"] as? JSON)?["tier"] as? String).map {
            let status = data["account_status"] as? String ?? ""
            return status.isEmpty ? $0 : "\($0) (\(status))"
        }
        return try quota(tiers: tiers, plan: plan)
    }

    private func queryOpenCode(_ profile: Profile) async throws -> PlanUsage {
        let (response, body) = try await jsonRequest(
            "https://opencode.ai/zen/go/v1/usage",
            headers: ["Authorization": "Bearer \(profile.apiKey)", "Accept": "application/json"]
        )
        if response.statusCode == 403 {
            throw UsageServiceError.request("API Key 没有 OpenCode Go 套餐")
        }
        try validate(response)
        guard let usage = body["usage"] as? JSON else {
            throw UsageServiceError.request("OpenCode Go 响应格式无法识别")
        }
        var tiers: [PlanUsageTier] = []
        for (key, name) in [("rolling", "five_hour"), ("weekly", "weekly_limit"), ("monthly", "monthly")] {
            guard let window = usage[key] as? JSON, let percent = number(window["percent"]) else { continue }
            tiers.append(PlanUsageTier(
                name: name,
                utilization: percent,
                resetsAt: percent > 0 ? resetTime(window["resetsAt"]) : nil,
                usedValueUSD: nil,
                maxValueUSD: nil
            ))
        }
        return try quota(tiers: tiers)
    }

    private func queryDeepSeek(_ profile: Profile) async throws -> PlanUsage {
        let (response, body) = try await jsonRequest(
            "https://api.deepseek.com/user/balance",
            headers: ["Authorization": "Bearer \(profile.apiKey)"]
        )
        try validate(response)
        guard let available = body["is_available"] as? Bool,
              let rawBalances = body["balance_infos"] as? [JSON], !rawBalances.isEmpty else {
            throw UsageServiceError.request("DeepSeek 余额响应无法识别")
        }
        let balances = try rawBalances.map { value -> PlanBalance in
            guard let currency = value["currency"] as? String,
                  ["CNY", "USD"].contains(currency),
                  let total = value["total_balance"] as? String,
                  let granted = value["granted_balance"] as? String,
                  let topped = value["topped_up_balance"] as? String,
                  Decimal(string: total) != nil, Decimal(string: granted) != nil, Decimal(string: topped) != nil else {
                throw UsageServiceError.request("DeepSeek 余额响应无法识别")
            }
            return PlanBalance(currency: currency, totalBalance: total, grantedBalance: granted, toppedUpBalance: topped)
        }
        return PlanUsage(
            status: .success, tiers: [], balances: balances, isAvailable: available,
            plan: nil, queriedAt: Date(), error: nil
        )
    }

    private func queryVolcengine(_ profile: Profile) async throws -> PlanUsage {
        let region = "cn-beijing"
        var errors: [String] = []
        for action in ["GetAFPUsage", "GetCodingPlanUsage"] {
            do {
                let body = try await volcengineCall(profile, region: region, action: action)
                let result = body["Result"] as? JSON ?? body
                let tiers = action == "GetAFPUsage" ? parseAFP(result) : parseCodingPlan(result)
                if !tiers.isEmpty {
                    let plan: String?
                    if action == "GetAFPUsage", let type = result["PlanType"] as? String, !type.isEmpty {
                        plan = "Agent Plan \(type)"
                    } else {
                        plan = action == "GetCodingPlanUsage" ? "Coding Plan" : "Agent Plan"
                    }
                    return try quota(tiers: tiers, plan: plan)
                }
            } catch {
                errors.append(error.localizedDescription)
            }
        }
        throw UsageServiceError.request(errors.first ?? "未找到火山方舟有效套餐")
    }

    private func volcengineCall(_ profile: Profile, region: String, action: String) async throws -> JSON {
        let query = "Action=\(action)&Region=\(region)&Version=2024-01-01"
        let body = Data()
        let signed = volcengineHeaders(
            accessKey: profile.accessKey,
            secretKey: profile.secretKey,
            region: region,
            query: query,
            body: body,
            date: Date()
        )
        let (response, json) = try await jsonRequest(
            "https://open.volcengineapi.com/?\(query)",
            method: "POST",
            headers: signed,
            body: body
        )
        try validate(response)
        if let metadata = json["ResponseMetadata"] as? JSON,
           let error = metadata["Error"] as? JSON {
            let code = error["Code"] as? String ?? ""
            throw UsageServiceError.request(code.lowercased().contains("auth") ? "火山方舟 AK/SK 鉴权失败" : "火山方舟接口返回错误")
        }
        return json
    }

    private func parseAFP(_ result: JSON) -> [PlanUsageTier] {
        [("AFPFiveHour", "five_hour"), ("AFPWeekly", "weekly_limit"), ("AFPMonthly", "monthly")].compactMap { key, name in
            guard let window = result[key] as? JSON, let quota = number(window["Quota"]), quota > 0 else { return nil }
            return PlanUsageTier(
                name: name,
                utilization: (number(window["Used"]) ?? 0) / quota * 100,
                resetsAt: resetTime(window["ResetTime"]),
                usedValueUSD: nil,
                maxValueUSD: nil
            )
        }
    }

    private func parseCodingPlan(_ result: JSON) -> [PlanUsageTier] {
        let values = result["QuotaUsage"] as? [JSON] ?? result["Usages"] as? [JSON] ?? result["Details"] as? [JSON] ?? []
        return values.compactMap { item in
            let raw = (item["Level"] ?? item["Type"] ?? item["Period"] ?? item["Label"] ?? item["Window"]) as? String ?? ""
            let name: String
            switch raw.lowercased() {
            case "session", "5h", "fivehour", "five_hour", "rolling_5h": name = "five_hour"
            case "weekly", "week", "7d": name = "weekly_limit"
            case "monthly", "month": name = "monthly"
            default: return nil
            }
            return PlanUsageTier(
                name: name,
                utilization: number(item["Percent"] ?? item["UsedPercent"] ?? item["UsagePercent"]) ?? 0,
                resetsAt: resetTime(item["ResetTime"] ?? item["ResetTimestamp"]),
                usedValueUSD: nil,
                maxValueUSD: nil
            )
        }
    }

    private func parseZhipu(_ data: JSON) -> [PlanUsageTier] {
        typealias Entry = (unit: Int?, percent: Double, reset: String?)
        var five: Entry?
        var weekly: Entry?
        var other: [Entry] = []
        for item in data["limits"] as? [JSON] ?? [] {
            let type = (item["type"] as? String ?? "").uppercased()
            guard type == "TOKENS_LIMIT" || type == "CREDIT_LIMIT" else { continue }
            let entry: Entry = (
                unit: integer(item["unit"]),
                percent: number(item["percentage"]) ?? 0,
                reset: resetTime(item["nextResetTime"])
            )
            if entry.unit == 3, five == nil { five = entry }
            else if entry.unit == 6, weekly == nil { weekly = entry }
            else { other.append(entry) }
        }
        other.sort {
            if ($0.reset == nil) != ($1.reset == nil) { return $0.reset == nil }
            return ($0.reset ?? "") < ($1.reset ?? "")
        }
        for entry in other {
            if five == nil { five = entry }
            else if weekly == nil { weekly = entry }
        }
        return [("five_hour", five), ("weekly_limit", weekly)].compactMap { name, entry in
            entry.map { PlanUsageTier(name: name, utilization: $0.percent, resetsAt: $0.reset, usedValueUSD: nil, maxValueUSD: nil) }
        }
    }

    private func quota(tiers: [PlanUsageTier], plan: String? = nil) throws -> PlanUsage {
        guard !tiers.isEmpty else { throw UsageServiceError.request("未找到有效套餐周期") }
        return PlanUsage(
            status: .success,
            tiers: tiers,
            balances: [],
            isAvailable: nil,
            plan: plan,
            queriedAt: Date(),
            error: nil
        )
    }

    private func percentTier(name: String, limit: Double, remaining: Double, reset: Any?) -> PlanUsageTier {
        let used = max(limit - remaining, 0)
        return PlanUsageTier(
            name: name,
            utilization: limit > 0 ? used / limit * 100 : 0,
            resetsAt: resetTime(reset),
            usedValueUSD: nil,
            maxValueUSD: nil
        )
    }

    private func tier(_ name: String, _ utilization: Double, _ reset: Any?) -> PlanUsageTier {
        PlanUsageTier(name: name, utilization: utilization, resetsAt: resetTime(reset), usedValueUSD: nil, maxValueUSD: nil)
    }

    private func jsonRequest(
        _ url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> (HTTPURLResponse, JSON) {
        guard let url = URL(string: url) else { throw UsageServiceError.request("查询地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.httpBody = body
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, rawResponse) = try await session.data(for: request)
        guard let response = rawResponse as? HTTPURLResponse else { throw UsageServiceError.request("供应商响应无效") }
        let object = (try? JSONSerialization.jsonObject(with: data)) as? JSON ?? [:]
        return (response, object)
    }

    private func validate(_ response: HTTPURLResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message: String
            switch response.statusCode {
            case 401, 403: message = "套餐凭据被供应商拒绝"
            case 429: message = "请求过于频繁，请稍后重试"
            default: message = "套餐查询失败（HTTP \(response.statusCode)）"
            }
            throw UsageServiceError.request(message)
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func resetTime(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        guard let number = number(value), number > 0 else { return nil }
        let seconds = number >= 1_000_000_000_000 ? number / 1000 : number
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }

    private func volcengineHeaders(
        accessKey: String,
        secretKey: String,
        region: String,
        query: String,
        body: Data,
        date: Date
    ) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let xDate = formatter.string(from: date)
        formatter.dateFormat = "yyyyMMdd"
        let shortDate = formatter.string(from: date)
        let contentHash = SHA256.hash(data: body).hex
        let contentType = "application/json; charset=utf-8"
        let signedHeaders = "host;x-date;x-content-sha256;content-type"
        let canonicalHeaders = "host:open.volcengineapi.com\nx-date:\(xDate)\nx-content-sha256:\(contentHash)\ncontent-type:\(contentType)\n"
        let canonicalRequest = "POST\n/\n\(query)\n\(canonicalHeaders)\n\(signedHeaders)\n\(contentHash)"
        let scope = "\(shortDate)/\(region)/ark/request"
        let requestHash = SHA256.hash(data: Data(canonicalRequest.utf8)).hex
        let stringToSign = "HMAC-SHA256\n\(xDate)\n\(scope)\n\(requestHash)"
        let kDate = hmac(key: Data(secretKey.utf8), value: shortDate)
        let kRegion = hmac(key: kDate, value: region)
        let kService = hmac(key: kRegion, value: "ark")
        let kSigning = hmac(key: kService, value: "request")
        let signature = hmac(key: kSigning, value: stringToSign).hex
        return [
            "X-Date": xDate,
            "X-Content-Sha256": contentHash,
            "Content-Type": contentType,
            "Authorization": "HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
        ]
    }

    private func hmac(key: Data, value: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
    }
}

private extension Sequence where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
