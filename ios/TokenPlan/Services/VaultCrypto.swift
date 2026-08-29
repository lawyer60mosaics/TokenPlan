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
    static let additionalData = Array("tokenplan-vault-v1".utf8)
    private let sodium = Sodium()

    func generateRecoveryKey() throws -> String {
        guard let key = sodium.randomBytes.buf(length: 32) else {
            throw TokenPlanError.encryptionFailed
        }
        return Base64URL.encode(Data(key))
    }

    func encrypt(_ plaintext: Data, recoveryKey: String) throws -> VaultEnvelope {
        let key = try decodeKey(recoveryKey)
        guard let combined = sodium.aead.xchacha20poly1305ietf.encrypt(
            message: Array(plaintext),
            secretKey: key,
            additionalData: Self.additionalData
        ), combined.count > 24 else {
            throw TokenPlanError.encryptionFailed
        }
        return VaultEnvelope(
            schemaVersion: 1,
            nonce: Base64URL.encode(Data(combined.prefix(24))),
            ciphertext: Base64URL.encode(Data(combined.dropFirst(24)))
        )
    }

    func decrypt(_ envelope: VaultEnvelope, recoveryKey: String) throws -> Data {
        guard envelope.schemaVersion == 1,
              let nonce = Base64URL.decode(envelope.nonce), nonce.count == 24,
              let ciphertext = Base64URL.decode(envelope.ciphertext) else {
            throw TokenPlanError.decryptionFailed
        }
        let key = try decodeKey(recoveryKey)
        guard let plaintext = sodium.aead.xchacha20poly1305ietf.decrypt(
            nonceAndAuthenticatedCipherText: Array(nonce + ciphertext),
            secretKey: key,
            additionalData: Self.additionalData
        ) else {
            throw TokenPlanError.decryptionFailed
        }
        return Data(plaintext)
    }

    private func decodeKey(_ value: String) throws -> [UInt8] {
        guard let data = Base64URL.decode(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              data.count == 32 else {
            throw TokenPlanError.invalidRecoveryKey
        }
        return Array(data)
    }
}
