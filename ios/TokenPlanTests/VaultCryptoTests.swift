import XCTest
@testable import TokenPlan

final class VaultCryptoTests: XCTestCase {
    func testRoundTripAndWrongKeyFails() throws {
        let crypto = VaultCrypto()
        let username = "tokenplan"
        let password = "correct-horse-1234"
        let plaintext = Data(#"[{"api_key":"fictional"}]"#.utf8)
        let envelope = try crypto.encrypt(plaintext, username: username, password: password)

        XCTAssertEqual(envelope.schemaVersion, 2)
        XCTAssertFalse(envelope.ciphertext.contains("fictional"))
        XCTAssertEqual(try crypto.decrypt(envelope, username: username, password: password), plaintext)
        XCTAssertThrowsError(try crypto.decrypt(envelope, username: username, password: "different-password-1"))
    }

    func testCredentialDerivationMatchesRust() throws {
        let token = SyncCredentials.authToken(username: "tokenplan", password: "correct-horse-1234")
        let key = Base64URL.encode(Data(SyncCredentials.vaultKey(username: "tokenplan", password: "correct-horse-1234")))
        XCTAssertEqual(token, "oNgFfFG1T4-ATA1kPkTCHqMSqXyDfZraNWRv4l0vNBY")
        XCTAssertEqual(key, "KP7wj6TG07KvuvKeUYT1mdQY4L361j-GJxg5V3Iu0Sk")
        XCTAssertNotEqual(token, key)
    }

    func testDecryptsRustCryptoCompatibilityVector() throws {
        let envelope = VaultEnvelope(
            schemaVersion: 2,
            nonce: "CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJ",
            ciphertext: "5QnA4xiIQ0CSe3BIHQFiyQbR1uopPvaE368ifrVPMC_rRS66vqnICUBFvZYuG0oyxMEcQJnVQxo"
        )
        let key = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc"
        let expected = Data(#"[{"id":"fixture","api_key":"fictional"}]"#.utf8)
        XCTAssertEqual(try VaultCrypto().decrypt(envelope, key: Array(try XCTUnwrap(Base64URL.decode(key)))), expected)
    }
}
