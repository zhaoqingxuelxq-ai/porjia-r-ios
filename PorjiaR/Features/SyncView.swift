import SwiftUI
import UniformTypeIdentifiers

/// 同步/备份页：本地快照导入导出 + OAuth token 手动降级 + 状态说明。
struct SyncView: View {
    @State private var statusText = SyncEngine.shared.summary()
    @State private var showImport = false
    @State private var showExport = false
    @State private var oauthProvider = "github"
    @State private var oauthToken = ""
    @State private var oauthMsg = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Card {
                        SectionTitle(icon: "icloud", title: "同步状态", tint: .blue)
                        Label(statusText, systemImage: "info.circle").font(.caption).foregroundColor(Theme.text2)
                        Text("TrollStore 安装的 ad-hoc 签名 App 通常拿不到 iCloud 容器，自动同步降级为本地快照。可手动导出后传到另一台设备导入。")
                            .font(.caption2).foregroundColor(Theme.text2)
                    }

                    Card {
                        SectionTitle(icon: "square.and.arrow.up", title: "备份与恢复", tint: .green)
                        HStack {
                            Button("导出快照") {
                                if SyncEngine.shared.exportToFile() != nil {
                                    showExport = true
                                    statusText = SyncEngine.shared.summary()
                                }
                            }.buttonStyle(.bordered)
                            Button("导入快照") { showImport = true }.buttonStyle(.bordered)
                        }
                        Text("导出内容含配置/记忆/会话/MCP 配置与 Key 名清单；**不含 API Key 值**（Key 只在钥匙串）。")
                            .font(.caption2).foregroundColor(Theme.text2)
                    }

                    Card {
                        SectionTitle(icon: "key.fill", title: "OAuth 令牌（手动降级）", tint: .orange)
                        Picker("服务", selection: $oauthProvider) {
                            Text("GitHub PAT").tag("github")
                            Text("Kimi").tag("kimi")
                        }.pickerStyle(.segmented)
                        SecureField("粘贴 token / PAT", text: $oauthToken)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                        HStack {
                            Button("保存令牌") {
                                if OAuthManager.shared.saveManualToken(oauthToken, provider: oauthProvider) {
                                    oauthMsg = "已存入钥匙串"
                                    oauthToken = ""
                                } else { oauthMsg = "保存失败" }
                            }.buttonStyle(.bordered).disabled(oauthToken.isEmpty)
                            if OAuthManager.shared.token(oauthProvider) != nil {
                                Button("删除", role: .destructive) {
                                    KeychainStore.shared.delete("OAUTH_\(oauthProvider.uppercased())")
                                    oauthMsg = "已删除"
                                }.buttonStyle(.bordered)
                            }
                        }
                        if !oauthMsg.isEmpty { Text(oauthMsg).font(.caption).foregroundColor(Theme.text2) }
                        Text("系统浏览器授权（ASWebAuthenticationSession）在 TrollStore 环境可能无回调域名；手动粘贴走同一钥匙串存储。")
                            .font(.caption2).foregroundColor(Theme.text2)
                    }

                    Card {
                        SectionTitle(icon: "clock", title: "后台任务", tint: .purple)
                        let last = BackgroundTasks.shared.lastRun() ?? "从未"
                        Text("上次后台调度：\(last)").font(.caption)
                        Text("策略 best-effort：进程死亡即终止，不自动执行危险 agent 循环。")
                            .font(.caption2).foregroundColor(Theme.text2)
                    }
                }
                .padding()
            }
            .navigationTitle("同步与令牌")
            .fileImporter(isPresented: $showImport,
                          allowedContentTypes: [.json, .data], allowsMultipleSelection: false) { res in
                if case .success(let urls) = res, let u = urls.first {
                    statusText = SyncEngine.shared.importFromFile(u) ? "导入成功" : "导入失败（格式不匹配）"
                }
            }
            .fileExporter(isPresented: $showExport,
                          document: SnapshotDocument(url: SyncEngine.shared.exportToFile() ?? Store.shared.root),
                          contentType: .json, defaultFilename: "porjia-snapshot.json") { _ in }
        }
        .navigationViewStyle(.stack)
    }
}

/// 文件导出包装（指向已写好的快照文件）
struct SnapshotDocument: FileDocument {
    let url: URL
    static var readableContentTypes: [UTType] { [.json] }
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { self.url = URL(fileURLWithPath: "/dev/null") }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let d = (try? Data(contentsOf: url)) ?? Data()
        return FileWrapper(regularFileWithContents: d)
    }
}
