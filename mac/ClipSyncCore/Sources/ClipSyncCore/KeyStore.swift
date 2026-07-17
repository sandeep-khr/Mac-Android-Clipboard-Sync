import Foundation
import Security

/// A minimal secret-storage seam. The identity and trust layers persist their
/// secrets through this protocol so they can be unit-tested against an in-memory
/// double instead of the real Keychain (which needs entitlements and isn't
/// available under `swift test`).
///
/// - App uses `KeychainKeyStore`.
/// - Tests use `InMemoryKeyStore`.
public protocol KeyStore {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func remove(forKey key: String) throws
}

/// In-memory implementation for tests (and any ephemeral use).
public final class InMemoryKeyStore: KeyStore {
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) throws -> Data? { storage[key] }
    public func set(_ data: Data, forKey key: String) throws { storage[key] = data }
    public func remove(forKey key: String) throws { storage[key] = nil }
}

/// Keychain-backed store (generic-password items) for the real app. Secrets live
/// in the login Keychain under a single service; each secret is one account.
///
/// Not exercised by `swift test` (no Keychain entitlements there) — its logic is
/// intentionally thin; the behavioural tests run against `InMemoryKeyStore`.
public final class KeychainKeyStore: KeyStore {
    private let service: String

    public init(service: String = "com.clipsync.identity") {
        self.service = service
    }

    public func data(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        return result as? Data
    }

    public func set(_ data: Data, forKey key: String) throws {
        try remove(forKey: key)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    public func remove(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    public enum KeychainError: Error { case unhandled(OSStatus) }
}
