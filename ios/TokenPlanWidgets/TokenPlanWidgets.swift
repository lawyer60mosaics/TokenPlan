import ActivityKit
import SwiftUI
import WidgetKit

struct TokenPlanEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: TokenPlanWidgetSnapshot
}

struct TokenPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenPlanEntry {
        TokenPlanEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenPlanEntry) -> Void) {
        completion(TokenPlanEntry(date: .now, snapshot: context.isPreview ? .placeholder : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenPlanEntry>) -> Void) {
        let entry = TokenPlanEntry(date: .now, snapshot: WidgetSnapshotStore.load())
        let nextCheck = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextCheck)))
    }
}

struct TokenPlanHomeWidget: Widget {
    let kind = "TokenPlanHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenPlanProvider()) { entry in
            TokenPlanHomeWidgetView(entry: entry)
                .tokenPlanWidgetBackground()
                .widgetURL(URL(string: "tokenplan://plans"))
        }
        .configurationDisplayName("TokenPlan 套餐")
        .description("显示套餐窗口、用量、余额和重置时间。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct TokenPlanHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenPlanEntry

    var body: some View {
        Group {
            if entry.snapshot.profiles.isEmpty {
                WidgetEmptyView()
            } else {
                switch family {
                case .systemSmall: SmallPlanWidget(profile: entry.snapshot.featuredProfile)
                case .systemMedium: MediumPlanWidget(snapshot: entry.snapshot)
                default: LargePlanWidget(snapshot: entry.snapshot)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetHeader: View {
    let updatedAt: Date?

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "chart.bar.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            Text("TokenPlan").font(.caption.bold())
            Spacer(minLength: 4)
            if let updatedAt, updatedAt > .distantPast {
                Text(updatedAt, style: .time)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SmallPlanWidget: View {
    let profile: WidgetProfileSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetHeader(updatedAt: profile?.usage.queriedAt)
            if let profile {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(profile.provider).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let tier = profile.usage.primaryTier {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(tier.percentageText)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.8)
                        Text("已使用").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text(tier.title).font(.caption2.weight(.semibold))
                    ProgressView(value: tier.clampedUtilization, total: 100)
                        .tint(metricColor(tier.clampedUtilization))
                    if let reset = tier.resetText {
                        Text(reset).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else if let balance = profile.usage.balances.first {
                    Text(balance.totalBalance)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("\(balance.currency) 可用余额").font(.caption2.weight(.semibold))
                } else {
                    WidgetStatusView(usage: profile.usage)
                }
            } else {
                WidgetStatusView(usage: .waiting)
            }
        }
        .padding(14)
    }
}

private struct MediumPlanWidget: View {
    let snapshot: TokenPlanWidgetSnapshot

    private var displayedProfiles: [WidgetProfileSummary] {
        Array(snapshot.enabledProfiles.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(updatedAt: snapshot.updatedAt)
            HStack(spacing: 10) {
                ForEach(displayedProfiles) { profile in
                    WidgetPlanColumn(profile: profile)
                    if profile.id != displayedProfiles.last?.id { Divider() }
                }
                if snapshot.enabledProfiles.isEmpty {
                    WidgetStatusView(usage: .waiting)
                }
            }
        }
        .padding(14)
    }
}

private struct WidgetPlanColumn: View {
    let profile: WidgetProfileSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profile.name).font(.caption.bold()).lineLimit(1)
            Text(profile.usage.plan ?? profile.provider)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !profile.usage.tiers.isEmpty {
                ForEach(profile.usage.tiers.prefix(2)) { tier in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(tier.title).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(tier.percentageText).bold().monospacedDigit()
                        }
                        .font(.system(size: 10))
                        ProgressView(value: tier.clampedUtilization, total: 100)
                            .tint(metricColor(tier.clampedUtilization))
                    }
                }
            } else if let balance = profile.usage.balances.first {
                Text(balance.totalBalance)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text("\(balance.currency) 余额").font(.caption2).foregroundStyle(.secondary)
            } else {
                WidgetStatusView(usage: profile.usage)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LargePlanWidget: View {
    let snapshot: TokenPlanWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            WidgetHeader(updatedAt: snapshot.updatedAt)
            HStack(alignment: .firstTextBaseline) {
                Text("套餐用量")
                    .font(.title3.bold())
                Spacer()
                Text("\(snapshot.enabledCount) 个启用")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(snapshot.enabledProfiles.prefix(4)) { profile in
                LargePlanRow(profile: profile)
            }
            if snapshot.enabledProfiles.isEmpty {
                WidgetStatusView(usage: .waiting)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct LargePlanRow: View {
    let profile: WidgetProfileSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle()
                    .fill(profile.usage.status == .failed ? Color.orange : Color.indigo)
                    .frame(width: 7, height: 7)
                Text(profile.name).font(.caption.bold()).lineLimit(1)
                Text(profile.usage.plan ?? profile.provider)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(profile.usage.headline)
                    .font(.caption2.bold())
                    .monospacedDigit()
            }
            if !profile.usage.tiers.isEmpty {
                HStack(spacing: 8) {
                    ForEach(profile.usage.tiers.prefix(3)) { tier in
                        HStack(spacing: 3) {
                            Text(tier.title).foregroundStyle(.secondary)
                            Text(tier.percentageText).bold().monospacedDigit()
                        }
                        .font(.system(size: 9))
                    }
                }
                if let tier = profile.usage.primaryTier {
                    ProgressView(value: tier.clampedUtilization, total: 100)
                        .tint(metricColor(tier.clampedUtilization))
                }
            } else if let balance = profile.usage.balances.first {
                Text("赠送 \(balance.grantedBalance) · 充值 \(balance.toppedUpBalance)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct WidgetStatusView: View {
    let usage: PlanUsage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: usage.status == .failed ? "exclamationmark.triangle.fill" : "arrow.clockwise.circle")
            Text(usage.headline)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(usage.status == .failed ? .orange : .secondary)
    }
}

private struct WidgetEmptyView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: WidgetSnapshotStore.isAppGroupAvailable ? "chart.bar.xaxis" : "exclamationmark.shield.fill")
                .font(.title)
                .foregroundStyle(WidgetSnapshotStore.isAppGroupAvailable ? .indigo : .orange)
            Text(WidgetSnapshotStore.isAppGroupAvailable ? "尚未共享套餐" : "签名权限缺失")
                .font(.headline)
            Text(WidgetSnapshotStore.isAppGroupAvailable
                 ? "打开 TokenPlan 后刷新套餐"
                 : "重签名时需保留 App Group")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct TokenPlanLockScreenWidget: Widget {
    let kind = "TokenPlanLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenPlanProvider()) { entry in
            TokenPlanLockScreenView(entry: entry)
                .widgetURL(URL(string: "tokenplan://plans"))
        }
        .configurationDisplayName("TokenPlan 锁屏")
        .description("在锁屏上清晰查看套餐名称、窗口和用量。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TokenPlanLockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenPlanEntry

    private var primary: WidgetProfileSummary? { entry.snapshot.featuredProfile }
    private var tier: PlanUsageTier? { primary?.usage.primaryTier }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: tier?.clampedUtilization ?? 0, in: 0...100) {
                Image(systemName: "chart.bar.fill")
            } currentValueLabel: {
                if let tier {
                    Text("\(Int(tier.clampedUtilization.rounded()))")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                } else {
                    Image(systemName: "minus")
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(circularAccessibilityLabel)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill")
                    Text(primary?.name ?? "TokenPlan").font(.headline).lineLimit(1)
                    Spacer(minLength: 2)
                    if primary?.usage.status == .failed {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                }
                if let primary, !primary.usage.tiers.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(primary.usage.tiers.prefix(2)) { tier in
                            HStack(spacing: 3) {
                                Text(tier.title).foregroundStyle(.secondary)
                                Text(tier.percentageText).bold().monospacedDigit()
                            }
                        }
                    }
                    .font(.caption)
                    if let reset = primary.usage.primaryTier?.resetText {
                        Text(reset).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                } else if let balance = primary?.usage.balances.first {
                    Text("\(balance.currency) 余额  \(balance.totalBalance)")
                        .font(.subheadline.bold()).monospacedDigit()
                } else {
                    Text(primary?.usage.headline ?? (WidgetSnapshotStore.isAppGroupAvailable
                         ? "打开 App 刷新套餐"
                         : "签名缺少 App Group"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

        default:
            Label(inlineSummary, systemImage: "chart.bar.fill")
        }
    }

    private var inlineSummary: String {
        guard let primary else {
            return WidgetSnapshotStore.isAppGroupAvailable ? "TokenPlan 尚未共享套餐" : "TokenPlan 签名缺少 App Group"
        }
        let detail = primary.usage.compactDetail.isEmpty ? primary.usage.headline : primary.usage.compactDetail
        return "\(primary.name) · \(detail)"
    }

    private var circularAccessibilityLabel: String {
        guard let primary, let tier else {
            return WidgetSnapshotStore.isAppGroupAvailable ? "TokenPlan 尚无套餐用量" : "TokenPlan 签名缺少 App Group"
        }
        return "\(primary.name)，\(tier.title)，已使用 \(tier.percentageText)"
    }
}

@available(iOSApplicationExtension 16.1, *)
struct TokenPlanLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TokenPlanActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("TokenPlan", systemImage: "chart.bar.fill").font(.headline)
                    Spacer()
                    Text(context.state.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.primaryName).font(.subheadline.bold()).lineLimit(1)
                        Text(context.state.primaryMetricTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(context.state.primaryDetail)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
                if context.state.primaryProgress > 0 {
                    ProgressView(value: context.state.primaryProgress).tint(.indigo)
                }
                Text(context.state.secondaryDetail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding()
            .activityBackgroundTint(Color.indigo.opacity(0.10))
            .activitySystemActionForegroundColor(.indigo)
            .accessibilityElement(children: .combine)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("TokenPlan", systemImage: "chart.bar.fill").font(.caption.bold())
                        Text(context.state.primaryName).font(.caption2).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.primaryDetail)
                            .font(.title3.bold()).monospacedDigit()
                        Text(context.state.primaryMetricTitle)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5) {
                        if context.state.primaryProgress > 0 {
                            ProgressView(value: context.state.primaryProgress).tint(.indigo)
                        }
                        HStack {
                            Text(context.state.secondaryDetail).lineLimit(1)
                            Spacer()
                            Text(context.state.updatedAt, style: .relative).foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                    }
                }
            } compactLeading: {
                Image(systemName: "chart.bar.fill")
            } compactTrailing: {
                Text(context.state.primaryDetail)
                    .font(.caption2.bold()).monospacedDigit().lineLimit(1)
            } minimal: {
                Image(systemName: "chart.bar.fill")
            }
            .keylineTint(.indigo)
        }
    }
}

private func metricColor(_ utilization: Double) -> Color {
    if utilization >= 90 { return .red }
    if utilization >= 70 { return .orange }
    return .indigo
}

private extension View {
    @ViewBuilder
    func tokenPlanWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.13), Color.purple.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                for: .widget
            )
        } else {
            background(Color.indigo.opacity(0.10))
        }
    }
}

@main
struct TokenPlanWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenPlanHomeWidget()
        TokenPlanLockScreenWidget()
        if #available(iOSApplicationExtension 16.1, *) {
            TokenPlanLiveActivityWidget()
        }
    }
}
