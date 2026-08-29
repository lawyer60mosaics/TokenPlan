import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var profile: Profile

    private var provider: Provider { Provider(rawValue: profile.provider) ?? .volcengine }

    var body: some View {
        NavigationStack {
            Form {
                Section("套餐") {
                    TextField("名称", text: $profile.name)
                    Picker("供应商", selection: $profile.provider) {
                        ForEach(Provider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    Toggle("启用", isOn: $profile.enabled)
                    if provider == .zhipu || provider == .minimax {
                        Picker("站点", selection: $profile.region) {
                            Text("国内").tag("cn")
                            Text("国际").tag("global")
                        }
                    }
                }
                Section("凭据") {
                    if provider == .volcengine {
                        SecureField("AccessKey ID", text: $profile.accessKey)
                        SecureField("Secret AccessKey", text: $profile.secretKey)
                    } else {
                        SecureField("API Key", text: $profile.apiKey)
                    }
                    if provider == .zhipuTeam {
                        TextField("组织 ID", text: $profile.organizationID)
                        TextField("项目 ID", text: $profile.projectID)
                    }
                    if provider == .zenmux {
                        TextField("HTTPS 用量查询地址", text: $profile.baseURL)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                }
                Section {
                    Text("本地文件使用 iOS 完整文件保护；云端只保存端到端加密密文。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("套餐设置")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: profile.provider) { _ in
                profile.accessKey = ""
                profile.secretKey = ""
                profile.apiKey = ""
                profile.organizationID = ""
                profile.projectID = ""
                profile.baseURL = ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await model.save(profile)
                            if model.errorMessage.isEmpty { dismiss() }
                        }
                    }
                    .disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
