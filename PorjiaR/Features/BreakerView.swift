import SwiftUI
import UniformTypeIdentifiers

/// 破甲引擎页：导入 IPA / Mach-O → 选命令 → 看结果。
/// 文件来自 iOS 文件 App，全程本地处理，不联网、不经浏览器。
struct BreakerView: View {
    @State private var targetURL: URL?
    @State private var targetName = "未选择目标"
    @State private var fileData: Data?
    @State private var isImporting = false
    @State private var command = "auth"
    @State private var result = ""
    @State private var pattern = ""
    @State private var offset = "0x0"
    @State private var oldHex = ""
    @State private var newHex = ""
    @State private var applyPatch = false
    @State private var busy = false

    private let commands = ["info", "symbols", "strings", "gate", "auth", "patch", "verify", "report"]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 目标选择
                    GroupBox("分析目标") {
                        HStack {
                            Image(systemName: "doc.badge.gearshape").foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text(targetName).font(.subheadline.weight(.semibold))
                                Text(fileData == nil ? "从文件 App 导入 IPA 或 Mach-O" : "\(fileData!.count) 字节已载入内存")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("导入") { isImporting = true }
                        }
                    }

                    // 命令选择
                    GroupBox("引擎命令") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("命令", selection: $command) {
                                ForEach(commands, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)

                            if command == "symbols" || command == "strings" {
                                TextField("过滤正则（可空）", text: $pattern)
                                    .textFieldStyle(.roundedBorder)
                                    .autocapitalization(.none).disableAutocorrection(true)
                            }
                            if command == "patch" || command == "verify" {
                                TextField("偏移，如 0x1a2b3c", text: $offset)
                                    .textFieldStyle(.roundedBorder).autocapitalization(.none)
                                TextField("原字节 HEX，如 75 08", text: $oldHex)
                                    .textFieldStyle(.roundedBorder).autocapitalization(.none)
                            }
                            if command == "patch" {
                                TextField("替换字节 HEX（等长），如 EB 08", text: $newHex)
                                    .textFieldStyle(.roundedBorder).autocapitalization(.none)
                                Toggle("确认写入（关闭=dry-run 不落盘）", isOn: $applyPatch)
                                    .font(.caption)
                            }
                            if command == "verify" {
                                TextField("期望字节 HEX", text: $newHex)
                                    .textFieldStyle(.roundedBorder).autocapitalization(.none)
                            }

                            Button {
                                runCommand()
                            } label: {
                                HStack {
                                    if busy { ProgressView() }
                                    Text(busy ? "执行中…" : "执行 \(command)")
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(.red)
                            .disabled(fileData == nil || busy)
                        }
                    }

                    // SOP
                    GroupBox("破解标准流程 SOP") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1 · auth 判授权位置：server=本地无解转抓包；local=继续")
                            Text("2 · gate 定位校验点候选（符号 + 字符串启发式）")
                            Text("3 · patch 等长替换：先 dry-run，确认后勾选写入，自动 .bak 备份")
                            Text("4 · verify 校验字节落地；重启/联网后复查是否保持")
                            Text("5 · report 生成逆向四件套 Markdown")
                        }.font(.caption).foregroundColor(.secondary)
                    }

                    // 结果
                    GroupBox("执行结果") {
                        ScrollView {
                            Text(result.isEmpty ? "—" : result)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(minHeight: 180, maxHeight: 320)
                    }

                    if !result.isEmpty {
                        Button("分享结果") { shareResult() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("破甲引擎")
            .fileImporter(isPresented: $isImporting,
                          allowedContentTypes: [.data, .archive, .item],
                          allowsMultipleSelection: false) { res in
                switch res {
                case .success(let urls):
                    guard let u = urls.first else { return }
                    loadTarget(u)
                case .failure(let e):
                    result = "导入失败: \(e.localizedDescription)"
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func loadTarget(_ u: URL) {
        guard u.startAccessingSecurityScopedResource() else {
            result = "无法访问该文件（权限）"
            return
        }
        defer { u.stopAccessingSecurityScopedResource() }
        guard let d = try? Data(contentsOf: u) else {
            result = "读取文件失败"
            return
        }
        targetURL = u
        targetName = u.lastPathComponent
        fileData = d
        result = "已载入 \(u.lastPathComponent)（\(d.count) 字节）。先跑 auth 判授权位置。"
    }

    private func runCommand() {
        guard let d = fileData else { return }
        busy = true
        defer { busy = false }
        let eng = BreakerEngine.shared
        switch command {
        case "info":
            result = eng.info(d, name: targetName).jsonString
        case "symbols":
            result = eng.symbols(d, pattern: pattern.isEmpty ? nil : pattern).jsonString
        case "strings":
            result = eng.strings(d, pattern: pattern.isEmpty ? nil : pattern).jsonString
        case "gate":
            result = eng.gate(d, name: targetName).jsonString
        case "auth":
            result = eng.auth(d, name: targetName).jsonString
        case "patch":
            guard let u = targetURL else { result = "需要先导入可写目标"; return }
            result = eng.patch(file: u, offsetStr: offset, oldHex: oldHex,
                               newHex: newHex, apply: applyPatch).jsonString
        case "verify":
            guard let u = targetURL else { result = "需要先导入目标"; return }
            result = eng.verify(file: u, offsetStr: offset, expectHex: newHex).jsonString
        case "report":
            let auth = eng.auth(d, name: targetName)
            let v = auth.data["verdict"] as? String ?? "待判定"
            result = eng.report(target: targetName, auth: v,
                                gate: "先跑 gate 定位校验点",
                                patch: "先跑 patch（dry-run → --apply）",
                                verify: "先跑 verify 校验字节")
        default:
            result = "未知命令"
        }
    }

    private func shareResult() {
        let av = UIActivityViewController(activityItems: [result], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
