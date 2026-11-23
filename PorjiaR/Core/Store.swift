import Foundation

/// 本地数据层（对齐 IPA 的 /var/minis 数据区）：配置条目、记忆、会话、模型端点。
/// 落在 App 沙箱 Documents/porjia/，JSON 原子写。
final class Store {
    static let shared = Store()

    let root: URL
    private let fm = FileManager.default

    init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("porjia", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { root.appendingPathComponent(name) }

    func load(_ name: String, default def: [String: Any]) -> [String: Any] {
        guard let d = try? Data(contentsOf: url(name)),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return def }
        return o
    }

    @discardableResult
    func save(_ name: String, _ obj: [String: Any]) -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return false }
        // 原子写：先写临时文件再替换
        let tmp = url(name + ".tmp")
        do {
            try d.write(to: tmp, options: .atomic)
            if fm.fileExists(atPath: url(name).path) { try fm.removeItem(at: url(name)) }
            try fm.moveItem(at: tmp, to: url(name))
            return true
        } catch { return false }
    }

    func textFileURL(_ name: String) -> URL { url(name) }

    // ---- 条目 ----
    func entries() -> [[String: Any]] {
        (load("registry.json", default: ["entries": []])["entries"] as? [[String: Any]]) ?? []
    }

    func saveEntries(_ entries: [[String: Any]]) {
        save("registry.json", ["schema": "porjia.entries/1", "entries": entries])
    }

    // ---- 记忆 ----
    func memory() -> [String: Any] { load("memory.json", default: ["global": "", "notes": []]) }
    func saveMemory(_ m: [String: Any]) { save("memory.json", m) }

    // ---- 会话 ----
    func sessions() -> [[String: Any]] {
        (load("sessions.json", default: ["sessions": []])["sessions"] as? [[String: Any]]) ?? []
    }
    func saveSessions(_ s: [[String: Any]]) { save("sessions.json", ["sessions": s]) }
}
