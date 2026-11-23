import Foundation
import UIKit
import AuthenticationServices

/// OAuth 框架：ASWebAuthenticationSession 拉起系统浏览器授权，回调 code 存 Keychain。
/// TrollStore 环境无 Associated Domains，自定义 scheme 回调可能不可用，
/// 因此同时支持"手动粘贴 token"降级路径。
final class OAuthManager: NSObject {
    static let shared = OAuthManager()

    struct Provider: Identifiable {
        let id: String
        let name: String
        let authURL: String
        let tokenURL: String
        let clientID: String
        let scheme: String
    }

    let providers: [Provider] = [
        Provider(id: "github", name: "GitHub PAT",
                 authURL: "https://github.com/login/oauth/authorize",
                 tokenURL: "https://github.com/login/oauth/access_token",
                 clientID: "", scheme: "porjiar"),
        Provider(id: "kimi", name: "Kimi（设备码）",
                 authURL: "https://auth.kimi.com/api/oauth/authorize",
                 tokenURL: "https://auth.kimi.com/api/oauth/token",
                 clientID: "17e5f671-0000-0000-0000-000000000000", scheme: "porjiar"),
    ]

    /// 手动粘贴的 token（降级路径）——存入 Keychain，键名 OAUTH_<provider>
    @discardableResult
    func saveManualToken(_ token: String, provider: String) -> Bool {
        return KeychainStore.shared.set(token, for: "OAUTH_\(provider.uppercased())")
    }

    func token(_ provider: String) -> String? {
        return KeychainStore.shared.get("OAUTH_\(provider.uppercased())")
    }

    /// 尝试系统浏览器授权（结果通过 session 回调，需 App 支持 scheme）
    @discardableResult
    func start(_ provider: Provider, from anchor: ASPresentationAnchor?) -> Bool {
        guard var comps = URLComponents(string: provider.authURL) else { return false }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "client_id", value: provider.clientID))
        items.append(URLQueryItem(name: "redirect_uri", value: "\(provider.scheme)://oauth/\(provider.id)"))
        items.append(URLQueryItem(name: "response_type", value: "code"))
        comps.queryItems = items
        guard let url = comps.url else { return false }
        let session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: provider.scheme) { callbackURL, error in
            guard error == nil, let cb = callbackURL,
                  let code = URLComponents(url: cb, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            // code → token 需要后端交换；TrollStore 无服务端，这里仅保存 code 供手动完成
            KeychainStore.shared.set(code, for: "OAUTH_CODE_\(provider.id.uppercased())")
        }
        session.presentationContextProvider = self
        session.start()
        return true
    }
}

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            return window
        }
        return ASPresentationAnchor()
    }
}
