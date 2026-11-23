import Foundation
import Security

/// API Key 安全存储：系统 Keychain，永不进 UserDefaults / JSON / 日志。
/// 键名对应模型的 `env[]` 字段名（如 OPENAI_API_KEY），与主程序的环境变量语义一致。
final class KeychainStore {
    static let shared = KeychainStore()
    private let service = "top.porjia.r.keys"

    private func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key] as [String: Any]
    }

    func get(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(_ value: String, for key: String) -> Bool {
        let data = Data(value.utf8)
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let add = SecItemAdd(q as CFDictionary, nil)
        if add == errSecSuccess { return true }
        if add == errSecDuplicateItem {
            let upd: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query(key) as CFDictionary, upd as CFDictionary) == errSecSuccess
        }
        return false
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        SecItemDelete(query(key) as CFDictionary) == errSecSuccess
    }

    /// 已保存的 Key 名列表（只返回账号名，不返回值）
    func savedKeys() -> [String] {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnAttributes as String: kCFBooleanTrue,
                                kSecMatchLimit as String: kSecMatchLimitAll] as [String: Any]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let arr = item as? [[String: Any]] else { return [] }
        return arr.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    /// 掩码显示（只留后四位）
    func masked(_ key: String) -> String {
        guard let v = get(key) else { return "未设置" }
        if v.count <= 4 { return String(repeating: "•", count: v.count) }
        return String(repeating: "•", count: min(v.count - 4, 12)) + String(v.suffix(4))
    }

    /// 卸载/重置：清空本 service 下所有项
    @discardableResult
    func removeAll() -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service] as [String: Any]
        SecItemDelete(q as CFDictionary) == errSecSuccess
    }
}
