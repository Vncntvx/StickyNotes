import Foundation
import CryptoKit
import Security
import Domain

// MARK: - ObjectCrypto (T111)
//
// Per plan §Encryption architecture and contracts/encrypted-envelope.schema.json:
//
// - Per-object keys derived via HKDF-SHA-256 from the vault master key with
//   context = {vaultID, objectID, objectType, schemaVersion,
//   encryptionSuiteVersion}.
// - The SAME immutable context is the AES-GCM associated data (AAD). The
//   envelope does NOT repeat the context (avoids substitution attacks).
// - Fail closed: wrong password, modified ciphertext, invalid tag, mismatched
//   object ID/type/vault, unsupported envelope version all throw; no partial
//   plaintext is ever returned.
// - No hand-rolled crypto (constitution VII): CryptoKit only.

/// The immutable context that both derives the object key and authenticates
/// the object (AAD). Any mismatch MUST fail closed.
public struct ObjectCryptoContext: Sendable, Equatable {
    public let vaultId: UUID
    public let objectId: String
    public let objectType: String
    public let schemaVersion: Int
    public let encryptionSuiteVersion: Int

    public init(vaultId: UUID, objectId: String, objectType: String, schemaVersion: Int, encryptionSuiteVersion: Int) {
        self.vaultId = vaultId
        self.objectId = objectId
        self.objectType = objectType
        self.schemaVersion = schemaVersion
        self.encryptionSuiteVersion = encryptionSuiteVersion
    }

    /// Canonical AAD bytes: stable, ordered, unambiguous encoding of the
    /// context fields. Changing any field changes every derived key and
    /// every AAD → fail closed on substitution.
    public func canonicalBytes() -> Data {
        var bytes = Data()
        func append(_ s: String) {
            bytes.append(Data([UInt8(s.count >> 8), UInt8(s.count & 0xFF)]))
            bytes.append(Data(s.utf8))
        }
        append(vaultId.uuidString)
        append(objectId)
        append(objectType)
        append("\(schemaVersion)")
        append("\(encryptionSuiteVersion)")
        return bytes
    }
}

/// The current encryption suite (argon2id KEK + HKDF-SHA-256 + AES-GCM).
/// Bumping this is a MAJOR change (vault-bootstrap.schema.json).
public enum EncryptionSuite {
    public static let version = 1
}

/// AES-GCM encryption/decryption of canonical object bytes with
/// context-derived keys. Stateless and Sendable.
public enum ObjectCrypto {

    /// Derives the per-object key for a context.
    public static func objectKey(masterKey: SymmetricKey, context: ObjectCryptoContext) -> SymmetricKey {
        let info = context.canonicalBytes()
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            info: info,
            outputByteCount: 32
        )
        return derived
    }

    /// Encrypts plaintext under the context-derived key. Returns a random
    /// 12-byte nonce + combined ciphertext (AES-GCM combined mode includes
    /// the tag).
    public static func encrypt(
        _ plaintext: Data,
        masterKey: SymmetricKey,
        context: ObjectCryptoContext
    ) throws -> (nonce: Data, sealed: Data) {
        let key = objectKey(masterKey: masterKey, context: context)
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: context.canonicalBytes())
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        guard let combined = box.combined else {
            throw StickyError.encryption(.kdfFailed)
        }
        return (nonceData, combined)
    }

    /// Decrypts and authenticates. ANY failure (wrong key, modified
    /// ciphertext, tampered tag, substituted context) throws
    /// `.encryption(.modifiedCiphertext)` — fail closed (constitution VII).
    public static func decrypt(
        sealed: Data,
        masterKey: SymmetricKey,
        context: ObjectCryptoContext
    ) throws -> Data {
        let key = objectKey(masterKey: masterKey, context: context)
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            return try AES.GCM.open(box, using: key, authenticating: context.canonicalBytes())
        } catch {
            throw StickyError.encryption(.modifiedCiphertext)
        }
    }

    /// Wraps (encrypts) the master key with a KEK. AES-GCM, random nonce.
    public static func wrap(masterKeyBytes: Data, kek: SymmetricKey) throws -> (nonce: Data, sealed: Data) {
        let nonce = AES.GCM.Nonce()
        let box = try AES.GCM.seal(masterKeyBytes, using: kek, nonce: nonce)
        let nonceData = nonce.withUnsafeBytes { Data($0) }
        guard let combined = box.combined else {
            throw StickyError.encryption(.kdfFailed)
        }
        return (nonceData, combined)
    }

    /// Unwraps (decrypts) the master key with a KEK. Wrong KEK → throws
    /// `.encryption(.wrongPassword)`-class error (fail closed).
    public static func unwrap(masterKeyBytes: Data, nonce: Data, kek: SymmetricKey) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: masterKeyBytes)
            return try AES.GCM.open(box, using: kek)
        } catch {
            throw StickyError.encryption(.wrongPassword)
        }
    }
}

// MARK: - Keychain-backed secret storage (credentials never in SQLite,
// UserDefaults, or logs — constitution VI).

/// Abstraction over the Keychain for vault secrets. The app wires the
/// real `KeychainService`; tests use `InMemorySecretStore`.
public protocol SecretStore: Sendable {
    func save(_ data: Data, forKey key: String) throws
    func load(forKey key: String) throws -> Data?
    func delete(forKey key: String) throws
}

/// A deterministic in-memory store for tests. NEVER used in production.
/// `@unchecked Sendable`: guarded by its own lock.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func save(_ data: Data, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }

    public func load(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func delete(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}

/// Real Keychain-backed store via the Security framework. Items are
/// `kSecClassGenericPassword` entries keyed by a stable service+account;
/// no secrets ever touch SQLite/UserDefaults/logs (constitution VI).
public struct KeychainService: SecretStore {
    public static let serviceName = "local.stickynotes.security"

    public init() {}

    public func save(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
                throw StickyError.credentials(.saveFailed)
            }
        } else if status != errSecSuccess {
            throw StickyError.credentials(.saveFailed)
        }
    }

    public func load(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StickyError.credentials(.accessDenied)
        }
        return data
    }

    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StickyError.credentials(.deleteFailed)
        }
    }
}
