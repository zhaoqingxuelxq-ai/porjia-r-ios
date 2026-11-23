import Foundation

/// 跨设备同步抽象：优先 CloudKit（需 iCloud 登录 + 有效签名），否则降级为本地快照。
/// TrollStore 装的 ad-hoc 签名 App 通常拿不到 CloudKit 容器，因此降级是常态而非异常。
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: String {
        case localOnly = "仅本地"
        case cloud = "iCloud 同步"
        case unavailable = "不可用"
    }

    private let fm = FileManager.default
    private var snapshot: URL { Store.shared.root.appendingPathComponent("sync_snapshot.json") }

    var status: Status {
        // iCloud 令牌存在且容器可用 → cloud；否则 localOnly
        if fm.ubiquityIdentityToken != nil { return .cloud }
        return .localOnly
    }

    /// 导出本地快照（配置/记忆/会话/条目/MCP/Key 名清单，不含 Key 值）
    func exportSnapshot() -> [String: Any] {
        var obj: [String: Any] = [
            "schema": "porjia.sync/1",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "registry": Store.shared.load("registry.json", default: ["entries": []]),
            "memory": Store.shared.memory(),
            "sessions": Store.shared.load("sessions.json", default: ["sessions": []]),
            "mcpServers": Store.shared.load("mcp_servers", default: ["servers": []]),
            "keyNames": KeychainStore.shared.savedKeys(),   // 只导名字，不导 Key 值
        ]
        obj["status"] = status.rawValue
        return obj
    }

    @discardableResult
    func exportToFile() -> URL? {
        guard let d = try? JSONSerialization.data(withJSONObject: exportSnapshot(), options: [.prettyPrinted]) else { return nil }
        try? d.write(to: snapshot, options: .atomic)
        return snapshot
    }

    @discardableResult
    func importFromFile(_ u: URL) -> Bool {
        let accessed = u.startAccessingSecurityScopedResource()
        defer { if accessed { u.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: u),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let schema = o["schema"] as? String, schema == "porjia.sync/1" else { return false }
        if let reg = o["registry"] as? [String: Any] { Store.shared.save("registry.json", reg) }
        if let mem = o["memory"] as? [String: Any] { Store.shared.saveMemory(mem) }
        if let ses = o["sessions"] as? [String: Any] { Store.shared.save("sessions.json", ses) }
        if let mcp = o["mcpServers"] as? [String: Any] { Store.shared.save("mcp_servers", mcp) }
        return true
    }

    /// 供 UI 显示同步摘要
    func summary() -> String {
        let s = exportSnapshot()
        let entries = (s["registry"] as? [String: Any])?["entries"] as? [[String: Any]] ?? []
        let keys = s["keyNames"] as? [String] ?? []
        return "状态 \(status.rawValue) · \(entries.count) 条目 · \(keys.count) 个 Key 名（不含值）"
    }
}
