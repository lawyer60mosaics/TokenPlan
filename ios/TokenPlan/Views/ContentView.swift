import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editingProfile: Profile?
    @State private var showingSync = false

    var body: some View {
        NavigationStack {
            Group {
                if model.profiles.isEmpty {
                    ContentUnavailableView(
                        "尚无套餐",
                        systemImage: "key.horizontal",
                        description: Text("从云端下载，或在此设备添加套餐。")
                    )
                } else {
                    List {
                        ForEach(model.profiles) { profile in
                            Button {
                                editingProfile = profile
                            } label: {
                                ProfileRow(profile: profile)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSync = true } label: {
                        Image(systemName: model.isSyncConfigured ? "icloud.fill" : "icloud")
                    }
                    .accessibilityLabel("云同步")
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                StatusBanner(message: model.errorMessage.isEmpty ? model.message : model.errorMessage,
                             isError: !model.errorMessage.isEmpty)
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.enabled ? "bolt.circle.fill" : "pause.circle")
                .font(.title2)
                .foregroundStyle(profile.enabled ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name).font(.headline)
                Text(Provider(rawValue: profile.provider)?.title ?? profile.provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
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
