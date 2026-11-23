import Foundation

/// 统一接口信封（对齐 V9 的 I 表 / 原 minis.result 契约）。
/// 引擎所有结果都包在信封里：UI 直接消费，报告导出直接序列化。
struct Envelope {
    var schema: String = "porjia.result/1"
    var ok: Bool
    var mode: String
    var tool: String = "PorjiaR"
    var data: [String: Any]
    var error: String?
    var code: Int
    var ms: Int = 0

    static func ok(_ mode: String, _ data: [String: Any] = [:], tool: String = "PorjiaR") -> Envelope {
        Envelope(ok: true, mode: mode, tool: tool, data: data, error: nil, code: 0)
    }

    static func fail(_ mode: String, _ error: String, code: Int = 1,
                     tool: String = "PorjiaR", data: [String: Any] = [:]) -> Envelope {
        Envelope(ok: false, mode: mode, tool: tool, data: data, error: error, code: code)
    }

    /// 输出为 JSON 字符串（报告 / 分享用）。
    var jsonString: String {
        var obj: [String: Any] = [
            "schema": schema, "ok": ok, "mode": mode, "tool": tool,
            "data": data, "code": code, "timing": ["ms": ms],
        ]
        if let e = error { obj["error"] = e }
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}
