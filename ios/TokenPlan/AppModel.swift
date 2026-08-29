import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var username = ""
    @Published var password = ""
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
            revision = UInt64(defaults.integer(forKey: "sync.revision"))
            username = try secretStore.read("username") ?? ""
            password = try secretStore.read("password") ?? ""
            isSyncConfigured = !username.isEmpty && !password.isEmpty
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
            let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
            try SyncCredentials.validate(username: account, password: password)
            _ = try SyncClient(username: account, password: password)
            _ = try crypto.encrypt(Data(), username: account, password: password)
            try secretStore.write(account, account: "username")
            try secretStore.write(password, account: "password")
            try? secretStore.delete("token")
            try? secretStore.delete("vault-key")
            username = account
            isSyncConfigured = true
            message = "云同步账号密码已保存"
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
            let data = try crypto.decrypt(vault.envelope, username: username, password: password)
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
            let envelope = try crypto.encrypt(data, username: username, password: password)
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
            try secretStore.delete("username")
            try secretStore.delete("password")
            try? secretStore.delete("token")
            try? secretStore.delete("vault-key")
            defaults.removeObject(forKey: "sync.endpoint")
            defaults.removeObject(forKey: "sync.revision")
            username = ""
            password = ""
            revision = 0
            isSyncConfigured = false
            message = "已停用云同步，本地套餐未删除"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func configuredClient() throws -> SyncClient {
        guard isSyncConfigured, !username.isEmpty, !password.isEmpty else {
            throw TokenPlanError.missingCredentials
        }
        return try SyncClient(username: username, password: password)
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
