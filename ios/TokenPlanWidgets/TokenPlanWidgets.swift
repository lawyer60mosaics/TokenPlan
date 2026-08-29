import ActivityKit
import SwiftUI
import WidgetKit

struct TokenPlanEntry: TimelineEntry {
    let date: Date
    let snapshot: TokenPlanWidgetSnapshot
}

struct TokenPlanProvider: TimelineProvider {
    func placeholder(in context: Context) -> TokenPlanEntry {
        TokenPlanEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenPlanEntry) -> Void) {
        completion(TokenPlanEntry(date: Date(), snapshot: context.isPreview ? .placeholder : WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenPlanEntry>) -> Void) {
        let entry = TokenPlanEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct TokenPlanHomeWidget: Widget {
    let kind = "TokenPlanHomeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenPlanProvider()) { entry in
            TokenPlanHomeWidgetView(entry: entry)
                .tokenPlanWidgetBackground()
        }
        .configurationDisplayName("TokenPlan 套餐")
        .description("在桌面查看已启用套餐。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct TokenPlanHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenPlanEntry

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        default:
            large
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "key.horizontal.fill")
                .foregroundStyle(.indigo)
            Text("TokenPlan").font(.headline)
            Spacer()
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer()
            Text("\(entry.snapshot.enabledCount)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
            Text("个套餐已启用")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var medium: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                header
                Text("\(entry.snapshot.enabledCount) / \(entry.snapshot.totalCount)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("启用 / 全部套餐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                ForEach(entry.snapshot.profiles.prefix(3)) { profile in
                    Label(profile.name, systemImage: profile.enabled ? "bolt.circle.fill" : "pause.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(profile.enabled ? .primary : .secondary)
                        .lineLimit(1)
                }
                if entry.snapshot.profiles.isEmpty {
                    Text("尚无套餐").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.snapshot.enabledCount)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text("/ \(entry.snapshot.totalCount) 个套餐已启用")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            ForEach(entry.snapshot.profiles.prefix(6)) { profile in
                HStack(spacing: 9) {
                    Image(systemName: profile.enabled ? "bolt.circle.fill" : "pause.circle")
                        .foregroundStyle(profile.enabled ? .indigo : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(profile.provider).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(profile.enabled ? "启用" : "暂停")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(entry.snapshot.updatedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct TokenPlanLockScreenWidget: Widget {
    let kind = "TokenPlanLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenPlanProvider()) { entry in
            TokenPlanLockScreenView(entry: entry)
        }
        .configurationDisplayName("TokenPlan 锁屏")
        .description("在锁屏上查看套餐状态。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct TokenPlanLockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenPlanEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.snapshot.enabledCount), in: 0...Double(max(entry.snapshot.totalCount, 1))) {
                Image(systemName: "key.horizontal")
            } currentValueLabel: {
                Text("\(entry.snapshot.enabledCount)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("TokenPlan", systemImage: "key.horizontal.fill").font(.headline)
                Text("\(entry.snapshot.enabledCount) / \(entry.snapshot.totalCount) 个套餐启用")
                    .font(.caption)
                Text(entry.snapshot.profiles.first(where: { $0.enabled })?.name ?? "尚无启用套餐")
                    .font(.caption2)
                    .lineLimit(1)
            }
        default:
            Label("TokenPlan：\(entry.snapshot.enabledCount) 个套餐启用", systemImage: "key.horizontal.fill")
        }
    }
}

@available(iOSApplicationExtension 16.1, *)
struct TokenPlanLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TokenPlanActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "key.horizontal.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TokenPlan").font(.headline)
                    Text("\(context.state.enabledCount) / \(context.state.totalCount) 个套餐启用")
                        .font(.subheadline)
                    Text(context.state.primaryName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color.indigo.opacity(0.12))
            .activitySystemActionForegroundColor(.indigo)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("TokenPlan", systemImage: "key.horizontal.fill")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.enabledCount)/\(context.state.totalCount)")
                        .font(.title3.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.primaryName).lineLimit(1)
                        Spacer()
                        Text(context.state.updatedAt, style: .relative).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "key.horizontal.fill")
            } compactTrailing: {
                Text("\(context.state.enabledCount)").font(.caption.bold())
            } minimal: {
                Image(systemName: "key.horizontal.fill")
            }
            .keylineTint(.indigo)
        }
    }
}

private extension View {
    @ViewBuilder
    func tokenPlanWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(Color.indigo.opacity(0.12), for: .widget)
        } else {
            background(Color.indigo.opacity(0.12))
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
