import Foundation
import Sodium

struct VaultEnvelope: Codable, Equatable {
    let schemaVersion: UInt32
    let nonce: String
    let ciphertext: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case nonce, ciphertext
    }
}

struct VaultCrypto {
    static let additionalData = Array("tokenplan-vault-v2".utf8)
    private let sodium = Sodium()

    func encrypt(_ plaintext: Data, username: String, password: String) throws -> VaultEnvelope {
        try encrypt(plaintext, key: SyncCredentials.vaultKey(username: username, password: password))
    }

    func encrypt(_ plaintext: Data, key: [UInt8]) throws -> VaultEnvelope {
        guard key.count == 32 else { throw TokenPlanError.encryptionFailed }
        guard let combined: [UInt8] = sodium.aead.xchacha20poly1305ietf.encrypt(
            message: Array(plaintext),
            secretKey: key,
            additionalData: Self.additionalData
        ), combined.count > 24 else {
            throw TokenPlanError.encryptionFailed
        }
        return VaultEnvelope(
            schemaVersion: 2,
            nonce: Base64URL.encode(Data(combined.prefix(24))),
            ciphertext: Base64URL.encode(Data(combined.dropFirst(24)))
        )
    }

    func decrypt(_ envelope: VaultEnvelope, username: String, password: String) throws -> Data {
        try decrypt(envelope, key: SyncCredentials.vaultKey(username: username, password: password))
    }

    func decrypt(_ envelope: VaultEnvelope, key: [UInt8]) throws -> Data {
        guard envelope.schemaVersion == 2,
              let nonce = Base64URL.decode(envelope.nonce), nonce.count == 24,
              let ciphertext = Base64URL.decode(envelope.ciphertext), key.count == 32 else {
            throw TokenPlanError.decryptionFailed
        }
        guard let plaintext = sodium.aead.xchacha20poly1305ietf.decrypt(
            nonceAndAuthenticatedCipherText: Array(nonce + ciphertext),
            secretKey: key,
            additionalData: Self.additionalData
        ) else {
            throw TokenPlanError.decryptionFailed
        }
        return Data(plaintext)
    }

}
