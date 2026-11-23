import SwiftUI

/// 在线对话页：复用内置模型路由表 + Keychain Key，流式调用在线模型。
/// 破甲分析结果可显式注入为上下文（默认关闭），写操作永不由模型直接触发。
struct ChatView: View {
    @State private var providerID = "deepseek"
    @State private var modelID = ""
    @State private var input = ""
    @State private var output = ""
    @State private var busy = false
    @State private var attachReport = false
    @State private var status = "选择供应商与模型后开始对话"
    @State private var showSettings = false

    private let ds = DataSources.shared
    private let mc = ModelClient.shared

    private var providers: [DataSources.ProviderRow] { ds.searchProviders("") }
    private var selectedProvider: [String: Any]? { ds.provider(providerID) }
    private var models: [DataSources.ModelInfo] { ds.models(of: providerID) }
    private var envKey: String { ds.envKeys(providerID).first ?? "\(providerID.uppercased())_API_KEY" }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.gap) {
                    // 路由选择卡
                    Card {
                        SectionTitle(icon: "network", title: "模型路由", tint: .blue)
                        Picker("供应商", selection: $providerID) {
                            ForEach(providers.prefix(80)) { p in
                                Text("\(p.id) (\(p.modelCount))").tag(p.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: providerID) { _ in
                            modelID = models.first?.id ?? ""
                        }
                        Picker("模型", selection: $modelID) {
                            ForEach(models.prefix(120)) { m in Text(m.name).tag(m.id) }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Image(systemName: "key.fill").foregroundColor(Theme.warn)
                            Text("Key·\(envKey)").font(.caption).foregroundColor(Theme.text2)
                            Spacer()
                            Text(KeychainStore.shared.masked(envKey)).font(.caption2).foregroundColor(Theme.text2)
                        }
                        Button("设置 API Key") { showSettings = true }
                            .font(.caption).buttonStyle(.bordered)

                        Toggle("附带最近破甲分析结果作为上下文（默认关闭）", isOn: $attachReport)
                            .font(.caption)
                    }

                    // 输入
                    Card {
                        SectionTitle(icon: "bubble.left.and.bubble.right", title: "对话", tint: .purple)
                        TextEditor(text: $input)
                            .frame(minHeight: 70)
                            .font(.body)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.sep, lineWidth: 0.5))
                        PrimaryButton(title: "发送", icon: "paperplane.fill",
                                      busy: busy, disabled: input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelID.isEmpty) {
                            send()
                        }
                        HStack {
                            Button("连通性测试") { test() }.font(.caption).buttonStyle(.bordered).disabled(busy)
                            Button("清空") { output = ""; status = "已清空" }.font(.caption).buttonStyle(.bordered)
                        }
                    }

                    // 状态 + 输出
                    Card {
                        HStack {
                            Label(status, systemImage: busy ? "hourglass" : "checkmark.circle")
                                .font(.caption).foregroundColor(busy ? Theme.warn : Theme.text2)
                            Spacer()
                            if !output.isEmpty {
                                Button { copyOutput() } label: {
                                    Image(systemName: "doc.on.doc").font(.caption)
                                }.buttonStyle(.plain)
                            }
                        }
                        ScrollView {
                            Text(output.isEmpty ? "—" : output)
                                .font(.system(.body, design: .default))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 160, maxHeight: 360)
                    }

                    Text("模型输出仅用于分析与建议；patch 写入始终在破甲页由你手动确认，模型无权直接改文件。")
                        .font(.caption2).foregroundColor(Theme.text2)
                }
                .padding()
            }
            .navigationTitle("在线对话")
            .onAppear { if modelID.isEmpty { modelID = models.first?.id ?? "" } }
            .sheet(isPresented: $showSettings) { KeySettingView(keyName: envKey) }
        }
        .navigationViewStyle(.stack)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let key = KeychainStore.shared.get(envKey), !key.isEmpty else {
            status = "请先在「设置 API Key」中填写 \(envKey)"
            return
        }
        guard let route = mc.route(providerID: providerID, model: modelID, key: key) else {
            status = "路由构造失败，检查 provider 的 api 字段"
            return
        }
        input = ""
        output = ""
        busy = true
        status = "请求中…"
        var messages: [[String: Any]] = []
        var system = "你是破甲 R 的逆向分析助手。给出可执行、参数完整的技术结论。"
        if attachReport {
            let rep = Store.shared.load("last_report", default: [:])["text"] as? String ?? ""
            if !rep.isEmpty { system += "\n\n[最近破甲分析结果]\n\(rep.prefix(6000))" }
        }
        messages.append(["role": "system", "content": system])
        messages.append(["role": "user", "content": text])

        Task {
            let res = await mc.stream(route, messages: messages) { token in
                DispatchQueue.main.async { self.output += token }
            }
            DispatchQueue.main.async {
                busy = false
                if res.ok {
                    status = "完成 · \(res.ms) ms"
                } else {
                    status = "错误: \(res.error ?? "未知")"
                    if output.isEmpty { output = res.error ?? "" }
                }
            }
        }
    }

    private func test() {
        guard let key = KeychainStore.shared.get(envKey), !key.isEmpty else {
            status = "请先设置 API Key"; return
        }
        guard let route = mc.route(providerID: providerID, model: modelID, key: key) else { return }
        busy = true; status = "测试中…"
        Task {
            let res = await mc.testConnection(route)
            DispatchQueue.main.async {
                busy = false
                status = res.ok ? "连通正常 · \(res.ms) ms" : "失败: \(res.error ?? "")"
            }
        }
    }

    private func copyOutput() { UIPasteboard.general.string = output }
}

/// API Key 设置卡（Keychain 写入，UI 只显掩码）
struct KeySettingView: View {
    let keyName: String
    @State private var value = ""
    @State private var msg = ""
    @Environment(\.presentationMode) var mode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("环境变量名")) {
                    Text(keyName).font(.system(.caption, design: .monospaced))
                }
                Section(header: Text("API Key（写入系统钥匙串，仅本机）")) {
                    SecureField("sk-...", text: $value)
                        .autocapitalization(.none).disableAutocorrection(true)
                }
                Section {
                    Button("保存") {
                        let ok = KeychainStore.shared.set(value, for: keyName)
                        msg = ok ? "已保存到 Keychain" : "保存失败"
                        if ok { mode.wrappedValue.dismiss() }
                    }.disabled(value.isEmpty)
                    if KeychainStore.shared.get(keyName) != nil {
                        Button("删除已保存的 Key", role: .destructive) {
                            KeychainStore.shared.delete(keyName)
                            msg = "已删除"; value = ""
                        }
                    }
                }
                if !msg.isEmpty { Section { Text(msg).font(.caption) } }
            }
            .navigationTitle("设置 API Key")
            .toolbar {
                Button("完成") { mode.wrappedValue.dismiss() }
            }
        }
        .navigationViewStyle(.stack)
    }
}
