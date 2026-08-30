import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingProfile: Profile?
    @State private var showingSync = false

    var body: some View {
        NavigationStack {
            Group {
                if model.profiles.isEmpty {
                    EmptyPlansView { editingProfile = Profile() }
                } else {
                    plansList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("TokenPlan")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showingSync = true } label: {
                        Image(systemName: model.isSyncConfigured ? "icloud.fill" : "icloud")
                    }
                    .accessibilityLabel("云同步")
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { Task { await model.refreshAll() } } label: {
                        if model.isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityLabel("刷新套餐用量")

                    Button { editingProfile = Profile() } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增套餐")
                }
            }
            .sheet(item: $editingProfile) { profile in
                ProfileEditorView(profile: profile)
            }
            .sheet(isPresented: $showingSync) {
                SyncSettingsView()
            }
            .overlay(alignment: .bottom) {
                StatusBanner(
                    message: model.errorMessage.isEmpty ? model.message : model.errorMessage,
                    isError: !model.errorMessage.isEmpty
                )
            }
            .task {
                await model.refreshAll()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if !Task.isCancelled { await model.refreshAll() }
                }
            }
        }
    }

    private var plansList: some View {
        List {
            DashboardSummaryCard(
                profiles: model.profiles,
                usageByProfile: model.usageByProfile,
                isRefreshing: model.isRefreshing
            )
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                ForEach(model.profiles) { profile in
                    Button { editingProfile = profile } label: {
                        PlanProfileCard(
                            profile: profile,
                            usage: model.usageByProfile[profile.id] ?? .waiting
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            guard let index = model.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
                            Task { await model.delete(at: IndexSet(integer: index)) }
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("我的套餐")
                    Spacer()
                    Text("\(model.profiles.count) 个")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refreshAll() }
    }
}

private struct DashboardSummaryCard: View {
    let profiles: [Profile]
    let usageByProfile: [String: PlanUsage]
    let isRefreshing: Bool

    private var enabledCount: Int { profiles.filter(\.enabled).count }
    private var healthyCount: Int {
        profiles.filter { $0.enabled && usageByProfile[$0.id]?.status == .success }.count
    }
    private var warningCount: Int {
        profiles.filter { $0.enabled && usageByProfile[$0.id]?.status == .failed }.count
    }
    private var latestDate: Date? { usageByProfile.values.compactMap(\.queriedAt).max() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("套餐总览", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("\(enabledCount) 个正在监控")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Circle().fill(.white.opacity(0.14))
                    if isRefreshing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                SummaryMetric(value: "\(healthyCount)", label: "正常", icon: "checkmark.circle.fill")
                Divider().overlay(.white.opacity(0.22)).padding(.vertical, 2)
                SummaryMetric(value: "\(warningCount)", label: "异常", icon: "exclamationmark.triangle.fill")
                Divider().overlay(.white.opacity(0.22)).padding(.vertical, 2)
                SummaryMetric(
                    value: latestDate.map { $0.formatted(.dateTime.hour().minute()) } ?? "--",
                    label: "最近刷新",
                    icon: "clock.fill"
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.18, blue: 0.48), Color(red: 0.35, green: 0.20, blue: 0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Color.indigo.opacity(0.24), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("套餐总览，\(enabledCount) 个正在监控，\(healthyCount) 个正常，\(warningCount) 个异常")
    }
}

private struct SummaryMetric: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
            }
            Text(label).font(.caption2).opacity(0.72)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

private struct PlanProfileCard: View {
    let profile: Profile
    let usage: PlanUsage

    private var visual: ProviderVisual { ProviderVisual(provider: profile.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(visual.gradient)
                    Image(systemName: visual.symbol)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(Provider(rawValue: profile.provider)?.title ?? profile.provider)
                        if let plan = usage.plan, !plan.isEmpty {
                            Text("·")
                            Text(plan)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                StatusPill(status: profile.enabled ? usage.status : .paused)
            }

            if !profile.enabled {
                EmptyMetricView(icon: "pause.fill", title: "套餐已暂停", detail: "启用后将继续查询用量")
            } else if usage.hasDetails {
                ForEach(usage.tiers.prefix(3)) { tier in
                    UsageMeter(tier: tier, tint: visual.color)
                }
                ForEach(usage.balances.prefix(2)) { balance in
                    BalanceMetric(balance: balance, tint: visual.color)
                }
                if usage.status == .failed {
                    Label("本次刷新失败，正在显示上次数据", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                EmptyMetricView(
                    icon: usage.status == .failed ? "wifi.exclamationmark" : "arrow.triangle.2.circlepath",
                    title: usage.headline,
                    detail: usage.error ?? "下拉或点击右上角刷新"
                )
            }

            HStack(spacing: 6) {
                if let date = usage.queriedAt {
                    Image(systemName: "clock")
                    Text(date, style: .relative)
                    Text("前更新")
                } else {
                    Image(systemName: "clock.badge.questionmark")
                    Text("尚未获取数据")
                }
                Spacer()
                Text("查看配置")
                Image(systemName: "chevron.right")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(visual.color.opacity(0.10), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UsageMeter: View {
    let tier: PlanUsageTier
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(tier.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let used = tier.usedValueUSD, let max = tier.maxValueUSD {
                    Text("$\(used, specifier: "%.1f") / $\(max, specifier: "%.1f")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(tier.percentageText)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(tier.clampedUtilization >= 90 ? .red : tint)
                    .monospacedDigit()
            }
            ProgressView(value: tier.clampedUtilization, total: 100)
                .tint(tier.clampedUtilization >= 90 ? .red : tint)
                .scaleEffect(x: 1, y: 1.35, anchor: .center)
            if let reset = tier.resetText {
                Label(reset, systemImage: "arrow.counterclockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tier.title)，已使用 \(tier.percentageText)\(tier.resetText.map { "，\($0)" } ?? "")")
    }
}

private struct BalanceMetric: View {
    let balance: PlanBalance
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(tint.opacity(0.12))
                Image(systemName: "creditcard.fill").foregroundStyle(tint)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(balance.currency) 可用余额").font(.caption).foregroundStyle(.secondary)
                Text(balance.totalBalance).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("赠送 \(balance.grantedBalance)")
                Text("充值 \(balance.toppedUpBalance)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyMetricView: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct StatusPill: View {
    let status: PlanUsageStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .loading { ProgressView().controlSize(.mini) }
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: Capsule())
    }

    private var title: String {
        switch status {
        case .success: "正常"
        case .loading: "刷新中"
        case .failed: "异常"
        case .paused: "已暂停"
        case .waiting: "待刷新"
        }
    }

    private var color: Color {
        switch status {
        case .success: .green
        case .loading: .blue
        case .failed: .red
        case .paused, .waiting: .secondary
        }
    }
}

private struct ProviderVisual {
    let color: Color
    let secondaryColor: Color
    let symbol: String

    init(provider: String) {
        switch Provider(rawValue: provider) {
        case .volcengine: (color, secondaryColor, symbol) = (.orange, .red, "flame.fill")
        case .kimi: (color, secondaryColor, symbol) = (.blue, .cyan, "moon.stars.fill")
        case .zhipu, .zhipuTeam: (color, secondaryColor, symbol) = (.purple, .indigo, "brain.head.profile")
        case .minimax: (color, secondaryColor, symbol) = (.pink, .purple, "waveform")
        case .zenmux: (color, secondaryColor, symbol) = (.teal, .blue, "point.3.connected.trianglepath.dotted")
        case .opencodeGo: (color, secondaryColor, symbol) = (.green, .teal, "chevron.left.forwardslash.chevron.right")
        case .deepseek: (color, secondaryColor, symbol) = (.indigo, .blue, "creditcard.fill")
        case nil: (color, secondaryColor, symbol) = (.indigo, .purple, "key.horizontal.fill")
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [color, secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct EmptyPlansView: View {
    let add: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.10))
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.indigo)
            }
            .frame(width: 92, height: 92)
            Text("还没有套餐").font(.title2.bold())
            Text("从云端下载配置，或添加第一个 AI 套餐。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: add) {
                Label("添加套餐", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(30)
    }
}

private struct StatusBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        if !message.isEmpty {
            Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(isError ? Color.red : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding()
        }
    }
}
