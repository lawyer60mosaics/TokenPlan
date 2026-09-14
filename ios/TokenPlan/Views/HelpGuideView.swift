import SwiftUI

struct HelpGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BeginnerStepCard(number: 1, title: "添加套餐", detail: "选择你购买套餐的平台，填写平台提供的访问凭据，然后保存。", systemImage: "plus.circle.fill")
                    BeginnerStepCard(number: 2, title: "查看用量", detail: "回到首页后点击“刷新用量”，或者直接下拉页面。", systemImage: "chart.bar.fill")
                    BeginnerStepCard(number: 3, title: "开启更多功能", detail: "需要多设备同步、小组件或灵动岛时，再进入“同步设置”。", systemImage: "sparkles")
                } header: {
                    FeatureSectionHeader(title: "第一次使用", subtitle: "按顺序完成三步即可", systemImage: "figure.walk")
                }

                Section {
                    Label("绿色“正常”：最近一次查询成功", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("橙色或红色“异常”：查询失败，可点击套餐检查凭据", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Label("“待刷新”：尚未查询，点击首页“刷新用量”", systemImage: "arrow.clockwise.circle")
                        .foregroundStyle(.secondary)
                    Label("“已暂停”：配置仍保留，但不会自动查询", systemImage: "pause.circle.fill")
                        .foregroundStyle(.secondary)
                } header: {
                    FeatureSectionHeader(title: "状态怎么看", subtitle: "颜色之外还会显示文字，不需要猜图标", systemImage: "eye.fill")
                }

                Section {
                    ChineseHelpText(text: "云同步：让多台设备使用同一份加密套餐配置。首次使用先上传，新设备再下载。")
                    ChineseHelpText(text: "桌面小组件：长按桌面并搜索 TokenPlan，可选择小、中、大尺寸。")
                    ChineseHelpText(text: "锁屏与灵动岛：进入同步设置后手动启动，支持的设备会实时显示主要套餐。")
                    ChineseHelpText(text: "定时预热：在工作日指定时间发送最小请求，只应选择一个调度平台。")
                } header: {
                    FeatureSectionHeader(title: "扩展功能", subtitle: "按需开启，不影响基础用量查询", systemImage: "square.grid.2x2.fill")
                }

                Section {
                    ChineseHelpText(
                        text: "套餐凭据受 iOS 文件保护；云同步仅上传端到端加密密文。任何页面都不会显示已保存密钥的完整内容。",
                        systemImage: "lock.shield.fill",
                        tint: .green
                    )
                } header: {
                    FeatureSectionHeader(title: "安全说明", subtitle: "密钥只用于查询对应平台的套餐信息", systemImage: "hand.raised.fill")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("使用帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
