import Foundation
import CryptoKit

/// 破甲引擎（Swift 原生，对齐 breaker.py 的 8 子命令）。
/// 确定性工具，秒级出结果：info / symbols / strings / gate / auth / patch / verify / report。
/// patch 强制等长 + 原字节校验 + 自动备份；默认 dry-run。
final class BreakerEngine {

    static let shared = BreakerEngine()

    // 授权 / 校验点关键字（对齐 breaker.py）
    private let authSymPattern = try! NSRegularExpression(pattern:
        "is(vip|svip|member|smember|premium|subscribed|paid|login|anonymous)|" +
        "needauth|requireauth|checkauth|verify|entitlement|receipt|" +
        "(vip|member|premium|subscribe|purchase|pay)(check|status|info|state)", options: [.caseInsensitive])
    private let authStrPattern = try! NSRegularExpression(pattern:
        "isVip|isSVIP|isMember|isSmember|isLogin|needAuth|user/queryVip|queryVip|" +
        "/auth|/vip|/member|signature|sign=|timestamp|receipt|verifyReceipt|" +
        "订阅|会员|超级会员|开通|支付|授权", options: [.caseInsensitive])
    private let serverPattern = try! NSRegularExpression(pattern:
        "queryVip|verifyReceipt|/api/|/user/|/auth|signature|sign=|timestamp|https?://[a-z0-9.-]+",
        options: [.caseInsensitive])
    private let localPattern = try! NSRegularExpression(pattern:
        "NSUserDefaults|UserDefaults|plist|\\.db|sqlite|sled|local.*(vip|member)|archived|keychain",
        options: [.caseInsensitive])

    private func hits(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private func sha256(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - info

    func info(_ data: Data, name: String) -> Envelope {
        var ipa: String?
        let slices = MachOParser.parse(data, ipaName: &ipa)
        let rows = slices.map { s -> [String: Any] in
            ["label": s.label, "is64": s.is64, "cputype": NSNumber(value: s.cputype),
             "symbols": s.symbols.count, "segments": s.segments.count]
        }
        return .ok("info", [
            "target": name, "size": data.count, "sha256": sha256(data),
            "ipa_binary": ipa ?? NSNull(), "slices": rows,
        ], tool: "BreakerEngine")
    }

    // MARK: - symbols

    func symbols(_ data: Data, pattern: String?) -> Envelope {
        var ipa: String?
        let slices = MachOParser.parse(data, ipaName: &ipa)
        let re = pattern.flatMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        let seen = NSMutableSet()
        var rows: [[String: Any]] = []
        for s in slices {
            for sym in s.symbols {
                if let re = re, !hits(re, sym.name) { continue }
                if seen.contains(sym.name) { continue }
                seen.add(sym.name)
                rows.append(["name": sym.name,
                             "vm": "0x" + String(sym.value, radix: 16),
                             "fileoff": sym.fileoff.map { "0x" + String($0, radix: 16) } ?? NSNull()])
                if rows.count >= 300 { break }
            }
        }
        rows.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        return .ok("symbols", ["total": rows.count, "truncated": rows.count >= 300, "symbols": rows],
                   tool: "BreakerEngine")
    }

    // MARK: - strings

    func strings(_ data: Data, pattern: String?) -> Envelope {
        let re = pattern.flatMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        let all = printableStrings(data, limit: 200_000)
        var rows: [[String: Any]] = []
        for (off, text) in all {
            if let re = re, !hits(re, text) { continue }
            rows.append(["offset": "0x" + String(off, radix: 16), "text": String(text.prefix(300))])
            if rows.count >= 300 { break }
        }
        return .ok("strings", ["total": rows.count, "truncated": rows.count >= 300, "strings": rows],
                   tool: "BreakerEngine")
    }

    private func printableStrings(_ d: Data, minLen: Int = 4, limit: Int) -> [(Int, String)] {
        var out: [(Int, String)] = []
        var cur: [UInt8] = []
        var start = 0
        for (i, b) in d.enumerated() {
            if b >= 0x20 && b < 0x7f {
                if cur.isEmpty { start = i }
                cur.append(b)
            } else {
                if cur.count >= minLen, let s = String(bytes: cur, encoding: .ascii) {
                    out.append((start, s))
                    if out.count >= limit { break }
                }
                cur.removeAll()
            }
        }
        return out
    }

    // MARK: - gate（校验点定位）

    func gate(_ data: Data, name: String) -> Envelope {
        var ipa: String?
        let slices = MachOParser.parse(data, ipaName: &ipa)
        var cand: [[String: Any]] = []
        for s in slices {
            for sym in s.symbols where hits(authSymPattern, sym.name) {
                cand.append(["kind": "symbol", "name": sym.name,
                             "fileoff": sym.fileoff.map { "0x" + String($0, radix: 16) } ?? NSNull(),
                             "vm": "0x" + String(sym.value, radix: 16), "why": "auth/member symbol"])
            }
        }
        var seen = Set<String>()
        for (off, text) in printableStrings(data, limit: 200_000) where hits(authStrPattern, text) {
            let key = String(text.prefix(80))
            if seen.contains(key) { continue }
            seen.insert(key)
            cand.append(["kind": "string", "name": String(text.prefix(160)),
                         "fileoff": "0x" + String(off, radix: 16), "why": "auth/member string"])
        }
        cand.sort { (a, b) in
            let ka = a["kind"] as? String == "symbol" ? 0 : 1
            let kb = b["kind"] as? String == "symbol" ? 0 : 1
            return ka != kb ? ka < kb : (a["name"] as? String ?? "") < (b["name"] as? String ?? "")
        }
        return .ok("gate", ["target": name, "candidates": cand.count, "top": Array(cand.prefix(60))],
                   tool: "BreakerEngine")
    }

    // MARK: - auth（授权位置判定）

    func auth(_ data: Data, name: String) -> Envelope {
        var ipa: String?
        let slices = MachOParser.parse(data, ipaName: &ipa)
        var authSyms: [String] = []
        for s in slices {
            for sym in s.symbols where hits(authSymPattern, sym.name) {
                authSyms.append(sym.name)
                if authSyms.count >= 20 { break }
            }
        }
        var serverHits = Set<String>()
        var localHits = Set<String>()
        // 对每条字符串命中正则的整体片段
        for (_, text) in printableStrings(data, limit: 40_000) {
            for m in serverPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text) { serverHits.insert(String(text[r])) }
            }
            for m in localPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r = Range(m.range, in: text) { localHits.insert(String(text[r])) }
            }
        }
        let sh = Array(serverHits).sorted().prefix(20)
        let lh = Array(localHits).sorted().prefix(20)
        var score = 0
        if sh.contains(where: { $0.contains("queryVip") || $0.contains("verifyReceipt") }) { score += 3 }
        if sh.count >= 4 { score += 2 }
        if !lh.isEmpty { score += 1 }
        let verdict = score >= 4 ? "server" : (score <= 1 ? "local" : "mixed")
        let concl: String
        switch verdict {
        case "server": concl = "服务端授权：本地 patch 改不出服务端签名，会员权益连不上。转抓包 / 票据复现路线。"
        case "local": concl = "本地判定：可静态定位 gate 并 patch，重启校验是否保持。"
        default: concl = "混合：存在本地判定与网络校验，需断网实测确认授权落点。"
        }
        return .ok("auth", [
            "target": name, "verdict": verdict, "score": score,
            "server_hints": Array(sh), "local_hints": Array(lh),
            "auth_symbols": Array(authSyms.prefix(20)), "conclusion": concl,
            "next_step": "断网打开 App：会员状态保留=本地，失效=服务端",
        ], tool: "BreakerEngine")
    }

    // MARK: - patch / verify

    private func parseHex(_ s: String) -> Data {
        let cleaned = s.filter { $0.isHexDigit }
        var out = Data()
        var i = cleaned.startIndex
        while i < cleaned.endIndex {
            let j = cleaned.index(i, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            if let b = UInt8(cleaned[i..<j], radix: 16) { out.append(b) }
            i = j
        }
        return out
    }

    private func offset(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        return Int(t)
    }

    func patch(file: URL, offsetStr: String, oldHex: String, newHex: String, apply: Bool) -> Envelope {
        guard let off = offset(offsetStr), off >= 0 else {
            return .fail("patch", "invalid --offset", code: 2, tool: "BreakerEngine")
        }
        let old = parseHex(oldHex), new = parseHex(newHex)
        guard !old.isEmpty, !new.isEmpty else {
            return .fail("patch", "--old/--new 不能为空", code: 2, tool: "BreakerEngine")
        }
        guard old.count == new.count else {
            return .fail("patch", "原字节与目标字节长度必须一致（原地等长替换）", code: 4, tool: "BreakerEngine")
        }
        guard var data = try? Data(contentsOf: file), off + old.count <= data.count else {
            return .fail("patch", "文件读取失败或偏移越界", code: 2, tool: "BreakerEngine")
        }
        let cur = data[off..<(off + old.count)]
        guard cur == old else {
            return .fail("patch", "原字节不匹配", code: 4, tool: "BreakerEngine",
                         data: ["offset": "0x" + String(off, radix: 16),
                                "expect": old.map { String(format: "%02X", $0) }.joined(separator: " "),
                                "actual": cur.map { String(format: "%02X", $0) }.joined(separator: " ")])
        }
        var plan: [String: Any] = [
            "offset": "0x" + String(off, radix: 16),
            "old": old.map { String(format: "%02X", $0) }.joined(separator: " "),
            "new": new.map { String(format: "%02X", $0) }.joined(separator: " "),
            "length": old.count, "applied": false,
        ]
        if !apply {
            plan["note"] = "dry-run：确认后勾选“写入”才落盘"
            return .ok("patch", plan, tool: "BreakerEngine")
        }
        // 备份
        let bak = file.deletingPathExtension().appendingPathExtension("bak")
        try? Data(contentsOf: file).write(to: bak, options: .atomic)
        data.replaceSubrange(off..<(off + old.count), with: new)
        guard (try? data.write(to: file, options: .atomic)) != nil else {
            return .fail("patch", "写入失败，可从备份回滚", code: 5, tool: "BreakerEngine",
                         data: ["backup": bak.lastPathComponent])
        }
        plan["applied"] = true
        plan["backup"] = bak.lastPathComponent
        return .ok("patch", plan, tool: "BreakerEngine")
    }

    func verify(file: URL, offsetStr: String, expectHex: String) -> Envelope {
        guard let off = offset(offsetStr), let data = try? Data(contentsOf: file) else {
            return .fail("verify", "参数或文件无效", code: 2, tool: "BreakerEngine")
        }
        let exp = parseHex(expectHex)
        guard off + exp.count <= data.count else {
            return .fail("verify", "偏移越界", code: 2, tool: "BreakerEngine")
        }
        let got = data[off..<(off + exp.count)]
        let matched = got == exp
        return Envelope(ok: matched, mode: "verify", data: [
            "offset": "0x" + String(off, radix: 16),
            "expect": exp.map { String(format: "%02X", $0) }.joined(separator: " "),
            "actual": got.map { String(format: "%02X", $0) }.joined(separator: " "),
            "matched": matched,
        ], error: matched ? nil : "字节不匹配", code: matched ? 0 : 4, tool: "BreakerEngine")
    }

    // MARK: - report（逆向四件套）

    func report(target: String, auth: String, gate: String, patch: String, verify: String) -> String {
        """
        # 逆向四件套 · \(target)

        ## 1. 目标与授权位置
        - 目标：\(target)
        - 授权位置：\(auth)
        - 判据：断网后会员状态保留=本地判定；失效=服务端授权（服务端授权本地无解）

        ## 2. 校验点
        - \(gate)

        ## 3. patch 实体（原字节 → 替换字节）
        - \(patch)

        ## 4. 验证步骤
        - \(verify)
        - 重启 App / 联网后复查授权状态。

        > 由 破甲 R iOS 原生破甲引擎生成。
        """
    }
}
