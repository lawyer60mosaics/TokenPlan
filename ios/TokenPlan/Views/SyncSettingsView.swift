import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
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
    }
}
