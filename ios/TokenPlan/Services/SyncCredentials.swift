import CryptoKit
import Foundation

enum SyncCredentials {
    static let endpoint = URL(string: "https://47.102.119.11")!

    static func validate(username: String, password: String) throws {
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-@"))
        guard (3...64).contains(account.count),
              account.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              (16...128).contains(password.count) else {
            throw TokenPlanError.missingCredentials
        }
    }

    static func authToken(username: String, password: String) -> String {
        Base64URL.encode(derive(domain: "tokenplan-auth-v2", username: username, password: password))
    }

    static func vaultKey(username: String, password: String) -> [UInt8] {
        Array(derive(domain: "tokenplan-vault-v2", username: username, password: password))
    }

    private static func derive(domain: String, username: String, password: String) -> Data {
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var input = Data(domain.utf8)
        input.append(0)
        input.append(contentsOf: account.utf8)
        input.append(0)
        input.append(contentsOf: password.utf8)
        return Data(SHA256.hash(data: input))
    }
}
