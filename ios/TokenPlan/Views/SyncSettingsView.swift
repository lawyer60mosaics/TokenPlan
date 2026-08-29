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
