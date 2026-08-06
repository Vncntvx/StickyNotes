import Foundation
import CryptoKit
import Domain

// MARK: - VaultBootstrap (T112)
//
// Per contracts/vault-bootstrap.schema.json and plan §Encryption
// architecture:
//
// - Versioned bootstrap: format version, random vault ID, random vault
//   locator, Argon2id salt + params, wrapped master key, optional
//   key-confirmation material, encryption-suite version.
// - The password protects the RANDOM MASTER KEY (not every object).
// - Password change RE-WRAPS the master key; unchanged objects are not
//   re-encrypted (FR-164).
// - Wrong password / corrupt bootstrap fail closed.

/// The vault bootstrap (vault-bootstrap.schema.json, version 1).
public struct VaultBootstrap: Sendable, Equatable, Codable {
    public static let schemaVersion = 1
    public static let currentFormatVersion = 1

    public var schemaVersion: Int
    public var formatVersion: Int
    public var vaultId: UUID
    /// Random/opaque remote locator — reveals nothing semantic.
    public var vaultLocator: String
    public var argon2id: Argon2Parameters
    /// Master key wrapped with the password-derived KEK.
    public var wrappedMasterKey: WrappedKey
    /// Optional wrong-password verification material.
    public var keyConfirmation: WrappedKey?
    public var encryptionSuiteVersion: Int
    public var createdAt: Date

    public struct WrappedKey: Sendable, Equatable, Codable {
        public var nonce: Data
        public var sealed: Data  // AES-GCM combined (ciphertext + tag)

        public init(nonce: Data, sealed: Data) {
            self.nonce = nonce
            self.sealed = sealed
        }
    }

    public init(
        schemaVersion: Int = VaultBootstrap.schemaVersion,
        formatVersion: Int = VaultBootstrap.currentFormatVersion,
        vaultId: UUID,
        vaultLocator: String,
        argon2id: Argon2Parameters,
        wrappedMasterKey: WrappedKey,
        keyConfirmation: WrappedKey? = nil,
        encryptionSuiteVersion: Int = EncryptionSuite.version,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.formatVersion = formatVersion
        self.vaultId = vaultId
        self.vaultLocator = vaultLocator
        self.argon2id = argon2id
        self.wrappedMasterKey = wrappedMasterKey
        self.keyConfirmation = keyConfirmation
        self.encryptionSuiteVersion = encryptionSuiteVersion
        self.createdAt = createdAt
    }

    /// Canonical JSON encoding (stable keys, explicit schemaVersion).
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func fromCanonicalJSON(_ data: Data) throws -> VaultBootstrap {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(VaultBootstrap.self, from: data) else {
            throw StickyError.encryption(.corruptBootstrap)
        }
        guard decoded.schemaVersion == VaultBootstrap.schemaVersion else {
            throw StickyError.encryption(.corruptBootstrap)
        }
        return decoded
    }
}

/// Creates/opens a vault. Stateless; secrets live in the caller-provided
/// SecretStore (Keychain in production).
public enum VaultBootstrapService {

    /// Creates a new vault: random vault ID + locator, random salt, random
    /// master key, KEK-wrapped master key + key-confirmation blob.
    public static func createVault(
        password: String,
        secretStore: any SecretStore
    ) async throws -> VaultBootstrap {
        let salt = KeyDerivation.generateSalt()
        var parameters = Argon2Parameters.recommended
        parameters.salt = salt

        let kek = try await KeyDerivation.deriveKEK(password: password, parameters: parameters)
        let masterKey = KeyDerivation.generateMasterKey()

        // Key confirmation: wrap a deterministic marker with the KEK so a
        // wrong password is detected without touching objects.
        let confirmationMarker = Data("sticky-vault-confirmation-v1".utf8)
        let (confNonce, confSealed) = try ObjectCrypto.wrap(masterKeyBytes: confirmationMarker, kek: kek)
        let (masterNonce, masterSealed) = try ObjectCrypto.wrap(
            masterKeyBytes: masterKey.withUnsafeBytes { Data($0) },
            kek: kek
        )

        let bootstrap = VaultBootstrap(
            vaultId: UUID(),
            vaultLocator: RemoteLayout.opaqueObjectName(),
            argon2id: parameters,
            wrappedMasterKey: VaultBootstrap.WrappedKey(nonce: masterNonce, sealed: masterSealed),
            keyConfirmation: VaultBootstrap.WrappedKey(nonce: confNonce, sealed: confSealed)
        )

        // Store the master key in the local secret store (remembered unlock
        // is the app's choice; the raw key never leaves here unencrypted).
        try secretStore.save(masterKey.withUnsafeBytes { Data($0) }, forKey: vaultKeySecretKey(vaultId: bootstrap.vaultId))
        return bootstrap
    }

    /// Opens the vault: derives the KEK from the password, verifies the
    /// key-confirmation blob (wrong password → `.encryption(.wrongPassword)`
    /// BEFORE any object decryption), unwraps the master key.
    public static func openVault(
        _ bootstrap: VaultBootstrap,
        password: String
    ) async throws -> SymmetricKey {
        // Unsupported suite/format → fail closed, never partial.
        guard bootstrap.encryptionSuiteVersion == EncryptionSuite.version else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }
        guard bootstrap.formatVersion == VaultBootstrap.currentFormatVersion else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }

        let kek = try await KeyDerivation.deriveKEK(password: password, parameters: bootstrap.argon2id)

        // Wrong-password detection via key confirmation.
        if let confirmation = bootstrap.keyConfirmation {
            do {
                _ = try ObjectCrypto.unwrap(
                    masterKeyBytes: confirmation.sealed,
                    nonce: confirmation.nonce,
                    kek: kek
                )
            } catch {
                throw StickyError.encryption(.wrongPassword)
            }
        }

        let masterKeyBytes = try ObjectCrypto.unwrap(
            masterKeyBytes: bootstrap.wrappedMasterKey.sealed,
            nonce: bootstrap.wrappedMasterKey.nonce,
            kek: kek
        )
        return SymmetricKey(data: masterKeyBytes)
    }

    /// Password change: re-wraps the master key with the new password's KEK.
    /// Objects are NOT re-encrypted (FR-164). Returns the updated bootstrap.
    public static func changePassword(
        _ bootstrap: VaultBootstrap,
        currentPassword: String,
        newPassword: String
    ) async throws -> VaultBootstrap {
        let oldKEK = try await KeyDerivation.deriveKEK(password: currentPassword, parameters: bootstrap.argon2id)
        // Unwrapping the master key validates the current password.
        let masterKeyBytes = try ObjectCrypto.unwrap(
            masterKeyBytes: bootstrap.wrappedMasterKey.sealed,
            nonce: bootstrap.wrappedMasterKey.nonce,
            kek: oldKEK
        )

        // Fresh salt + params for the new password.
        let salt = KeyDerivation.generateSalt()
        var parameters = Argon2Parameters.recommended
        parameters.salt = salt
        let newKEK = try await KeyDerivation.deriveKEK(password: newPassword, parameters: parameters)

        var updated = bootstrap
        updated.argon2id = parameters
        let (newNonce, newSealed) = try ObjectCrypto.wrap(masterKeyBytes: masterKeyBytes, kek: newKEK)
        updated.wrappedMasterKey = VaultBootstrap.WrappedKey(nonce: newNonce, sealed: newSealed)
        // Re-wrap the key confirmation with the new KEK.
        let confirmationMarker = Data("sticky-vault-confirmation-v1".utf8)
        let (confNonce, confSealed) = try ObjectCrypto.wrap(masterKeyBytes: confirmationMarker, kek: newKEK)
        updated.keyConfirmation = VaultBootstrap.WrappedKey(nonce: confNonce, sealed: confSealed)
        return updated
    }

    /// Stable Keychain key for a vault's remembered-unlock secret.
    public static func vaultKeySecretKey(vaultId: UUID) -> String {
        "vault-master-key-\(vaultId.uuidString)"
    }
}
