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
                    Card {
                        SectionTitle(icon: "doc.badge.gearshape", title: "分析目标")
                        HStack {
                            VStack(alignment: .leading) {
                                Text(targetName).font(.subheadline.weight(.semibold))
                                Text(fileData == nil ? "从文件 App 导入 IPA 或 Mach-O" : "\(formatBytes(fileData!.count)) 已载入")
                                    .font(.caption).foregroundColor(Theme.text2)
                            }
                            Spacer()
                            Button("导入") { isImporting = true }
                                .buttonStyle(.bordered).tint(Theme.brand)
                        }
                    }

                    // 命令选择
                    Card {
                        SectionTitle(icon: "hammer.fill", title: "引擎命令")
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

                            PrimaryButton(title: "执行 \(command)", icon: "play.fill",
                                          busy: busy, disabled: fileData == nil) {
                                runCommand()
                            }
                        }
                    }

                    // SOP
                    Card {
                        SectionTitle(icon: "list.number", title: "破解标准流程 SOP", tint: .orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1 · auth 判授权位置：server=本地无解转抓包；local=继续")
                            Text("2 · gate 定位校验点候选（符号 + 字符串启发式）")
                            Text("3 · patch 等长替换：先 dry-run，确认后勾选写入，自动 .bak 备份")
                            Text("4 · verify 校验字节落地；重启/联网后复查是否保持")
                            Text("5 · report 生成逆向四件套 Markdown")
                        }.font(.caption).foregroundColor(Theme.text2)
                    }

                    // 结果
                    Card {
                        SectionTitle(icon: "terminal", title: "执行结果", tint: .purple)
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
        // BUGFIX: 同步执行时 busy=true 被同一 runloop 内的 defer 立即抵消，UI 永远看不到"执行中"。
        // 改为后台执行 + 主线程回写，大文件（129MB）也不会卡住界面。
        busy = true
        result = ""
        let cmd = command, pat = pattern, off = offset, old = oldHex, new = newHex
        let apply = applyPatch, name = targetName, url = targetURL
        DispatchQueue.global(qos: .userInitiated).async {
            let eng = BreakerEngine.shared
            let out: String
            switch cmd {
            case "info": out = eng.info(d, name: name).jsonString
            case "symbols": out = eng.symbols(d, pattern: pat.isEmpty ? nil : pat).jsonString
            case "strings": out = eng.strings(d, pattern: pat.isEmpty ? nil : pat).jsonString
            case "gate": out = eng.gate(d, name: name).jsonString
            case "auth": out = eng.auth(d, name: name).jsonString
            case "patch":
                guard let u = url else { out = "需要先导入可写目标"; break }
                // BUGFIX: fileImporter 给的 security scope 已在 loadTarget defer 里释放，
                // patch 写文件前必须重新获取，否则写入失败。
                let accessed = u.startAccessingSecurityScopedResource()
                defer { if accessed { u.stopAccessingSecurityScopedResource() } }
                out = eng.patch(file: u, offsetStr: off, oldHex: old,
                                newHex: new, apply: apply).jsonString
            case "verify":
                guard let u = url else { out = "需要先导入目标"; break }
                let accessed = u.startAccessingSecurityScopedResource()
                defer { if accessed { u.stopAccessingSecurityScopedResource() } }
                out = eng.verify(file: u, offsetStr: off, expectHex: new).jsonString
            case "report":
                let auth = eng.auth(d, name: name)
                let v = auth.data["verdict"] as? String ?? "待判定"
                out = eng.report(target: name, auth: v,
                                 gate: "先跑 gate 定位校验点",
                                 patch: "先跑 patch（dry-run → --apply）",
                                 verify: "先跑 verify 校验字节")
            default: out = "未知命令"
            }
            DispatchQueue.main.async {
                self.result = out
                self.busy = false
                // 供在线对话页注入上下文
                if cmd == "report" || cmd == "auth" || cmd == "gate" {
                    Store.shared.save("last_report", ["text": out, "command": cmd])
                }
            }
        }
    }

    private func shareResult() {
        let av = UIActivityViewController(activityItems: [result], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private func formatBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.1f MB", Double(n) / (1024 * 1024))
    }
}
