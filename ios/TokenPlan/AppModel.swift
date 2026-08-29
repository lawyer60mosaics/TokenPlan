import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var endpoint = "https://47.102.119.11"
    @Published var token = ""
    @Published var recoveryKey = ""
    @Published var revision: UInt64 = 0
    @Published var isSyncConfigured = false
    @Published var isBusy = false
    @Published var message = ""
    @Published var errorMessage = ""

    private let profileStore = ProfileStore()
    private let secretStore: SecretStoring
    private let crypto = VaultCrypto()
    private let defaults: UserDefaults

    init(secretStore: SecretStoring = KeychainStore(), defaults: UserDefaults = .standard) {
        self.secretStore = secretStore
        self.defaults = defaults
        do {
            profiles = try profileStore.load()
            endpoint = defaults.string(forKey: "sync.endpoint") ?? endpoint
            revision = UInt64(defaults.integer(forKey: "sync.revision"))
            token = try secretStore.read("token") ?? ""
            recoveryKey = try secretStore.read("vault-key") ?? ""
            isSyncConfigured = !token.isEmpty && !recoveryKey.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save(_ profile: Profile) async {
        clearStatus()
        do {
            try profile.validate()
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = profile
            } else {
                profiles.append(profile)
            }
            try profileStore.save(profiles)
            message = "已保存"
            if isSyncConfigured { await push() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) async {
        profiles.remove(atOffsets: offsets)
        do {
            try profileStore.save(profiles)
            if isSyncConfigured { await push() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configure() async {
        guard !isBusy else { return }
        clearStatus()
        isBusy = true
        defer { isBusy = false }
        do {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedToken.count >= 32 else { throw TokenPlanError.missingCredentials }
            _ = try SyncClient(endpoint: endpoint, token: trimmedToken)
            let key = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? try crypto.generateRecoveryKey()
                : recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try crypto.encrypt(Data(), recoveryKey: key)
            try secretStore.write(trimmedToken, account: "token")
            try secretStore.write(key, account: "vault-key")
            token = trimmedToken
            recoveryKey = key
            defaults.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "sync.endpoint")
            isSyncConfigured = true
            message = "同步已配置，请离线保存恢复密钥"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pull() async {
        guard !isBusy else { return }
        clearStatus()
        isBusy = true
        defer { isBusy = false }
        do {
            let client = try configuredClient()
            let vault = try await client.pull()
            let data = try crypto.decrypt(vault.envelope, recoveryKey: recoveryKey)
            let downloaded = try JSONDecoder().decode([Profile].self, from: data)
            try profileStore.validate(downloaded)
            try profileStore.save(downloaded)
            profiles = downloaded
            setRevision(vault.revision)
            message = "已下载云端配置"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func push() async {
        guard !isBusy else { return }
        clearStatus()
        isBusy = true
        defer { isBusy = false }
        do {
            try profileStore.validate(profiles)
            let data = try JSONEncoder().encode(profiles)
            let envelope = try crypto.encrypt(data, recoveryKey: recoveryKey)
            let nextRevision = try await configuredClient().push(envelope, revision: revision)
            setRevision(nextRevision)
            message = "已上传加密配置"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disableSync() {
        clearStatus()
        do {
            try secretStore.delete("token")
            try secretStore.delete("vault-key")
            defaults.removeObject(forKey: "sync.endpoint")
            defaults.removeObject(forKey: "sync.revision")
            token = ""
            recoveryKey = ""
            revision = 0
            isSyncConfigured = false
            message = "已停用云同步，本地套餐未删除"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configuredClient() throws -> SyncClient {
        guard isSyncConfigured, !token.isEmpty, !recoveryKey.isEmpty else {
            throw TokenPlanError.missingCredentials
        }
        return try SyncClient(endpoint: endpoint, token: token)
    }

    private func setRevision(_ value: UInt64) {
        revision = value
        defaults.set(Int(value), forKey: "sync.revision")
    }

    private func clearStatus() {
        message = ""
        errorMessage = ""
    }
}
