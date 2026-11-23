import Foundation

/// 模型在线调用层：URLSession + 双协议（OpenAI-compatible / Anthropic）。
/// 数据源复用内置 models-dev-api.json，Key 从 Keychain 读取，不落盘。
final class ModelClient {
    static let shared = ModelClient()

    enum Kind: String {
        case openAI = "openai"
        case anthropic = "anthropic"
    }

    struct Route {
        let providerID: String
        let base: String
        let key: String
        let model: String
        let kind: Kind
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 120
        c.timeoutIntervalForResource = 180
        c.httpAdditionalHeaders = ["User-Agent": "PorjiaR/1.0"]
        return URLSession(configuration: c)
    }()

    // MARK: - 路由构造

    /// 从 provider id + model id + key 构造路由；自动识别协议族。
    func route(providerID: String, model: String, key: String) -> Route? {
        guard let p = DataSources.shared.provider(providerID),
              let base = p["api"] as? String, !base.isEmpty else { return nil }
        let npm = (p["npm"] as? String ?? "").lowercased()
        let kind: Kind = npm.contains("anthropic") ? .anthropic : .openAI
        return Route(providerID: providerID, base: base, key: key, model: model, kind: kind)
    }

    /// 协议路由：规范化 base，避免重复 /v1。
    private func endpoint(_ r: Route) -> String {
        let b = r.base.hasSuffix("/") ? String(r.base.dropLast()) : r.base
        switch r.kind {
        case .openAI:
            return b.hasSuffix("/chat/completions") ? b : b + "/chat/completions"
        case .anthropic:
            if b.hasSuffix("/messages") { return b }
            if b.hasSuffix("/v1") { return b + "/messages" }
            return b + "/v1/messages"
        }
    }

    private func headers(_ r: Route) -> [String: String] {
        var h = ["Content-Type": "application/json"]
        switch r.kind {
        case .openAI:
            if !r.key.isEmpty { h["Authorization"] = "Bearer \(r.key)" }
        case .anthropic:
            if !r.key.isEmpty { h["x-api-key"] = r.key }
            h["anthropic-version"] = "2023-06-01"
        }
        return h
    }

    private func body(_ r: Route, messages: [[String: Any]], stream: Bool) -> Data? {
        var obj: [String: Any] = ["model": r.model, "stream": stream]
        switch r.kind {
        case .openAI:
            obj["messages"] = messages
        case .anthropic:
            // Anthropic 要求 max_tokens；system 单独提出
            obj["max_tokens"] = 4096
            var msgs: [[String: Any]] = []
            var systemParts: [String] = []
            for m in messages {
                let role = m["role"] as? String ?? "user"
                let content = m["content"] as? String ?? ""
                if role == "system" { systemParts.append(content) }
                else { msgs.append(["role": role, "content": content]) }
            }
            if !systemParts.isEmpty { obj["system"] = systemParts.joined(separator: "\n\n") }
            obj["messages"] = msgs.isEmpty ? [["role": "user", "content": ""]] : msgs
        }
        return try? JSONSerialization.data(withJSONObject: obj)
    }

    private func makeRequest(_ r: Route, messages: [[String: Any]], stream: Bool) -> URLRequest? {
        guard let u = URL(string: endpoint(r)), let b = body(r, messages: messages, stream: stream) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.httpBody = b
        for (k, v) in headers(r) { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    // MARK: - 连通性测试

    func testConnection(_ r: Route) async -> Envelope {
        let msgs: [[String: Any]] = [["role": "user", "content": "Reply with OK only."]]
        guard let req = makeRequest(r, messages: msgs, stream: false) else {
            return .fail("model.test", "无法构造请求（检查 base URL）", tool: "ModelClient")
        }
        let start = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            var e = code == 200
                ? Envelope.ok("model.test", ["provider": r.providerID, "model": r.model, "http": code], tool: "ModelClient")
                : Envelope.fail("model.test", "HTTP \(code)", code: code, tool: "ModelClient", data: ["body": String(data: data.prefix(600), encoding: .utf8) ?? ""])
            e.ms = Int(Date().timeIntervalSince(start) * 1000)
            return e
        } catch {
            var e = Envelope.fail("model.test", error.localizedDescription, code: 2, tool: "ModelClient")
            e.ms = Int(Date().timeIntervalSince(start) * 1000)
            return e
        }
    }

    // MARK: - 非流式对话

    func chat(_ r: Route, messages: [[String: Any]]) async -> Envelope {
        guard let req = makeRequest(r, messages: messages, stream: false) else {
            return .fail("model.chat", "无法构造请求", tool: "ModelClient")
        }
        let start = Date()
        do {
            let (data, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                let detail = String(data: data.prefix(800), encoding: .utf8) ?? ""
                return .fail("model.chat", "HTTP \(code): \(detail)", code: code, tool: "ModelClient")
            }
            let text = extractText(data, kind: r.kind) ?? ""
            var e = Envelope.ok("model.chat", ["text": text, "provider": r.providerID, "model": r.model], tool: "ModelClient")
            e.ms = Int(Date().timeIntervalSince(start) * 1000)
            return e
        } catch {
            return .fail("model.chat", error.localizedDescription, code: 2, tool: "ModelClient")
        }
    }

    // MARK: - 流式对话（SSE）

    /// 逐 token 回调 onToken；完整文本通过 completion 返回。
    func stream(_ r: Route, messages: [[String: Any]],
                onToken: @escaping (String) -> Void) async -> Envelope {
        guard let req = makeRequest(r, messages: messages, stream: true) else {
            return .fail("model.stream", "无法构造请求", tool: "ModelClient")
        }
        let start = Date()
        var full = ""
        do {
            let (bytes, resp) = try await session.bytes(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                var buf = ""
                for try await line in bytes.lines { buf += line; if buf.count > 800 { break } }
                return .fail("model.stream", "HTTP \(code): \(buf)", code: code, tool: "ModelClient")
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { break }
                guard let d = payload.data(using: .utf8),
                      let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
                if let piece = streamPiece(j, kind: r.kind), !piece.isEmpty {
                    full += piece
                    onToken(piece)
                }
            }
            var e = Envelope.ok("model.stream", ["text": full, "provider": r.providerID, "model": r.model], tool: "ModelClient")
            e.ms = Int(Date().timeIntervalSince(start) * 1000)
            return e
        } catch {
            if !full.isEmpty {
                var e = Envelope.ok("model.stream", ["text": full, "partial": true], tool: "ModelClient")
                e.error = error.localizedDescription
                e.ms = Int(Date().timeIntervalSince(start) * 1000)
                return e
            }
            return .fail("model.stream", error.localizedDescription, code: 2, tool: "ModelClient")
        }
    }

    // MARK: - 解析

    private func streamPiece(_ j: [String: Any], kind: Kind) -> String? {
        switch kind {
        case .openAI:
            guard let choices = j["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else { return nil }
            return (delta["content"] as? String) ?? (delta["reasoning_content"] as? String)
        case .anthropic:
            guard let type = j["type"] as? String, type == "content_block_delta",
                  let delta = j["delta"] as? [String: Any] else { return nil }
            return delta["text"] as? String
        }
    }

    private func extractText(_ data: Data, kind: Kind) -> String? {
        guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch kind {
        case .openAI:
            guard let choices = j["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any] else { return nil }
            return msg["content"] as? String
        case .anthropic:
            guard let content = j["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { $0["text"] as? String }.joined()
        }
    }
}
