import XCTest
@testable import TokenPlan

final class VaultCryptoTests: XCTestCase {
    func testRoundTripAndWrongKeyFails() throws {
        let crypto = VaultCrypto()
        let key = try crypto.generateRecoveryKey()
        let plaintext = Data(#"[{"api_key":"fictional"}]"#.utf8)
        let envelope = try crypto.encrypt(plaintext, recoveryKey: key)

        XCTAssertEqual(envelope.schemaVersion, 1)
        XCTAssertFalse(envelope.ciphertext.contains("fictional"))
        XCTAssertEqual(try crypto.decrypt(envelope, recoveryKey: key), plaintext)
        XCTAssertThrowsError(try crypto.decrypt(envelope, recoveryKey: crypto.generateRecoveryKey()))
    }

    func testBase64URLHasNoPadding() throws {
        let key = try VaultCrypto().generateRecoveryKey()
        XCTAssertEqual(Base64URL.decode(key)?.count, 32)
        XCTAssertFalse(key.contains("="))
        XCTAssertFalse(key.contains("+"))
        XCTAssertFalse(key.contains("/"))
    }

    func testDecryptsRustCryptoCompatibilityVector() throws {
        let envelope = VaultEnvelope(
            schemaVersion: 1,
            nonce: "CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJ",
            ciphertext: "5QnA4xiIQ0CSe3BIHQFiyQbR1uopPvaE368ifrVPMC_rRS66vqnICfd2XXcCwjHCI4RTXMIszKE"
        )
        let key = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc"
        let expected = Data(#"[{"id":"fixture","api_key":"fictional"}]"#.utf8)
        XCTAssertEqual(try VaultCrypto().decrypt(envelope, recoveryKey: key), expected)
    }
}
