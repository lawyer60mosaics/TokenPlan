import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingRecoveryKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("HTTPS 地址", text: $model.endpoint)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    SecureField("同步令牌", text: $model.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("端到端加密") {
                    Group {
                        if showingRecoveryKey {
                            TextField("恢复密钥", text: $model.recoveryKey)
                        } else {
                            SecureField("恢复密钥（首次设备可留空）", text: $model.recoveryKey)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Toggle("显示恢复密钥", isOn: $showingRecoveryKey)
                    Text("首次配置留空会生成新密钥。已有云端数据时必须填写原恢复密钥；服务器无法找回该密钥。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("状态") {
                    LabeledContent("连接", value: model.isSyncConfigured ? "已配置" : "未配置")
                    LabeledContent("云端版本", value: String(model.revision))
                    Button("保存同步配置") { Task { await model.configure() } }
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
