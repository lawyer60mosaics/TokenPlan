import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var usageByProfile: [String: PlanUsage] = [:]
    @Published var username = ""
    @Published var password = ""
    @Published var revision: UInt64 = 0
    @Published var isSyncConfigured = false
    @Published var isBusy = false
    @Published var isRefreshing = false
    @Published var isLiveActivityActive = false
    @Published var isWidgetSharingAvailable = false
    @Published var widgetSharingStatus = "检测中"
    @Published var prewarmState: PrewarmState?
    @Published var prewarmEnabled = false
    @Published var prewarmModel = "ark-code-latest"
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
            let cached = WidgetSnapshotStore.load()
            usageByProfile = Dictionary(uniqueKeysWithValues: cached.profiles
                .filter { profile in profiles.contains(where: { $0.id == profile.id }) }
                .map { ($0.id, $0.usage) })
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
            usageByProfile[profile.id] = usageByProfile[profile.id] ?? .waiting
            publishWidgetSnapshot()
            message = "已保存"
            if isSyncConfigured { await push() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) async {
        profiles.remove(atOffsets: offsets)
        let validIDs = Set(profiles.map(\.id))
        usageByProfile = usageByProfile.filter { validIDs.contains($0.key) }
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
            let validIDs = Set(downloaded.map(\.id))
            usageByProfile = usageByProfile.filter { validIDs.contains($0.key) }
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

    @discardableResult
    func changeSyncPassword(currentPassword: String, newPassword: String, confirmation: String) async -> Bool {
        guard !isBusy else { return false }
        clearStatus()
        guard isSyncConfigured else {
            errorMessage = "请先配置云同步"
            return false
        }
        guard newPassword == confirmation else {
            errorMessage = "两次输入的新密码不一致"
            return false
        }
        guard currentPassword != newPassword else {
            errorMessage = "新密码不能与当前密码相同"
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let account = try secretStore.read("username") ?? username
            try SyncCredentials.validate(username: account, password: currentPassword)
            try SyncCredentials.validate(username: account, password: newPassword)
            let currentClient = try SyncClient(username: account, password: currentPassword)
            let vault = try await currentClient.pull()
            let plaintext = try crypto.decrypt(vault.envelope, username: account, password: currentPassword)
            let downloaded = try JSONDecoder().decode([Profile].self, from: plaintext)
            try profileStore.validate(downloaded)

            _ = try SyncClient(username: account, password: newPassword)
            let nextEnvelope = try crypto.encrypt(plaintext, username: account, password: newPassword)
            let nextToken = SyncCredentials.authToken(username: account, password: newPassword)
            try secretStore.write(newPassword, account: "password-change-check")
            try secretStore.delete("password-change-check")
            let nextRevision = try await currentClient.rotateCredentials(
                newToken: nextToken,
                envelope: nextEnvelope,
                revision: vault.revision
            )

            try secretStore.write(newPassword, account: "password")
            username = account
            password = newPassword
            setRevision(nextRevision)
            message = "同步密码修改成功，其他设备需要重新登录"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let targets = profiles.filter(\.enabled)
        for profile in profiles where !profile.enabled {
            usageByProfile[profile.id] = PlanUsage(
                status: .paused, tiers: [], balances: [], isAvailable: nil,
                plan: nil, queriedAt: usageByProfile[profile.id]?.queriedAt, error: nil
            )
        }
        await withTaskGroup(of: (String, PlanUsage?, String?).self) { group in
            for profile in targets {
                let previous = usageByProfile[profile.id] ?? .waiting
                usageByProfile[profile.id] = PlanUsage(
                    status: .loading,
                    tiers: previous.tiers,
                    balances: previous.balances,
                    isAvailable: previous.isAvailable,
                    plan: previous.plan,
                    queriedAt: previous.queriedAt,
                    error: nil
                )
                group.addTask {
                    do { return (profile.id, try await UsageService().query(profile), nil) }
                    catch { return (profile.id, nil, error.localizedDescription) }
                }
            }
            publishWidgetSnapshot()
            for await (id, usage, failure) in group {
                if let usage {
                    usageByProfile[id] = usage
                } else {
                    let previous = usageByProfile[id] ?? .waiting
                    usageByProfile[id] = PlanUsage(
                        status: .failed,
                        tiers: previous.tiers,
                        balances: previous.balances,
                        isAvailable: previous.isAvailable,
                        plan: previous.plan,
                        queriedAt: previous.queriedAt,
                        error: String((failure ?? "套餐查询失败").prefix(300))
                    )
                }
                publishWidgetSnapshot()
            }
        }
        message = "套餐用量已刷新"
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

    func loadPrewarm() async {
        guard isSyncConfigured, !isBusy else { return }
        clearStatus()
        isBusy = true
        defer { isBusy = false }
        do {
            let state = try await configuredClient().getPrewarm()
            prewarmState = state
            prewarmEnabled = state.enabled
            prewarmModel = state.model
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePrewarm(apiKey: String) async -> Bool {
        guard isSyncConfigured, !isBusy else { return false }
        clearStatus()
        isBusy = true
        defer { isBusy = false }
        do {
            let state = try await configuredClient().savePrewarm(
                enabled: prewarmEnabled,
                apiKey: apiKey,
                model: prewarmModel
            )
            prewarmState = state
            message = "配额预热设置已保存"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func runPrewarm() async {
        guard isSyncConfigured, !isBusy else { return }
        clearStatus()
        isBusy = true
        defer { isBusy = false }
        do {
            let run = try await configuredClient().runPrewarm()
            if let current = prewarmState {
                prewarmState = PrewarmState(
                    enabled: current.enabled,
                    model: current.model,
                    schedule: current.schedule,
                    timezone: current.timezone,
                    hasAPIKey: current.hasAPIKey,
                    lastRun: run
                )
            }
            if run.success {
                message = "配额预热成功"
            } else {
                errorMessage = "配额预热失败：\(run.error ?? "未知错误")"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func repairWidgetSharing() {
        clearStatus()
        publishWidgetSnapshot()
        if isWidgetSharingAvailable {
            message = "已重新写入小组件套餐数据"
        } else {
            errorMessage = "当前 IPA 签名缺少 App Group \(WidgetSnapshotStore.appGroup)，请使用包含该权限的证书同时重签主程序和小组件扩展"
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
                    enabled: $0.enabled,
                    usage: usageByProfile[$0.id] ?? .waiting
                )
            },
            updatedAt: Date()
        )
        do {
            try WidgetSnapshotStore.save(snapshot)
            isWidgetSharingAvailable = true
            widgetSharingStatus = WidgetSnapshotStore.diagnosticText
        } catch {
            isWidgetSharingAvailable = false
            widgetSharingStatus = error.localizedDescription
        }
        WidgetCenter.shared.reloadAllTimelines()
        updateLiveActivities(with: snapshot)
    }

    @available(iOS 16.1, *)
    private func activityState(from snapshot: TokenPlanWidgetSnapshot? = nil) -> TokenPlanActivityAttributes.ContentState {
        let snapshot = snapshot ?? TokenPlanWidgetSnapshot(
            profiles: profiles.map {
                WidgetProfileSummary(
                    id: $0.id, name: $0.name, provider: $0.provider, enabled: $0.enabled,
                    usage: usageByProfile[$0.id] ?? .waiting
                )
            },
            updatedAt: Date()
        )
        let primary = snapshot.featuredProfile
        let usage = primary?.usage ?? .waiting
        let metricTitle: String
        if let balance = usage.balances.first {
            metricTitle = "\(balance.currency) 可用余额"
        } else {
            metricTitle = usage.tiers.first?.title ?? "套餐状态"
        }
        let secondary: String
        if let balance = usage.balances.first {
            secondary = "赠送 \(balance.grantedBalance) · 充值 \(balance.toppedUpBalance)"
        } else if usage.tiers.count > 1 {
            secondary = "\(usage.tiers[1].title) \(usage.tiers[1].percentageText)"
        } else if let reset = usage.tiers.first?.resetText {
            secondary = reset
        } else {
            secondary = usage.plan ?? usage.headline
        }
        return TokenPlanActivityAttributes.ContentState(
            enabledCount: snapshot.enabledCount,
            totalCount: snapshot.totalCount,
            primaryName: primary?.name ?? "尚无启用套餐",
            primaryMetricTitle: metricTitle,
            primaryDetail: usage.headline,
            secondaryDetail: secondary,
            primaryProgress: (usage.primaryTier?.clampedUtilization ?? 0) / 100,
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
