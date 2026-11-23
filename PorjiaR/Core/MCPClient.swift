import Foundation

/// MCP HTTP 客户端：JSON-RPC 2.0 over HTTP POST，兼容 application/json 与 SSE。
/// 只移植 HTTP transport（iOS 无法 spawn 任意子进程，stdio 不适用）。
/// 配置格式对齐 Claude Desktop 的 servers.json，Key 用 $VAR 引用从 Keychain 展开。
final class MCPClient {
    static let shared = MCPClient()

    struct Server: Identifiable, Codable {
        var id: String
        var name: String = ""
        var url: String = ""
        var headers: [String: String] = [:]
        var enabled: Bool = true

        enum CodingKeys: String, CodingKey { case id, name, url, headers, enabled }
        init(id: String = UUID().uuidString, name: String = "", url: String = "",
             headers: [String: String] = [:], enabled: Bool = true) {
            self.id = id; self.name = name; self.url = url
            self.headers = headers; self.enabled = enabled
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
            headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
            try c.encode(url, forKey: .url); try c.encode(headers, forKey: .headers)
            try c.encode(enabled, forKey: .enabled)
        }
    }

    struct Tool: Identifiable {
        var id: String { name }
        let name: String
        let description: String
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 300
        return URLSession(configuration: c)
    }()

    // MARK: - 配置持久化（Store）

    func servers() -> [Server] {
        let obj = Store.shared.load("mcp_servers", default: ["servers": []])
        guard let arr = obj["servers"] as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let data = try? JSONSerialization.data(withJSONObject: d),
                  let s = try? JSONDecoder().decode(Server.self, from: data) else { return nil }
            return s
        }
    }

    func save(_ list: [Server]) {
        var arr: [[String: Any]] = []
        for s in list {
            guard let data = try? JSONEncoder().encode(s),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            arr.append(obj)
        }
        Store.shared.save("mcp_servers", ["servers": arr])
    }

    /// $VAR / $$VAR → Keychain 值（不做二次展开）
    private func expand(_ s: String) -> String {
        let pattern = #"\$\$?\{?([A-Za-z_][A-Za-z0-9_]*)\}?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range(at: 1)
            if r.location == NSNotFound { continue }
            let key = ns.substring(with: r)
            result += ns.substring(from: last, to: m.range.location)
            result += KeychainStore.shared.get(key) ?? ""
            last = NSMaxRange(m.range)
        }
        result += ns.substring(from: last, to: ns.length)
        return result
    }

    private func request(_ server: Server, method: String, params: [String: Any], id: Int) -> URLRequest? {
        guard let u = URL(string: expand(server.url)) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in server.headers { req.setValue(expand(v), forHTTPHeaderField: k) }
        let rpc: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        req.httpBody = try? JSONSerialization.data(withJSONObject: rpc)
        return req
    }

    /// 解析响应：纯 JSON 或 SSE（取第一条 data: 的 JSON-RPC 回复）
    private func parse(_ data: Data) -> [String: Any]? {
        if let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return j }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("data:") else { continue }
            let p = String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let d = p.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            if j["jsonrpc"] != nil || j["result"] != nil || j["error"] != nil { return j }
        }
        return nil
    }

    private func call(_ server: Server, method: String, params: [String: Any], id: Int) async -> Envelope {
        guard let req = request(server, method: method, params: params, id: id) else {
            return .fail("mcp.call", "无效 URL: \(server.url)", tool: "MCPClient")
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                return .fail("mcp.call", "HTTP \(code)", code: code, tool: "MCPClient",
                             data: ["body": String(data: data.prefix(500), encoding: .utf8) ?? ""])
            }
            guard let rpc = parse(data) else {
                return .fail("mcp.call", "无法解析 JSON-RPC 响应", tool: "MCPClient")
            }
            if let err = rpc["error"] as? [String: Any] {
                let msg = err["message"] as? String ?? "JSON-RPC error"
                return .fail("mcp.call", msg, code: err["code"] as? Int ?? -1, tool: "MCPClient")
            }
            return .ok("mcp.call", ["result": rpc["result"] ?? NSNull()], tool: "MCPClient")
        } catch {
            return .fail("mcp.call", error.localizedDescription, code: 2, tool: "MCPClient")
        }
    }

    func initialize(_ server: Server) async -> Envelope {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "PorjiaR", "version": "1.0"],
        ]
        return await call(server, method: "initialize", params: params, id: 1)
    }

    func tools(_ server: Server) async -> Envelope {
        return await call(server, method: "tools/list", params: [:], id: 2)
    }

    func invoke(_ server: Server, name: String, arguments: [String: Any]) async -> Envelope {
        return await call(server, method: "tools/call",
                          params: ["name": name, "arguments": arguments], id: 3)
    }

    /// 测试连通性：initialize，返回可读摘要
    func test(_ server: Server) async -> Envelope {
        let res = await initialize(server)
        if res.ok {
            var e = Envelope.ok("mcp.test", ["server": server.name, "reachable": true], tool: "MCPClient")
            e.error = nil
            return e
        }
        return .fail("mcp.test", res.error ?? "连接失败", code: res.code, tool: "MCPClient")
    }
}
