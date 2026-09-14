import SwiftUI

struct SyncSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmedPassword = ""
    @State private var prewarmAPIKey = ""
    @State private var showPullConfirmation = false
    @State private var showPushConfirmation = false
    @State private var showDisableConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username, password, currentPassword, newPassword, confirmation, prewarmKey
    }

    private let prewarmModels = [
        "ark-code-latest", "doubao-seed-2.0-code", "doubao-seed-2.0-pro",
        "doubao-seed-2.0-lite", "doubao-seed-code", "minimax-m2.5",
        "glm-4.7", "deepseek-v3.2", "kimi-k2.5"
    ]

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                if model.isSyncConfigured {
                    transferSection
                    passwordSection
                    prewarmSection
                }
                liveActivitySection
                widgetSection
                operationStatusSection
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("云同步与组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityHint("关闭设置并返回套餐首页")
                }
            }
            .confirmationDialog("下载云端配置？", isPresented: $showPullConfirmation, titleVisibility: .visible) {
                Button("下载并替换本地套餐") { Task { await model.pull() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("下载后，本机当前套餐会被云端版本替换。建议先确认云端版本号。")
            }
            .confirmationDialog("上传本地配置？", isPresented: $showPushConfirmation, titleVisibility: .visible) {
                Button("上传并替换云端套餐") { Task { await model.push() } }
                Button("取消", role: .cancel) {}
            } message: {
                Text("上传后，云端配置会变成本机当前套餐，其他设备下次下载时也会收到此版本。")
            }
            .confirmationDialog("停用云同步？", isPresented: $showDisableConfirmation, titleVisibility: .visible) {
                Button("停用云同步", role: .destructive) { model.disableSync() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只会清除本机保存的同步登录信息，不会删除本地套餐或云端数据。")
            }
        }
        .task {
            if model.isSyncConfigured && model.prewarmState == nil {
                await model.loadPrewarm()
            }
        }
    }

    private var connectionSection: some View {
        Section {
            BeginnerStepCard(
                number: 1,
                title: "保存同步账号",
                detail: "首次使用时填写账号和至少 16 位密码；其他设备输入相同内容即可连接同一份加密配置。",
                systemImage: "person.crop.circle.badge.checkmark"
            )
            TextField("同步账号", text: $model.username)
                .focused($focusedField, equals: .username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .accessibilityHint("输入你自己设置的同步账号")
            SecureField("同步密码，至少 16 位", text: $model.password)
                .focused($focusedField, equals: .password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .accessibilityHint("此密码同时用于登录和端到端加密，请妥善保存")

            LabeledContent("当前状态") {
                InlineStatusLabel(
                    title: model.isSyncConfigured ? "本机已保存账号" : "尚未配置",
                    isSuccess: model.isSyncConfigured
                )
            }

            Button {
                focusedField = nil
                Task { await model.configure() }
            } label: {
                FullWidthActionLabel(
                    title: model.isSyncConfigured ? "更新本机账号密码" : "保存账号密码",
                    systemImage: "lock.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)

            ChineseHelpText(
                text: "应用会根据账号和密码自动生成认证密钥与加密密钥。服务器看不到套餐凭据明文，也不需要“同步令牌”或“恢复密钥”。",
                systemImage: "lock.shield.fill",
                tint: .green
            )
        } header: {
            FeatureSectionHeader(title: "连接云同步", subtitle: "先完成这一步，才能上传或下载套餐", systemImage: "icloud.fill")
        }
    }

    private var transferSection: some View {
        Section {
            BeginnerStepCard(
                number: 2,
                title: "选择同步方向",
                detail: "新手机通常选择“从云端下载”；刚在本机修改套餐后选择“上传本地套餐”。",
                systemImage: "arrow.up.arrow.down.circle.fill"
            )
            LabeledContent("云端版本", value: String(model.revision))

            Button { showPullConfirmation = true } label: {
                Label("从云端下载到本机", systemImage: "icloud.and.arrow.down.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(model.isBusy)
            .accessibilityHint("会先显示确认说明，然后用云端配置替换本机套餐")

            Button { showPushConfirmation = true } label: {
                Label("把本机套餐上传到云端", systemImage: "icloud.and.arrow.up.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(model.isBusy)
            .accessibilityHint("会先显示确认说明，然后用本机套餐更新云端")

            Button("停用本机云同步", role: .destructive) { showDisableConfirmation = true }
                .disabled(model.isBusy)
                .accessibilityHint("不会删除本地套餐和云端数据")
        } header: {
            FeatureSectionHeader(title: "同步套餐", subtitle: "上传和下载前都会再次确认，避免选错方向", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private var passwordSection: some View {
        Section {
            SecureField("当前密码", text: $currentPassword)
                .focused($focusedField, equals: .currentPassword)
                .textContentType(.password)
            SecureField("新密码，至少 16 位", text: $newPassword)
                .focused($focusedField, equals: .newPassword)
                .textContentType(.newPassword)
            SecureField("再次输入新密码", text: $confirmedPassword)
                .focused($focusedField, equals: .confirmation)
                .textContentType(.newPassword)

            Button("确认修改同步密码", action: changePassword)
                .disabled(model.isBusy || currentPassword.isEmpty || newPassword.isEmpty || confirmedPassword.isEmpty)

            ChineseHelpText(
                text: "修改成功后，服务器上的套餐配置会用新密码重新加密；其他设备必须使用新密码重新登录。",
                systemImage: "exclamationmark.shield.fill",
                tint: .orange
            )
        } header: {
            FeatureSectionHeader(title: "修改同步密码", subtitle: "仅在你确定记得当前密码时使用", systemImage: "key.viewfinder")
        }
    }

    private var prewarmSection: some View {
        Section {
            BeginnerStepCard(
                number: 3,
                title: "配置套餐预热",
                detail: "到点发送一次最小请求，用于启动火山方舟 Coding Plan 的 5 小时使用窗口。",
                systemImage: "clock.badge.checkmark.fill"
            )
            Toggle("工作日自动预热", isOn: $model.prewarmEnabled)
                .accessibilityHint("启用后在上海时区工作日早上八点和下午一点执行")
            LabeledContent("执行时间", value: "工作日 08:00、13:00")
            LabeledContent("使用时区", value: "北京时间（上海）")
            Picker("调用模型", selection: $model.prewarmModel) {
                ForEach(prewarmModels, id: \.self) { Text($0).tag($0) }
            }
            SecureField(
                model.prewarmState?.hasAPIKey == true ? "已保存；留空不会覆盖" : "Coding Plan API Key",
                text: $prewarmAPIKey
            )
            .focused($focusedField, equals: .prewarmKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityHint("填写火山方舟 Coding Plan 专用 API Key")

            Button("保存自动预热设置", action: savePrewarm)
                .disabled(model.isBusy)
            Button("立即测试一次预热") { Task { await model.runPrewarm() } }
                .disabled(model.isBusy || model.prewarmState?.hasAPIKey != true)
                .accessibilityHint("立即发送一次最小请求，验证 API Key 和网络是否正常")

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

            ChineseHelpText(
                text: "每次预热会产生一次真实套餐调用，最多生成 1 token。只选择一个调度平台，避免 GitHub、阿里云和腾讯云重复触发。",
                systemImage: "info.circle.fill",
                tint: .blue
            )
        } header: {
            FeatureSectionHeader(title: "定时任务", subtitle: "保存后先点“立即测试一次预热”确认配置", systemImage: "calendar.badge.clock")
        }
    }

    private var liveActivitySection: some View {
        Section {
            LabeledContent("当前状态", value: model.isLiveActivityActive ? "正在显示" : "尚未启动")
            if model.isLiveActivityActive {
                Button("停止锁屏与灵动岛显示", role: .destructive) {
                    Task { await model.endLiveActivity() }
                }
            } else {
                Button {
                    Task { await model.startLiveActivity() }
                } label: {
                    FullWidthActionLabel(title: "启动锁屏与灵动岛显示", systemImage: "livephoto")
                }
                .buttonStyle(.borderedProminent)
            }
            ChineseHelpText(text: "启动后，锁屏会显示当前套餐；支持灵动岛的 iPhone 还会在灵动岛显示。可随时回到这里停止。")
        } header: {
            FeatureSectionHeader(title: "锁屏与灵动岛", subtitle: "实时查看主要套餐状态", systemImage: "iphone.gen3")
        }
    }

    private var widgetSection: some View {
        Section {
            LabeledContent("数据共享") {
                InlineStatusLabel(
                    title: model.isWidgetSharingAvailable ? "小组件可以读取套餐" : "小组件暂时无法读取",
                    isSuccess: model.isWidgetSharingAvailable
                )
            }
            Text(model.widgetSharingStatus)
                .font(.footnote)
                .foregroundStyle(model.isWidgetSharingAvailable ? Color.secondary : Color.red)
                .textSelection(.enabled)

            Button("重新写入小组件数据") { model.repairWidgetSharing() }
                .accessibilityHint("把当前套餐状态重新发送给桌面和锁屏小组件")

            ChineseHelpText(text: "添加方法：长按桌面或锁屏，点“添加小组件”，搜索 TokenPlan，再选择小、中或大尺寸。")
            ChineseHelpText(
                text: "如果使用重签 IPA，主程序和 TokenPlanWidgets 扩展必须属于同一开发团队，并包含 group.com.xuwenxu.tokenplan。",
                systemImage: "signature",
                tint: .orange
            )
        } header: {
            FeatureSectionHeader(title: "桌面与锁屏小组件", subtitle: "确认系统小组件能够读取套餐数据", systemImage: "square.grid.2x2.fill")
        }
    }

    @ViewBuilder
    private var operationStatusSection: some View {
        if model.isBusy {
            Section {
                ProgressView("正在处理，请稍候…")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        if !model.errorMessage.isEmpty || !model.message.isEmpty {
            Section {
                Label(
                    model.errorMessage.isEmpty ? model.message : model.errorMessage,
                    systemImage: model.errorMessage.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(model.errorMessage.isEmpty ? Color.green : Color.red)
                .accessibilityAddTraits(.isSummaryElement)
            } header: {
                Text("操作结果")
            }
        }
    }

    private func changePassword() {
        focusedField = nil
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

    private func savePrewarm() {
        focusedField = nil
        Task {
            if await model.savePrewarm(apiKey: prewarmAPIKey) {
                prewarmAPIKey = ""
            }
        }
    }
}
