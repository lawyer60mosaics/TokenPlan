import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var username = ""
    @Published var password = ""
    @Published var revision: UInt64 = 0
    @Published var isSyncConfigured = false
    @Published var isBusy = false
    @Published var isLiveActivityActive = false
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
            publishWidgetSnapshot()
            if #available(iOS 16.1, *) {
                isLiveActivityActive = !Activity<TokenPlanActivityAttributes>.activities.isEmpty
            }
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
            publishWidgetSnapshot()
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
            publishWidgetSnapshot()
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
            publishWidgetSnapshot()
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

    func startLiveActivity() async {
        clearStatus()
        guard #available(iOS 16.1, *) else {
            errorMessage = "灵动岛需要 iOS 16.1 或更高版本"
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            errorMessage = "请在系统设置中允许实时活动"
            return
        }
        do {
            let state = activityState()
            if #available(iOS 16.2, *) {
                _ = try Activity.request(
                    attributes: TokenPlanActivityAttributes(title: "TokenPlan"),
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
            } else {
                _ = try Activity.request(
                    attributes: TokenPlanActivityAttributes(title: "TokenPlan"),
                    contentState: state,
                    pushType: nil
                )
            }
            isLiveActivityActive = true
            message = "灵动岛实时活动已启动"
        } catch {
            errorMessage = "无法启动灵动岛：\(error.localizedDescription)"
        }
    }

    func endLiveActivity() async {
        clearStatus()
        guard #available(iOS 16.1, *) else { return }
        let state = activityState()
        for activity in Activity<TokenPlanActivityAttributes>.activities {
            if #available(iOS 16.2, *) {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            } else {
                await activity.end(using: state, dismissalPolicy: .immediate)
            }
        }
        isLiveActivityActive = false
        message = "灵动岛实时活动已结束"
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

    private func publishWidgetSnapshot() {
        let snapshot = TokenPlanWidgetSnapshot(
            profiles: profiles.map {
                WidgetProfileSummary(
                    id: $0.id,
                    name: $0.name,
                    provider: Provider(rawValue: $0.provider)?.title ?? $0.provider,
                    enabled: $0.enabled
                )
            },
            updatedAt: Date()
        )
        try? WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        updateLiveActivities(with: snapshot)
    }

    @available(iOS 16.1, *)
    private func activityState(from snapshot: TokenPlanWidgetSnapshot? = nil) -> TokenPlanActivityAttributes.ContentState {
        let snapshot = snapshot ?? TokenPlanWidgetSnapshot(
            profiles: profiles.map {
                WidgetProfileSummary(id: $0.id, name: $0.name, provider: $0.provider, enabled: $0.enabled)
            },
            updatedAt: Date()
        )
        return TokenPlanActivityAttributes.ContentState(
            enabledCount: snapshot.enabledCount,
            totalCount: snapshot.totalCount,
            primaryName: snapshot.profiles.first(where: { $0.enabled })?.name ?? "尚无启用套餐",
            updatedAt: snapshot.updatedAt
        )
    }

    private func updateLiveActivities(with snapshot: TokenPlanWidgetSnapshot) {
        guard #available(iOS 16.1, *) else { return }
        let state = activityState(from: snapshot)
        Task {
            for activity in Activity<TokenPlanActivityAttributes>.activities {
                if #available(iOS 16.2, *) {
                    await activity.update(ActivityContent(state: state, staleDate: nil))
                } else {
                    await activity.update(using: state)
                }
            }
            isLiveActivityActive = !Activity<TokenPlanActivityAttributes>.activities.isEmpty
        }
    }

    private func clearStatus() {
        message = ""
        errorMessage = ""
    }
}
