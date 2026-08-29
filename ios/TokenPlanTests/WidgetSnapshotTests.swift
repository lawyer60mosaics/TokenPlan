import XCTest
@testable import TokenPlan

final class WidgetSnapshotTests: XCTestCase {
    func testCountsAndRoundTrip() throws {
        let snapshot = TokenPlanWidgetSnapshot(
            profiles: [
                WidgetProfileSummary(id: "one", name: "One", provider: "Kimi", enabled: true),
                WidgetProfileSummary(id: "two", name: "Two", provider: "DeepSeek", enabled: false),
            ],
            updatedAt: Date(timeIntervalSince1970: 123)
        )

        XCTAssertEqual(snapshot.enabledCount, 1)
        XCTAssertEqual(snapshot.totalCount, 2)
        XCTAssertEqual(try JSONDecoder().decode(TokenPlanWidgetSnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
    }

    func testSnapshotDoesNotContainCredentials() throws {
        let snapshot = TokenPlanWidgetSnapshot(
            profiles: [WidgetProfileSummary(id: "one", name: "Kimi", provider: "Kimi", enabled: true)],
            updatedAt: Date()
        )
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("api_key"))
        XCTAssertFalse(encoded.contains("access_key"))
        XCTAssertFalse(encoded.contains("secret_key"))
    }
}
