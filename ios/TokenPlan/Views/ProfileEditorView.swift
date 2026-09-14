import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var profile: Profile
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, accessKey, secretKey, apiKey, organization, project, baseURL
    }

    private var provider: Provider { Provider(rawValue: profile.provider) ?? .volcengine }
    private var trimmedName: String { profile.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BeginnerStepCard(
                        number: 1,
                        title: "选择套餐供应商",
                        detail: "先选择你购买套餐的平台，下面会自动显示它需要的凭据。",
                        systemImage: "building.2.fill"
                    )
                    Picker("套餐供应商", selection: $profile.provider) {
                        ForEach(Provider.allCases) { provider in
                            Text(provider.title).tag(provider.rawValue)
                        }
                    }
                    .accessibilityHint("选择后会更新下方需要填写的凭据")

                    TextField("给这个套餐起个名字", text: $profile.name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .accessibilityLabel("套餐名称")
                        .accessibilityHint("例如：我的火山方舟套餐")

                    Toggle("启用用量监控", isOn: $profile.enabled)
                        .accessibilityHint("关闭后保留配置，但暂停查询套餐用量")

                    if provider == .zhipu || provider == .minimax {
                        Picker("账号所属站点", selection: $profile.region) {
                            Text("国内站点").tag("cn")
                            Text("国际站点").tag("global")
                        }
                    }

                    ChineseHelpText(text: "套餐名称只在你的设备和加密同步数据中显示，不会修改供应商账号。")
                    ChineseHelpText(text: "切换供应商时，当前输入不会立刻丢失；保存时只保留所选供应商需要的字段。")
                } header: {
                    FeatureSectionHeader(title: "基本信息", subtitle: "决定这个套餐如何显示和查询", systemImage: "slider.horizontal.3")
                }

                Section {
                    BeginnerStepCard(
                        number: 2,
                        title: "填写访问凭据",
                        detail: credentialIntroduction,
                        systemImage: "key.fill"
                    )

                    if provider == .volcengine {
                        TextField("AccessKey ID", text: $profile.accessKey)
                            .focused($focusedField, equals: .accessKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityHint("在火山引擎访问控制页面复制")
                        SecureField("Secret AccessKey", text: $profile.secretKey)
                            .focused($focusedField, equals: .secretKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityHint("内容会隐藏显示，请完整粘贴")
                    } else {
                        SecureField("API Key", text: $profile.apiKey)
                            .focused($focusedField, equals: .apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityHint("在对应平台的 API Key 管理页面复制")
                    }

                    if provider == .zhipuTeam {
                        TextField("组织 ID", text: $profile.organizationID)
                            .focused($focusedField, equals: .organization)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("项目 ID", text: $profile.projectID)
                            .focused($focusedField, equals: .project)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        ChineseHelpText(text: "团队套餐必须同时填写组织 ID 和项目 ID，可在智谱团队控制台查看。")
                    }

                    if provider == .zenmux {
                        TextField("HTTPS 用量查询地址", text: $profile.baseURL)
                            .focused($focusedField, equals: .baseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        ChineseHelpText(text: "只允许填写 zenmux.ai 或 zenmux.com 的 HTTPS 地址，不能填写其他域名。")
                    }
                } header: {
                    FeatureSectionHeader(title: "账号凭据", subtitle: "用于读取套餐用量，不会展示给其他用户", systemImage: "lock.shield.fill")
                }

                Section {
                    BeginnerStepCard(
                        number: 3,
                        title: "保存并刷新",
                        detail: "保存后返回首页，下拉页面即可读取最新套餐用量。",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    if !profile.enabled {
                        ChineseHelpText(text: "当前已关闭监控。配置会保存，但首页不会主动查询该套餐。", systemImage: "pause.circle.fill", tint: .orange)
                    }
                    ChineseHelpText(
                        text: "凭据保存在受 iOS 完整文件保护的本地文件中；开启云同步后，云端只保存端到端加密密文。",
                        systemImage: "checkmark.shield.fill",
                        tint: .green
                    )
                } header: {
                    FeatureSectionHeader(title: "保存说明", subtitle: "保存前确认名称和凭据填写完整", systemImage: "checkmark.circle.fill")
                }

                if !model.errorMessage.isEmpty {
                    Section("无法保存") {
                        Label(model.errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.isSummaryElement)
                        ChineseHelpText(text: "请检查供应商、套餐名称和必填凭据，然后再次点击保存。", systemImage: "arrow.counterclockwise", tint: .orange)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("套餐设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .accessibilityHint("放弃本次修改")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(trimmedName.isEmpty || isSaving)
                        .accessibilityHint("保存套餐并返回首页")
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("正在保存…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
    }

    private var credentialIntroduction: String {
        switch provider {
        case .volcengine: "火山方舟需要 AccessKey ID 和 Secret AccessKey，可在访问控制页面创建。"
        case .zhipuTeam: "智谱团队套餐需要 API Key、组织 ID 和项目 ID。"
        case .zenmux: "ZenMux 需要 API Key 和官方 HTTPS 用量查询地址。"
        default: "\(provider.title) 需要一个 API Key，可在该平台的密钥管理页面创建。"
        }
    }

    private func save() {
        guard !trimmedName.isEmpty, !isSaving else { return }
        focusedField = nil
        isSaving = true
        Task {
            await model.save(sanitizedProfile())
            isSaving = false
            if model.errorMessage.isEmpty { dismiss() }
        }
    }

    private func sanitizedProfile() -> Profile {
        var result = profile
        if provider == .volcengine {
            result.apiKey = ""
        } else {
            result.accessKey = ""
            result.secretKey = ""
        }
        if provider != .zhipuTeam {
            result.organizationID = ""
            result.projectID = ""
        }
        if provider != .zenmux { result.baseURL = "" }
        return result
    }
}
