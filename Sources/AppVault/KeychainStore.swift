import Foundation
import Security

protocol SecureStore: Sendable {
    func save<T: Encodable>(_ value: T, key: String) throws
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T?
    func remove(key: String) throws
}

final class KeychainStore: SecureStore, @unchecked Sendable {
    // A fresh namespace avoids legacy ad-hoc build ACLs that repeatedly ask for the login
    // keychain password. It is still device-local, Keychain-only storage.
    // v4 deliberately does not read the earlier experimental builds' records. Those records
    // can carry an old ad-hoc signing ACL and trigger the macOS login-keychain prompt.
    private let service = "com.appvault.desktop.local.v4"
    func save<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query; add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.keychain(status) }
    }
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw VaultError.keychain(status) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func remove(key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw VaultError.keychain(status) }
    }
}

final class MemorySecureStore: SecureStore, @unchecked Sendable {
    private var values: [String: Data] = [:]
    func save<T: Encodable>(_ value: T, key: String) throws { values[key] = try JSONEncoder().encode(value) }
    func load<T: Decodable>(_ type: T.Type, key: String) throws -> T? { try values[key].map { try JSONDecoder().decode(T.self, from: $0) } }
    func remove(key: String) throws { values.removeValue(forKey: key) }
}
