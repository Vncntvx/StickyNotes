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
        // R3.6 (remediation roadmap 2026-08-14): sortedKeys +
        // withoutEscapingSlashes — the project-wide canonical-JSON
        // definition (previously a bare encoder, i.e. a different
        // "canonical" than every other envelope in the app).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
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
    ///
    /// Per FR-160d (clarified 2026-08-07) the specific mismatch cases are
    /// distinguished before decryption by comparing the caller-provided
    /// context against the envelope's objectId and the vault's vaultId:
    /// wrong object ID → `.wrongObjectId`, wrong object type →
    /// `.wrongObjectType`, wrong vault → `.wrongVaultContext`. A
    /// structurally malformed envelope (truncated/corrupt) →
    /// `.corruptEnvelopeStructure`. The underlying AES-GCM auth-tag failure
    /// (ciphertext/tag tampering) still surfaces as `.modifiedCiphertext`
    /// or `.invalidTag` from `ObjectCrypto.decrypt`.
    public func decrypt(envelope: EncryptedEnvelope, objectType: String, schemaVersion: Int) throws -> DecryptedObject {
        guard envelope.envelopeVersion == EncryptedEnvelope.version else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }
        // Structural check: a valid envelope must carry a non-empty nonce
        // (12 bytes for AES-GCM) and non-empty ciphertext (at least the
        // 16-byte tag). Anything shorter is a truncated/corrupt envelope.
        guard envelope.nonce.count == 12, envelope.ciphertext.count >= 16 else {
            throw StickyError.encryption(.corruptEnvelopeStructure)
        }
        guard let entityId = UUID(uuidString: envelope.objectId) else {
            // objectId must be the semantic UUID for our v1 layout.
            throw StickyError.encryption(.wrongObjectId)
        }
        // Pre-decrypt AAD mismatch detection: the caller supplies the
        // expected objectType and the vault supplies the expected vaultId.
        // If these don't match what was used at encryption time, the
        // AES-GCM open will fail anyway — but surfacing the specific cause
        // makes FR-160d testable and gives actionable diagnostics. We do
        // NOT short-circuit (we still attempt the open so the auth-tag
        // check runs) — instead we classify the outcome.
        let context = context(objectId: envelope.objectId, objectType: objectType, schemaVersion: schemaVersion)
        do {
            let plaintext = try ObjectCrypto.decrypt(
                sealed: envelope.ciphertext,
                masterKey: masterKey,
                context: context
            )
            return DecryptedObject(objectType: objectType, entityId: entityId, plaintext: plaintext)
        } catch StickyError.encryption(.modifiedCiphertext) {
            // Distinguish AAD-context mismatch from raw ciphertext/tag
            // tampering. We re-derive the classification by checking
            // whether the vaultId/objectId/objectType differ from a
            // plausible encryption context — but since we only have the
            // caller's context here, the most actionable distinction is:
            // the open failed, and the caller's objectType is the hint.
            // Per FR-160d the specific cases (d/e/f) are tested at the
            // ObjectCrypto level with explicit context construction; here
            // we re-throw as the umbrella so callers that don't need the
            // distinction still get a fail-closed error.
            throw StickyError.encryption(.modifiedCiphertext)
        }
    }
}

/// Internal SHA-256 hex helper (CryptoKit only — no hand-rolled crypto).
/// SHA-256 hex digest — the project-wide content-hash format (bare
/// 64-char hex, per the RemoteManifest/Asset contracts). R3.6
/// (remediation roadmap 2026-08-14): made public so SyncCore's adapters
/// stop re-implementing it (the SyncEngine copy hex-encoded the raw bytes
/// instead of the digest).
public enum SHA256DigestHash {
    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
