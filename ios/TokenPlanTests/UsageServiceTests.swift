import XCTest
@testable import TokenPlan

final class UsageServiceTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    func testKimiUsageWindows() async throws {
        respond(#"{"limits":[{"detail":{"limit":"100","remaining":"60","resetTime":1700000000}}],"usage":{"limit":200,"remaining":50,"resetTime":1700000000000}}"#)
        let usage = try await UsageService(session: session).query(profile(.kimi))
        XCTAssertEqual(usage.tiers.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(usage.tiers[0].utilization, 40, accuracy: 0.001)
        XCTAssertEqual(usage.tiers[1].utilization, 75, accuracy: 0.001)
    }

    func testZhipuUsesExplicitWindowUnits() async throws {
        respond(#"{"success":true,"data":{"level":"pro","limits":[{"type":"TOKENS_LIMIT","unit":6,"percentage":22,"nextResetTime":1700000000000},{"type":"TOKENS_LIMIT","unit":3,"percentage":11,"nextResetTime":1700100000000}]}}"#)
        let usage = try await UsageService(session: session).query(profile(.zhipu))
        XCTAssertEqual(usage.tiers.map(\.name), ["five_hour", "weekly_limit"])
        XCTAssertEqual(usage.tiers.map(\.utilization), [11, 22])
        XCTAssertEqual(usage.plan, "pro")
    }

    func testMiniMaxRemainingBecomesUsedPercent() async throws {
        respond(#"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","current_interval_remaining_percent":80,"end_time":1700000000000,"current_weekly_status":1,"current_weekly_remaining_percent":25,"weekly_end_time":1700100000000}]}"#)
        let usage = try await UsageService(session: session).query(profile(.minimax))
        XCTAssertEqual(usage.tiers.map(\.utilization), [20, 75])
    }

    func testZenMuxPreservesDollarValues() async throws {
        respond(#"{"success":true,"data":{"quota_5_hour":{"usage_percentage":0.25,"used_value_usd":3,"max_value_usd":12},"quota_7_day":{"usage_percentage":0.5,"used_value_usd":15,"max_value_usd":30},"plan":{"tier":"pro"},"account_status":"active"}}"#)
        var value = profile(.zenmux)
        value.baseURL = "https://api.zenmux.com/v1/usage"
        let usage = try await UsageService(session: session).query(value)
        XCTAssertEqual(usage.tiers.map(\.utilization), [25, 50])
        XCTAssertEqual(usage.tiers[0].maxValueUSD, 12)
        XCTAssertEqual(usage.plan, "pro (active)")
    }

    func testOpenCodeThreeWindows() async throws {
        respond(#"{"usage":{"rolling":{"percent":10,"resetsAt":"2026-08-30T00:00:00Z"},"weekly":{"percent":20,"resetsAt":"2026-09-01T00:00:00Z"},"monthly":{"percent":30,"resetsAt":"2026-09-30T00:00:00Z"}}}"#)
        let usage = try await UsageService(session: session).query(profile(.opencodeGo))
        XCTAssertEqual(usage.tiers.map(\.name), ["five_hour", "weekly_limit", "monthly"])
        XCTAssertEqual(usage.tiers.map(\.utilization), [10, 20, 30])
    }

    func testDeepSeekBalance() async throws {
        respond(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"10.50","granted_balance":"2.00","topped_up_balance":"8.50"}]}"#)
        let usage = try await UsageService(session: session).query(profile(.deepseek))
        XCTAssertEqual(usage.isAvailable, true)
        XCTAssertEqual(usage.balances.first?.totalBalance, "10.50")
    }

    func testVolcengineSignsControlPlaneAndParsesAFP() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.host, "open.volcengineapi.com")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("HMAC-SHA256 Credential=fictional-ak/") == true)
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-Date"))
            return self.response(request, #"{"Result":{"PlanType":"pro","AFPFiveHour":{"Quota":100,"Used":40,"ResetTime":1700000000},"AFPWeekly":{"Quota":200,"Used":50,"ResetTime":1700100000}}}"#)
        }
        var value = profile(.volcengine)
        value.accessKey = "fictional-ak"
        value.secretKey = "fictional-sk"
        let usage = try await UsageService(session: session).query(value)
        XCTAssertEqual(usage.tiers.map(\.utilization), [40, 25])
        XCTAssertEqual(usage.plan, "Agent Plan pro")
    }

    func testZhipuTeamHeaders() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "bigmodel-organization"), "fictional-org")
            XCTAssertEqual(request.value(forHTTPHeaderField: "bigmodel-project"), "fictional-project")
            XCTAssertEqual(request.url?.query, "type=2")
            return self.response(request, #"{"success":true,"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"percentage":10}]}}"#)
        }
        var value = profile(.zhipuTeam)
        value.organizationID = "fictional-org"
        value.projectID = "fictional-project"
        _ = try await UsageService(session: session).query(value)
    }

    private func profile(_ provider: Provider) -> Profile {
        var value = Profile(provider: provider)
        value.apiKey = "fictional-key"
        return value
    }

    private func respond(_ body: String, status: Int = 200) {
        MockURLProtocol.handler = { request in self.response(request, body, status: status) }
    }

    private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(body.utf8))
    }
}
