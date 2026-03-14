import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GMN Usage Monitor")
                .font(.title)
                .bold()

            if !viewModel.message.isEmpty {
                Text(viewModel.message)
                    .foregroundStyle(.secondary)
            }

            switch viewModel.phase {
            case .login:
                LoginView()
            case .twoFactor:
                TwoFactorView()
            case .selectSubscription:
                SubscriptionSelectionView()
            case .monitor:
                MonitorSettingsView()
            }
        }
        .padding(24)
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.appDidBecomeActive() }
        }
    }
}
