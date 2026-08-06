import Foundation
import CryptoKit
import Domain

// MARK: - EncryptedEnvelope (T111)
//
// Per contracts/encrypted-envelope.schema.json: versioned framing for one
// encrypted object. Contains ONLY safe framing: version, opaque object ID,
// nonce, ciphertext. The AAD (vault/object/type/schema/suite context) is NOT
// repeated here (substitution defense).

/// The wire envelope for one encrypted object (schema version 1).
public struct EncryptedEnvelope: Sendable, Equatable, Codable {
    public static let version = 1

    public var envelopeVersion: Int
    /// Opaque object identifier (not necessarily the semantic entity UUID).
    public var objectId: String
    public var nonce: Data
    /// AES-GCM combined ciphertext (includes the auth tag).
    public var ciphertext: Data

    public init(envelopeVersion: Int = EncryptedEnvelope.version, objectId: String, nonce: Data, ciphertext: Data) {
        self.envelopeVersion = envelopeVersion
        self.objectId = objectId
        self.nonce = nonce
        self.ciphertext = ciphertext
    }

    public func canonicalJSON() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func fromCanonicalJSON(_ data: Data) throws -> EncryptedEnvelope {
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(EncryptedEnvelope.self, from: data) else {
            throw StickyError.remoteCorruption(.invalidEnvelope)
        }
        guard decoded.envelopeVersion == EncryptedEnvelope.version else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }
        return decoded
    }
}

/// A decrypted, authenticated sync object. Sent across module boundaries as
/// a Sendable value.
public struct DecryptedObject: Sendable, Equatable {
    /// The semantic entity type (e.g. "note", "asset", "tombstone"). Part of
    /// the AAD — tampering fails closed.
    public let objectType: String
    /// The semantic entity UUID (the objectId inside the envelope is opaque).
    public let entityId: UUID
    /// Canonical plaintext bytes (JSON, per the relevant contract).
    public let plaintext: Data
    /// SHA-256 hex of the canonical plaintext (manifest integrity, T118).
    public let contentHash: String

    public init(objectType: String, entityId: UUID, plaintext: Data) {
        self.objectType = objectType
        self.entityId = entityId
        self.plaintext = plaintext
        self.contentHash = SHA256DigestHash.hash(plaintext)
    }
}

/// A running vault: the unwrapped master key plus the immutable context
/// identity. Keep instances short-lived; release after use (key lifecycle,
/// plan §Encryption architecture).
public struct Vault: Sendable {
    public let vaultId: UUID
    public let encryptionSuiteVersion: Int
    public let masterKey: SymmetricKey

    public init(vaultId: UUID, encryptionSuiteVersion: Int, masterKey: SymmetricKey) {
        self.vaultId = vaultId
        self.encryptionSuiteVersion = encryptionSuiteVersion
        self.masterKey = masterKey
    }

    /// The AAD context for one object.
    public func context(objectId: String, objectType: String, schemaVersion: Int) -> ObjectCryptoContext {
        ObjectCryptoContext(
            vaultId: vaultId,
            objectId: objectId,
            objectType: objectType,
            schemaVersion: schemaVersion,
            encryptionSuiteVersion: encryptionSuiteVersion
        )
    }

    /// Encrypts canonical bytes into a wire envelope.
    public func encrypt(objectId: String, objectType: String, schemaVersion: Int, plaintext: Data) throws -> EncryptedEnvelope {
        let context = context(objectId: objectId, objectType: objectType, schemaVersion: schemaVersion)
        let (nonce, sealed) = try ObjectCrypto.encrypt(plaintext, masterKey: masterKey, context: context)
        return EncryptedEnvelope(objectId: objectId, nonce: nonce, ciphertext: sealed)
    }

    /// Decrypts + authenticates a wire envelope. ANY failure fails closed
    /// (`.encryption(.modifiedCiphertext)` / `.wrongObjectContext`).
    public func decrypt(envelope: EncryptedEnvelope, objectType: String, schemaVersion: Int) throws -> DecryptedObject {
        guard envelope.envelopeVersion == EncryptedEnvelope.version else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }
        guard let entityId = UUID(uuidString: envelope.objectId) else {
            // objectId must be the semantic UUID for our v1 layout.
            throw StickyError.encryption(.wrongObjectContext)
        }
        let context = context(objectId: envelope.objectId, objectType: objectType, schemaVersion: schemaVersion)
        let plaintext = try ObjectCrypto.decrypt(
            sealed: envelope.ciphertext,
            masterKey: masterKey,
            context: context
        )
        return DecryptedObject(objectType: objectType, entityId: entityId, plaintext: plaintext)
    }
}

/// Internal SHA-256 hex helper (CryptoKit only — no hand-rolled crypto).
enum SHA256DigestHash {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
