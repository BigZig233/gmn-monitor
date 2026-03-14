import Foundation

enum GMNAPIError: LocalizedError, Sendable {
    case api(message: String, code: String?, status: Int)
    case authenticationRequired
    case twoFactorRequired(tempToken: String, userEmailMasked: String)
    case network
    case decoding
    case turnstileEnabled

    var errorDescription: String? {
        switch self {
        case let .api(message, _, _):
            message
        case .authenticationRequired:
            "登录态已失效，需要重新登录。"
        case .twoFactorRequired:
            "需要输入 2FA 验证码。"
        case .network:
            "网络请求失败。"
        case .decoding:
            "响应解析失败。"
        case .turnstileEnabled:
            "当前站点已启用 Turnstile，自动重登需要人工介入。"
        }
    }

    var codeValue: String? {
        switch self {
        case let .api(_, code, _):
            code
        case .authenticationRequired:
            "AUTH_REQUIRED"
        case .twoFactorRequired:
            "TWO_FACTOR_REQUIRED"
        case .network:
            "NETWORK_ERROR"
        case .decoding:
            "DECODING_ERROR"
        case .turnstileEnabled:
            "TURNSTILE_ENABLED"
        }
    }

    var statusValue: Int {
        switch self {
        case let .api(_, _, status):
            status
        case .authenticationRequired:
            401
        case .twoFactorRequired:
            202
        case .network:
            502
        case .decoding:
            500
        case .turnstileEnabled:
            400
        }
    }

    var appErrorState: AppErrorState {
        AppErrorState(name: String(describing: self), message: errorDescription ?? "", code: codeValue, status: statusValue, at: .now)
    }
}
