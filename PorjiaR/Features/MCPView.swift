import SwiftUI

/// MCP 管理页：服务器 CRUD（Claude Desktop servers.json 格式）+ 连通性测试 + tools/list 查看。
struct MCPView: View {
    @State private var servers = MCPClient.shared.servers()
    @State private var showAdd = false
    @State private var editing: MCPClient.Server?
    @State private var toolsResult = ""
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    Card {
                        SectionTitle(icon: "plug", title: "MCP 服务器", tint: .orange)
                        Text("JSON-RPC 2.0 over HTTP。Key 用 $VAR_NAME 引用，运行时从钥匙串展开。")
                            .font(.caption).foregroundColor(Theme.text2)
                    }

                    if servers.isEmpty {
                        EmptyHint(icon: "plug", text: "还没有 MCP 服务器，点右上角 + 添加")
                    } else {
                        ForEach(servers) { s in
                            Card {
                                HStack {
                                    Image(systemName: s.enabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(s.enabled ? .green : .gray)
                                        .onTapGesture { toggle(s) }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.name.isEmpty ? "(未命名)" : s.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(s.url).font(.caption2).foregroundColor(.blue).lineLimit(1)
                                    }
                                    Spacer()
                                    Button("编辑") { editing = s }.font(.caption).buttonStyle(.bordered)
                                }
                                HStack {
                                    Button("测试连通") { test(s) }.font(.caption).buttonStyle(.bordered)
                                    Button("列出工具") { listTools(s) }.font(.caption).buttonStyle(.bordered)
                                    Spacer()
                                    Button(role: .destructive) { remove(s) } label: {
                                        Image(systemName: "trash").font(.caption)
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }

                    if !status.isEmpty {
                        HStack {
                            Label(status, systemImage: "info.circle").font(.caption)
                            Spacer()
                            if busy { ProgressView() }
                        }.foregroundColor(Theme.text2)
                    }

                    if !toolsResult.isEmpty {
                        Card {
                            SectionTitle(icon: "wrench", title: "工具列表", tint: .purple)
                            ScrollView {
                                Text(toolsResult).font(Theme.mono).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(maxHeight: 260)
                        }
                    }

                    Text("stdio 传输在 iOS 上不可用（无法 spawn 任意子进程），本客户端仅支持 HTTP / streamable-HTTP 端点。")
                        .font(.caption2).foregroundColor(Theme.text2)
                }
                .padding()
            }
            .navigationTitle("MCP 连接")
            .toolbar {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
            .sheet(isPresented: $showAdd) {
                ServerEditView(server: MCPClient.Server()) { new in
                    servers.append(new); MCPClient.shared.save(servers)
                }
            }
            .sheet(item: $editing) { s in
                ServerEditView(server: s) { updated in
                    if let i = servers.firstIndex(where: { $0.id == updated.id }) { servers[i] = updated }
                    MCPClient.shared.save(servers)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func toggle(_ s: MCPClient.Server) {
        if let i = servers.firstIndex(where: { $0.id == s.id }) {
            servers[i].enabled.toggle(); MCPClient.shared.save(servers)
        }
    }

    private func remove(_ s: MCPClient.Server) {
        servers.removeAll { $0.id == s.id }; MCPClient.shared.save(servers)
    }

    private func test(_ s: MCPClient.Server) {
        busy = true; status = "测试 \(s.name)…"
        Task {
            let r = await MCPClient.shared.test(s)
            DispatchQueue.main.async {
                busy = false
                status = r.ok ? "\(s.name): 连通" : "\(s.name): \(r.error ?? "失败")"
            }
        }
    }

    private func listTools(_ s: MCPClient.Server) {
        busy = true; status = "读取 \(s.name) 工具列表…"
        Task {
            let r = await MCPClient.shared.tools(s)
            DispatchQueue.main.async {
                busy = false
                if r.ok {
                    toolsResult = r.jsonString
                    status = "工具列表已载入"
                } else {
                    status = "失败: \(r.error ?? "")"
                }
            }
        }
    }
}

/// 服务器编辑卡
struct ServerEditView: View {
    @State var server: MCPClient.Server
    let onSave: (MCPClient.Server) -> Void
    @Environment(\.presentationMode) var mode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("名称")) {
                    TextField("本地 / 远程服务名", text: $server.name)
                }
                Section(header: Text("HTTP 端点")) {
                    TextField("https://.../mcp", text: $server.url)
                        .autocapitalization(.none).disableAutocorrection(true)
                        .keyboardType(.URL)
                }
                Section(header: Text("请求头（Key: Value，每行一条）")) {
                    TextEditor(text: Binding(
                        get: { server.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n") },
                        set: { text in
                            var h: [String: String] = [:]
                            for line in text.split(separator: "\n") {
                                let parts = line.split(separator: ":", maxSplits: 1)
                                if parts.count == 2 {
                                    h[parts[0].trimmingCharacters(in: .whitespaces)] =
                                        parts[1].trimmingCharacters(in: .whitespaces)
                                }
                            }
                            server.headers = h
                        }))
                        .frame(minHeight: 80)
                        .font(Theme.mono)
                }
                Section {
                    Toggle("启用", isOn: $server.enabled)
                }
                Section {
                    Text("示例：\nAuthorization: Bearer $MY_TOKEN\nX-API-Key: $OTHER_KEY")
                        .font(.caption2).foregroundColor(Theme.text2)
                }
            }
            .navigationTitle("MCP 服务器")
            .toolbar {
                Button("保存") { onSave(server); mode.wrappedValue.dismiss() }
                Button("取消") { mode.wrappedValue.dismiss() }
            }
        }
        .navigationViewStyle(.stack)
    }
}
