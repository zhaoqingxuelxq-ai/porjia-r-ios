import SwiftUI

@main
struct PorjiaRApp: App {
    @StateObject private var router = DeepLinkRouter()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .onOpenURL { url in router.handle(url) }
                .onChange(of: phase) { new in
                    if new == .background { BackgroundTasks.shared.schedule() }
                }
        }
    }
}

/// URL scheme 路由：porjiar://analyze?path=... 直达破甲页；porjiar://chat / //mcp。
final class DeepLinkRouter: ObservableObject {
    @Published var page: String? = nil
    @Published var path: String? = nil

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "porjiar" else { return }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        switch (url.host ?? "").lowercased() {
        case "analyze", "breaker":
            path = q?.first(where: { $0.name == "path" })?.value
            page = "breaker"
        case "chat":
            page = "chat"
        case "mcp":
            page = "mcp"
        default:
            page = nil
        }
    }

    func consume() { page = nil; path = nil }
}
