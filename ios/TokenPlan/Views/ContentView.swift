import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingProfile: Profile?
    @State private var showingSync = false

    var body: some View {
        NavigationStack {
            Group {
                if model.profiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("尚无套餐")
                            .font(.title2.bold())
                        Text("从云端下载，或在此设备添加套餐。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                } else {
                    List {
                        ForEach(model.profiles) { profile in
                            Button {
                                editingProfile = profile
                            } label: {
                                ProfileRow(profile: profile, usage: model.usageByProfile[profile.id] ?? .waiting)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            Task { await model.delete(at: offsets) }
                        }
                    }
                }
            }
            .navigationTitle("TokenPlan")
            .navigationBarItems(
                leading: Button {
                    showingSync = true
                } label: {
                    Image(systemName: model.isSyncConfigured ? "icloud.fill" : "icloud")
                }
                .accessibilityLabel("云同步"),
                trailing: HStack {
                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                    .accessibilityLabel("刷新套餐用量")
                    Button {
                        editingProfile = Profile()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增套餐")
                }
            )
            .sheet(item: $editingProfile) { profile in
                ProfileEditorView(profile: profile)
            }
            .sheet(isPresented: $showingSync) {
                SyncSettingsView()
            }
            .overlay(alignment: .bottom) {
                StatusBanner(message: model.errorMessage.isEmpty ? model.message : model.errorMessage,
                             isError: !model.errorMessage.isEmpty)
            }
            .refreshable { await model.refreshAll() }
            .task {
                await model.refreshAll()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if !Task.isCancelled { await model.refreshAll() }
                }
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile
    let usage: PlanUsage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: profile.enabled ? "bolt.circle.fill" : "pause.circle")
                .font(.title2)
                .foregroundStyle(profile.enabled ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name).font(.headline)
                HStack {
                    Text(Provider(rawValue: profile.provider)?.title ?? profile.provider)
                    Spacer()
                    Text(statusText).foregroundStyle(statusColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(usage.tiers.prefix(3)) { tier in
                    VStack(spacing: 2) {
                        HStack {
                            Text(tier.title)
                            Spacer()
                            Text("\(Int(tier.utilization.rounded()))%")
                        }
                        .font(.caption2)
                        ProgressView(value: min(max(tier.utilization, 0), 100), total: 100)
                            .tint(tier.utilization >= 90 ? .red : .blue)
                        if let reset = tier.resetsAt {
                            Text("重置：\(reset)")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                ForEach(usage.balances) { balance in
                    HStack {
                        Text(balance.currency)
                        Spacer()
                        Text(balance.totalBalance).fontWeight(.semibold)
                    }
                    .font(.caption2)
                    Text("赠送 \(balance.grantedBalance) · 充值 \(balance.toppedUpBalance)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                if let error = usage.error, usage.tiers.isEmpty, usage.balances.isEmpty {
                    Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var statusText: String {
        switch usage.status {
        case .success: return usage.plan ?? "已更新"
        case .loading: return "刷新中…"
        case .failed: return "刷新失败"
        case .paused: return "已暂停"
        case .waiting: return "等待刷新"
        }
    }

    private var statusColor: Color {
        usage.status == .failed ? .red : .secondary
    }
}

private struct StatusBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        if !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundStyle(isError ? Color.red : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding()
        }
    }
}
