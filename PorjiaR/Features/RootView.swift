import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            BreakerView()
                .tabItem { Label("破甲", systemImage: "hammer.fill") }
            ModelsView()
                .tabItem { Label("模型", systemImage: "network") }
            RulesView()
                .tabItem { Label("规范", systemImage: "book.fill") }
            ConfigView()
                .tabItem { Label("配置", systemImage: "gearshape.fill") }
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle.fill") }
        }
        .accentColor(.red)
    }
}
