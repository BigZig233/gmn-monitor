import SwiftUI

struct MonitorSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var aliasDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let subscription = viewModel.subscriptionStore.selectedSubscription {
                VStack(alignment: .leading, spacing: 6) {
                    Text(subscription.groupName)
                        .font(.headline)
                    if !subscription.groupDescription.isEmpty {
                        Text(subscription.groupDescription)
                            .foregroundStyle(.secondary)
                    }
                    Text("状态：\(subscription.status)")
                        .font(.subheadline)
                    if let percent = subscription.usage.daily?.percent {
                        Text("Daily usage: \(percent.formatted(.number.precision(.fractionLength(1))))%")
                    }
                }
            }

            TextField("Dock alias", text: $aliasDraft)
            Button("保存 alias") {
                viewModel.saveAlias(aliasDraft)
            }

            Picker("刷新间隔", selection: Binding(get: {
                viewModel.settingsStore.refreshIntervalPreset
            }, set: {
                viewModel.updateRefreshPreset($0)
            })) {
                ForEach(RefreshIntervalPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            HStack {
                Button("立即刷新") {
                    Task { await viewModel.refreshNow() }
                }
                .buttonStyle(.borderedProminent)

                Button("重新选择订阅") {
                    viewModel.clearSelectedSubscription()
                }

                Button("退出登录") {
                    Task { await viewModel.logout() }
                }

                Button("清除保存状态") {
                    viewModel.clearSavedState()
                }
            }
        }
        .onAppear {
            aliasDraft = viewModel.settingsStore.selectedSubscriptionAlias
        }
    }
}
