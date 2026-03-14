import SwiftUI

struct TwoFactorView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            if let masked = viewModel.authStore.pendingTwoFactor?.userEmailMasked, !masked.isEmpty {
                Text("账号 \(masked) 需要输入 2FA 验证码。")
                    .foregroundStyle(.secondary)
            }
            TextField("6 位验证码", text: $viewModel.manualTotpCode)
            HStack {
                Button("返回") {
                    Task { await viewModel.logout() }
                }
                Button("完成 2FA 登录") {
                    Task { await viewModel.submitTwoFactor() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.manualTotpCode.isEmpty || viewModel.isBusy)
            }
        }
        .formStyle(.grouped)
    }
}
