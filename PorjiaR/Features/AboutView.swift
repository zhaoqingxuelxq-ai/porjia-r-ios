import SwiftUI

struct AboutView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color.red)
                                .frame(width: 64, height: 64).rotationEffect(.degrees(-6))
                            Text("R").font(.largeTitle.weight(.bold)).foregroundColor(.white)
                        }
                        Text("破甲 R").font(.title.weight(.bold))
                        Text("V9 全功能 · iOS 原生版").font(.subheadline).foregroundColor(.secondary)
                        Text("版本 1.0 (1)").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity).padding(.top, 20)

                    GroupBox("核心能力") {
                        VStack(alignment: .leading, spacing: 6) {
                            FeatureLine(icon: "hammer.fill", text: "破甲引擎：Swift 原生解析 Mach-O / IPA，8 子命令")
                            FeatureLine(icon: "network", text: "模型路由：内置 223 供应商 / 8080 模型目录")
                            FeatureLine(icon: "book.fill", text: "V9 规范库：16+ 章内置，离线可查")
                            FeatureLine(icon: "gearshape.fill", text: "配置管理：四类条目本地增删启停")
                            FeatureLine(icon: "hand.raised.fill", text: "patch 安全：等长替换 + 原字节校验 + 自动备份")
                        }
                    }

                    GroupBox("安装与兼容") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• 安装：TrollStore 导入本 IPA，点击安装")
                            Text("• 系统：iOS 15.0 – 16.6.1 / 17.0（TrollStore 支持范围）")
                            Text("• 设备：iPhone / iPad，arm64 / arm64e")
                            Text("• 签名：TrollStore 会绕过签名校验，无需 App Store 签名")
                            Text("• 网络：核心功能完全离线，不依赖服务器")
                        }.font(.caption).foregroundColor(.secondary)
                    }

                    GroupBox("数据处理") {
                        Text("所有分析在本机沙箱完成。导入的文件只存于 App 文档目录，不上传。配置/记忆以 JSON 原子写落盘。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("关于")
        }
        .navigationViewStyle(.stack)
    }
}

private struct FeatureLine: View {
    let icon: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundColor(.red).frame(width: 20)
            Text(text).font(.caption)
            Spacer()
        }
    }
}
