import Foundation
import CryptoKit

/// Opaque payload suitable for an optional sync provider. It deliberately has no password, verifier,
/// biometric data, or plaintext metadata fields. Networking is disabled unless a future user enables it.
struct EncryptedSyncEnvelope: Codable, Sendable {
    let version: Int
    let nonce: Data
    let ciphertext: Data
}

enum EncryptedSync {
    static func seal<T: Encodable>(_ value: T, key: SymmetricKey) throws -> EncryptedSyncEnvelope {
        let plaintext = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else { throw VaultError.unavailable("Could not encrypt sync data.") }
        return EncryptedSyncEnvelope(version: 1, nonce: Data(sealed.nonce), ciphertext: combined)
    }
    static func open<T: Decodable>(_ envelope: EncryptedSyncEnvelope, as type: T.Type, key: SymmetricKey) throws -> T {
        guard envelope.version == 1 else { throw VaultError.unavailable("Unsupported sync envelope.") }
        return try JSONDecoder().decode(T.self, from: AES.GCM.open(try AES.GCM.SealedBox(combined: envelope.ciphertext), using: key))
    }
}

/// Creates a sync encryption key locally only when an opt-in sync implementation requests one.
/// The key is stored as Keychain data and is never sent to a provider.
struct SyncKeyProvider {
    private let store: SecureStore
    private let keyName = "sync-envelope-key-v1"
    init(store: SecureStore) { self.store = store }
    func key() throws -> SymmetricKey {
        if let existing = try store.load(Data.self, key: keyName) { return SymmetricKey(data: existing) }
        let generated = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try store.save(generated, key: keyName)
        return SymmetricKey(data: generated)
    }
}
