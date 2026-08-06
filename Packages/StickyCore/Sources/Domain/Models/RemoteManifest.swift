import Foundation

// MARK: - Remote manifest models (T110)
//
// Per contracts/encrypted-manifest.schema.json + tombstone.schema.json: the
// decrypted manifest payload. Object names are OPAQUE — the manifest lists
// only opaque names + sizes/times; semantic type is inside the encrypted
// object, never in filenames (constitution VII; research.md R11/R12).

/// One remote object entry in the manifest. Names are opaque; nothing
/// semantic is exposed here (T110: "manifest carries only opaque
/// names+sizes/times").
public struct RemoteObjectEntry: Sendable, Equatable, Hashable, Codable {
    /// Opaque remote object name (random; the provider sees this only).
    public let objectName: String
    /// Opaque object id matching the envelope's objectId (used as AAD).
    public let objectId: String
    /// SHA-256 (hex, 64 chars) of the decrypted canonical object bytes.
    public let contentHash: String
    public let byteSize: Int
    public let modifiedAt: Date

    public init(objectName: String, objectId: String, contentHash: String, byteSize: Int, modifiedAt: Date) {
        self.objectName = objectName
        self.objectId = objectId
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }
}

/// A deletion record tracked at the manifest level (tombstone.schema.json).
/// Carries enough version lineage to prevent resurrection (constitution
/// VIII; research.md R15).
public struct RemoteTombstone: Sendable, Equatable, Hashable, Codable {
    public let noteId: UUID
    public let deletedVersionId: UUID
    public let parentVersionId: UUID?
    public let deletingDeviceId: UUID
    public let deletedAt: Date

    public init(noteId: UUID, deletedVersionId: UUID, parentVersionId: UUID?, deletingDeviceId: UUID, deletedAt: Date) {
        self.noteId = noteId
        self.deletedVersionId = deletedVersionId
        self.parentVersionId = parentVersionId
        self.deletingDeviceId = deletingDeviceId
        self.deletedAt = deletedAt
    }
}

/// The decrypted remote manifest (encrypted-manifest.schema.json).
public struct RemoteManifest: Sendable, Equatable, Hashable, Codable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    /// Opaque version token used as the If-Match precondition.
    public var manifestVersion: String
    public var vaultId: UUID
    public var entries: [RemoteObjectEntry]
    public var tombstones: [RemoteTombstone]
    public var updatedAt: Date
    public var updatedByDeviceId: UUID

    public init(
        schemaVersion: Int = RemoteManifest.schemaVersion,
        manifestVersion: String,
        vaultId: UUID,
        entries: [RemoteObjectEntry] = [],
        tombstones: [RemoteTombstone] = [],
        updatedAt: Date = Date(),
        updatedByDeviceId: UUID
    ) {
        self.schemaVersion = schemaVersion
        self.manifestVersion = manifestVersion
        self.vaultId = vaultId
        self.entries = entries
        self.tombstones = tombstones
        self.updatedAt = updatedAt
        self.updatedByDeviceId = updatedByDeviceId
    }
}

/// Remote-layout policy (T110): remote object names must be random/opaque
/// and must not encode any semantic type.
public enum RemoteLayout {
    /// Generates an opaque remote object name. No semantic type, no entity
    /// UUID — only randomness.
    public static func opaqueObjectName() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Whether an object name is opaque (matches the generated shape).
    public static func isOpaque(_ name: String) -> Bool {
        name.count == 32 && name.allSatisfy { $0.isHexDigit }
    }
}
