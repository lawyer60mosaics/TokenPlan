import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmedPassword = ""
    @State private var prewarmAPIKey = ""

    private let prewarmModels = [
        "ark-code-latest", "doubao-seed-2.0-code", "doubao-seed-2.0-pro",
        "doubao-seed-2.0-lite", "doubao-seed-code", "minimax-m2.5",
        "glm-4.7", "deepseek-v3.2", "kimi-k2.5"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("账号") {
                    TextField("账号", text: $model.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("密码（至少 16 位）", text: $model.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                    Text("其他设备输入相同账号和密码即可同步。应用会自动生成独立的认证与加密密钥。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("状态") {
                    LabeledContent("连接", value: model.isSyncConfigured ? "已配置" : "未配置")
                    LabeledContent("云端版本", value: String(model.revision))
                    Button("保存账号密码") { Task { await model.configure() } }
                        .disabled(model.isBusy)
                    if model.isSyncConfigured {
                        Button("从云端下载") { Task { await model.pull() } }
                            .disabled(model.isBusy)
                        Button("上传本地套餐") { Task { await model.push() } }
                            .disabled(model.isBusy)
                        Button("停用云同步", role: .destructive) { model.disableSync() }
                            .disabled(model.isBusy)
                    }
                }
                if model.isSyncConfigured {
                    Section("修改同步密码") {
                        SecureField("当前密码", text: $currentPassword)
                            .textContentType(.password)
                        SecureField("新密码（至少 16 位）", text: $newPassword)
                            .textContentType(.newPassword)
                        SecureField("再次输入新密码", text: $confirmedPassword)
                            .textContentType(.newPassword)
                        Button("修改密码") {
                            Task {
                                if await model.changeSyncPassword(
                                    currentPassword: currentPassword,
                                    newPassword: newPassword,
                                    confirmation: confirmedPassword
                                ) {
                                    currentPassword = ""
                                    newPassword = ""
                                    confirmedPassword = ""
                                }
                            }
                        }
                        .disabled(model.isBusy)
                        Text("修改后，云端配置会使用新密码重新加密。其他设备需要输入新密码重新登录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("配额预热") {
                        Toggle("启用工作日自动预热", isOn: $model.prewarmEnabled)
                        LabeledContent("时间", value: "工作日 08:00、13:00")
                        LabeledContent("时区", value: "Asia/Shanghai")
                        Picker("套餐模型", selection: $model.prewarmModel) {
                            ForEach(prewarmModels, id: \.self) { Text($0).tag($0) }
                        }
                        SecureField(
                            model.prewarmState?.hasAPIKey == true ? "已加密保存；留空不覆盖" : "Coding Plan API Key",
                            text: $prewarmAPIKey
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button("保存预热设置") {
                            Task {
                                if await model.savePrewarm(apiKey: prewarmAPIKey) {
                                    prewarmAPIKey = ""
                                }
                            }
                        }
                        .disabled(model.isBusy)
                        Button("立即试运行") { Task { await model.runPrewarm() } }
                            .disabled(model.isBusy || model.prewarmState?.hasAPIKey != true)
                        if let run = model.prewarmState?.lastRun {
                            LabeledContent("最近执行") {
                                Label(
                                    Date(timeIntervalSince1970: TimeInterval(run.triggeredAt)).formatted(date: .abbreviated, time: .shortened),
                                    systemImage: run.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                                )
                                .foregroundStyle(run.success ? Color.green : Color.orange)
                            }
                        } else {
                            LabeledContent("最近执行", value: "尚未执行")
                        }
                        Text("每次会真实调用一次火山方舟 Coding Plan，最多生成 1 token，用于启动 5 小时窗口。API Key 经加密存于云服务器且不会回传；错过计划时间 30 分钟内会自动补执行。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("锁屏与灵动岛") {
                    LabeledContent("实时活动", value: model.isLiveActivityActive ? "运行中" : "未启动")
                    if model.isLiveActivityActive {
                        Button("结束灵动岛实时活动", role: .destructive) {
                            Task { await model.endLiveActivity() }
                        }
                    } else {
                        Button("启动灵动岛实时活动") {
                            Task { await model.startLiveActivity() }
                        }
                    }
                    Text("桌面和锁屏小组件可从系统的小组件库添加。灵动岛仅在支持的 iPhone 上显示，其他设备会显示锁屏实时活动。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("小组件数据共享") {
                    LabeledContent("状态") {
                        Label(
                            model.isWidgetSharingAvailable ? "正常" : "不可用",
                            systemImage: model.isWidgetSharingAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(model.isWidgetSharingAvailable ? Color.green : Color.red)
                    }
                    Text(model.widgetSharingStatus)
                        .font(.footnote)
                        .foregroundStyle(model.isWidgetSharingAvailable ? Color.secondary : Color.red)
                        .textSelection(.enabled)
                    Button("重新写入小组件数据") {
                        model.repairWidgetSharing()
                    }
                    Text("未签名 IPA 重签时，主程序和 TokenPlanWidgets.appex 必须使用同一开发团队，并同时包含 group.com.xuwenxu.tokenplan。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if model.isBusy {
                    Section { ProgressView("同步中…") }
                }
                if !model.errorMessage.isEmpty || !model.message.isEmpty {
                    Section {
                        Text(model.errorMessage.isEmpty ? model.message : model.errorMessage)
                            .foregroundStyle(model.errorMessage.isEmpty ? Color.primary : Color.red)
                    }
                }
            }
            .navigationTitle("云同步")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task {
            if model.isSyncConfigured && model.prewarmState == nil {
                await model.loadPrewarm()
            }
        }
    }
}
