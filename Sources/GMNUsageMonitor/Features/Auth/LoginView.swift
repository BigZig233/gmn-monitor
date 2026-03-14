import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            TextField("邮箱", text: $viewModel.email)
            SecureField("密码", text: $viewModel.password)
            TextField("TOTP Secret，可选", text: $viewModel.totpSecret)
            Toggle("保存凭据用于自动重登", isOn: $viewModel.rememberCredentials)
            Button("登录") {
                Task { await viewModel.submitLogin() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.email.isEmpty || viewModel.password.isEmpty || viewModel.isBusy)
        }
        .formStyle(.grouped)
    }
}
