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

                    Card {
                        SectionTitle(icon: "star.fill", title: "核心能力")
                        VStack(alignment: .leading, spacing: 8) {
                            FeatureLine(icon: "hammer.fill", text: "破甲引擎：Swift 原生解析 Mach-O / IPA，8 子命令（离线）")
                            FeatureLine(icon: "bubble.left.and.bubble.right.fill", text: "在线对话：223 供应商 / 8080 模型，OpenAI + Anthropic 双协议流式")
                            FeatureLine(icon: "plug.fill", text: "MCP 客户端：JSON-RPC 2.0 over HTTP，SSE 兼容")
                            FeatureLine(icon: "sparkles", text: "原生能力：剪贴板 / 定位 / 相册 OCR（主动触发）")
                            FeatureLine(icon: "icloud", text: "同步：本地快照导入导出，iCloud 可用时自动同步")
                            FeatureLine(icon: "book.fill", text: "V9 规范库：17 章内置，离线可查")
                            FeatureLine(icon: "hand.raised.fill", text: "patch 安全：等长替换 + 原字节校验 + 自动备份")
                        }
                    }

                    Card {
                        SectionTitle(icon: "iphone", title: "安装与兼容", tint: .blue)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("• 安装：TrollStore 导入本 IPA，点击安装")
                            Text("• 系统：iOS 15.0 – 16.6.1 / 17.0（TrollStore 支持范围）")
                            Text("• 设备：iPhone / iPad，arm64 / arm64e")
                            Text("• 签名：ad-hoc 未签名，TrollStore 绕过校验")
                            Text("• 网络：破甲引擎纯本地；在线对话/MCP 需联网")
                        }.font(.caption).foregroundColor(Theme.text2)
                    }

                    Card {
                        SectionTitle(icon: "lock.shield", title: "数据处理", tint: .green)
                        Text("破甲分析在本机沙箱完成，导入文件不上传。API Key / OAuth 令牌只存系统钥匙串，不进配置与日志；同步快照只导出 Key 名，不导出 Key 值。在线对话默认不附带分析结果，需手动开启。")
                            .font(.caption).foregroundColor(Theme.text2)
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
