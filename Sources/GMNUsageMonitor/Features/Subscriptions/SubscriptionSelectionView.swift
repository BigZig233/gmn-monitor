import SwiftUI

struct SubscriptionSelectionView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var aliasDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择监控订阅")
                .font(.headline)

            if let error = viewModel.authStore.lastError?.message ?? viewModel.subscriptionStore.lastError?.message {
                Text(error)
                    .foregroundStyle(.red)
            }

            List(viewModel.subscriptionStore.subscriptions, id: \.id) { subscription in
                Button {
                    viewModel.selectSubscription(subscription)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(subscription.groupName)
                            Spacer()
                            Text(subscription.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !subscription.groupDescription.isEmpty {
                            Text(subscription.groupDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let percent = subscription.usage.daily?.percent {
                            Text("Daily \(percent.formatted(.number.precision(.fractionLength(1))))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if subscription.unlimited {
                            Text("无限额度")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 260)

            TextField("Dock alias", text: $aliasDraft)
            Button("保存 alias") {
                viewModel.saveAlias(aliasDraft)
            }
            .disabled(viewModel.settingsStore.selectedSubscriptionID == nil)
        }
        .onAppear {
            aliasDraft = viewModel.settingsStore.selectedSubscriptionAlias
        }
        .onChange(of: viewModel.settingsStore.selectedSubscriptionID) {
            aliasDraft = viewModel.settingsStore.selectedSubscriptionAlias
        }
    }
}
