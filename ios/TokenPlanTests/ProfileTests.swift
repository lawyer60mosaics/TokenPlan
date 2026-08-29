import XCTest
@testable import TokenPlan

final class ProfileTests: XCTestCase {
    func testWindowsProfileJSONRoundTrip() throws {
        let json = #"[{"id":"fixture","name":"Kimi","provider":"kimi","type":"auto","access_key":"","secret_key":"","api_key":"fictional","region":"cn","base_url":"","organization_id":"","project_id":"","enabled":true}]"#
        let profiles = try JSONDecoder().decode([Profile].self, from: Data(json.utf8))
        XCTAssertEqual(profiles.first?.apiKey, "fictional")
        let encoded = String(decoding: try JSONEncoder().encode(profiles), as: UTF8.self)
        XCTAssertTrue(encoded.contains("\"api_key\":\"fictional\""))
        XCTAssertFalse(encoded.contains("apiKey"))
    }

    func testDuplicateIDsAreRejected() throws {
        var profile = Profile(provider: .kimi)
        profile.enabled = false
        XCTAssertThrowsError(try ProfileStore().validate([profile, profile]))
    }

    func testEnabledProfileRequiresCredentials() {
        XCTAssertThrowsError(try Profile(provider: .volcengine).validate())
        XCTAssertThrowsError(try Profile(provider: .kimi).validate())
    }

    func testZenMuxRejectsMisleadingHost() {
        var profile = Profile(provider: .zenmux)
        profile.apiKey = "fictional"
        profile.baseURL = "https://zenmux.ai.evil.example/usage"
        XCTAssertThrowsError(try profile.validate())
    }
}
