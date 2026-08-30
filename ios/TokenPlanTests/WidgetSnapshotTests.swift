import XCTest
@testable import TokenPlan

final class WidgetSnapshotTests: XCTestCase {
    func testCountsAndRoundTrip() throws {
        let snapshot = TokenPlanWidgetSnapshot(
            profiles: [
                WidgetProfileSummary(id: "one", name: "One", provider: "Kimi", enabled: true, usage: .waiting),
                WidgetProfileSummary(id: "two", name: "Two", provider: "DeepSeek", enabled: false, usage: .waiting),
            ],
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        XCTAssertEqual(snapshot.enabledCount, 1)
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(try JSONDecoder().decode(TokenPlanWidgetSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testSnapshotDoesNotContainCredentials() throws {
        let snapshot = TokenPlanWidgetSnapshot(
            profiles: [WidgetProfileSummary(id: "one", name: "Kimi", provider: "Kimi", enabled: true, usage: .waiting)],
            updatedAt: Date()
        )
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("api_key"))
        XCTAssertFalse(encoded.contains("access_key"))
        XCTAssertFalse(encoded.contains("secret_key"))
    }

    func testLegacySnapshotMigratesToWaitingUsage() throws {
        struct LegacyProfile: Codable {
            let id: String
            let name: String
            let provider: String
            let enabled: Bool
        }
        struct LegacySnapshot: Codable {
            let profiles: [LegacyProfile]
            let updatedAt: Date
        }

        let data = try JSONEncoder().encode(LegacySnapshot(
            profiles: [LegacyProfile(id: "legacy", name: "Kimi", provider: "Kimi", enabled: true)],
            updatedAt: Date(timeIntervalSince1970: 100)
        ))
        let migrated = try XCTUnwrap(WidgetSnapshotStore.decode(data))

        XCTAssertEqual(migrated.profiles.first?.id, "legacy")
        XCTAssertEqual(migrated.profiles.first?.usage.status, .waiting)
    }

    func testFeaturedProfilePrefersRealUsageDetails() {
        let populated = PlanUsage(
            status: .success,
            tiers: [PlanUsageTier(name: "five_hour", utilization: 42, resetsAt: nil, usedValueUSD: nil, maxValueUSD: nil)],
            balances: [], isAvailable: nil, plan: "Pro", queriedAt: Date(), error: nil
        )
        let snapshot = TokenPlanWidgetSnapshot(
            profiles: [
                WidgetProfileSummary(id: "waiting", name: "Waiting", provider: "Kimi", enabled: true, usage: .waiting),
                WidgetProfileSummary(id: "ready", name: "Ready", provider: "MiniMax", enabled: true, usage: populated),
            ],
            updatedAt: Date()
        )

        XCTAssertEqual(snapshot.featuredProfile?.id, "ready")
        XCTAssertEqual(snapshot.featuredProfile?.usage.headline, "42%")
    }

    func testTierPresentationClampsAndParsesResetTime() {
        let tier = PlanUsageTier(
            name: "weekly_limit",
            utilization: 120,
            resetsAt: "2026-09-01T08:30:00Z",
            usedValueUSD: nil,
            maxValueUSD: nil
        )

        XCTAssertEqual(tier.clampedUtilization, 100)
        XCTAssertEqual(tier.percentageText, "100%")
        XCTAssertNotNil(tier.resetDate)
        XCTAssertNotNil(tier.resetText)
    }
}
