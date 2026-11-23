import Foundation

/// 内置数据源：模型路由表（223 providers / 8080 models）+ V9 规范章节。
final class DataSources {
    static let shared = DataSources()

    private(set) var providers: [String: Any] = [:]
    private(set) var ruleFiles: [String] = []

    init() {
        loadModels()
        loadRules()
    }

    private func loadModels() {
        guard let url = Bundle.main.url(forResource: "models-dev-api", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        providers = o
    }

    private func loadRules() {
        guard let dir = Bundle.main.url(forResource: "Rules", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        ruleFiles = files.filter { $0.hasSuffix(".md") }.sorted()
    }

    var stats: (providers: Int, models: Int) {
        var m = 0
        for v in providers.values {
            if let models = v as? [String: Any], let mm = models["models"] as? [String: Any] { m += mm.count }
        }
        return (providers.count, m)
    }

    struct ProviderRow: Identifiable {
        let id: String
        let name: String
        let npm: String
        let api: String
        let modelCount: Int
    }

    func searchProviders(_ q: String) -> [ProviderRow] {
        let ql = q.lowercased()
        var rows: [ProviderRow] = []
        for (pid, raw) in providers {
            guard let p = raw as? [String: Any] else { continue }
            let name = p["name"] as? String ?? ""
            let api = p["api"] as? String ?? ""
            if !ql.isEmpty && !(pid.lowercased().contains(ql) || name.lowercased().contains(ql) || api.lowercased().contains(ql)) {
                continue
            }
            let count = (p["models"] as? [String: Any])?.count ?? 0
            rows.append(ProviderRow(id: pid, name: name, npm: p["npm"] as? String ?? "",
                                    api: api, modelCount: count))
        }
        return rows.sorted { $0.modelCount > $1.modelCount }
    }

    /// 单个 provider 原始字典（ModelClient 构造路由用）
    func provider(_ id: String) -> [String: Any]? { providers[id] as? [String: Any] }

    /// provider 声明的 API Key 环境变量名（可能多个，取可配的）
    func envKeys(_ id: String) -> [String] {
        guard let p = provider(id) else { return [] }
        if let arr = p["env"] as? [String] { return arr }
        if let s = p["env"] as? String { return [s] }
        return []
    }

    /// 模型能力结构（UI 徽标与工具调用开关的数据源）
    struct ModelInfo: Identifiable {
        let id: String
        let name: String
        let reasoning: Bool
        let toolCall: Bool
        let structured: Bool
        let family: String
    }

    func models(of providerID: String) -> [ModelInfo] {
        guard let p = provider(providerID), let mm = p["models"] as? [String: Any] else { return [] }
        var out: [ModelInfo] = []
        for (mid, raw) in mm {
            guard let m = raw as? [String: Any] else { continue }
            out.append(ModelInfo(
                id: m["id"] as? String ?? mid,
                name: m["name"] as? String ?? mid,
                reasoning: (m["reasoning"] as? Bool) ?? false,
                toolCall: (m["tool_call"] as? Bool) ?? false,
                structured: (m["structured_output"] as? Bool) ?? false,
                family: m["family"] as? String ?? ""))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func ruleContent(_ file: String) -> String {
        guard let dir = Bundle.main.url(forResource: "Rules", withExtension: nil) else { return "" }
        let u = dir.appendingPathComponent(file)
        return (try? String(contentsOf: u, encoding: .utf8)) ?? ""
    }
}
