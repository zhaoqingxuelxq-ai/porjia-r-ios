import SwiftUI

struct RootView: View {
    @EnvironmentObject var router: DeepLinkRouter
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            BreakerView().tabItem { Label("破甲", systemImage: "hammer.fill") }.tag(0)
            ChatView().tabItem { Label("对话", systemImage: "bubble.left.and.bubble.right.fill") }.tag(1)
            ModelsView().tabItem { Label("模型", systemImage: "network") }.tag(2)
            MCPView().tabItem { Label("MCP", systemImage: "plug.fill") }.tag(3)
            RulesView().tabItem { Label("规范", systemImage: "book.fill") }.tag(4)
            OffloadsView().tabItem { Label("能力", systemImage: "sparkles") }.tag(5)
            SyncView().tabItem { Label("同步", systemImage: "icloud") }.tag(6)
            ConfigView().tabItem { Label("配置", systemImage: "gearshape.fill") }.tag(7)
            AboutView().tabItem { Label("关于", systemImage: "info.circle.fill") }.tag(8)
        }
        .accentColor(Theme.brand)
        .onChange(of: router.page) { page in
            guard let p = page else { return }
            switch p {
            case "breaker": selection = 0
            case "chat": selection = 1
            case "mcp": selection = 3
            default: break
            }
            router.consume()
        }
    }
}
