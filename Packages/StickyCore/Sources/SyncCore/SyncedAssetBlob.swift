import Foundation
import Domain

// MARK: - SyncedAssetBlob (T108: partial asset upload)
//
// The encrypted plaintext for one synced asset. Assets are NOT canonical
// Domain types — they are binary blobs — so the sync layer wraps the raw
// bytes with the minimal metadata the receiver needs (kind, contentType)
// to register the asset locally. The manifest entry's `contentHash` is the
// SHA-256 of the RAW BYTES (matching the asset table's `contentHash`),
// verified after decryption by hashing `bytes` — NOT the hash of this JSON
// wrapper. This keeps the manifest consistent with the asset table and
// avoids re-hashing the wrapper.
//
// v1 schema. Bumping `syncedAssetBlobVersion` is a major sync change
// (re-encrypts every asset).

/// The versioned wire form of one synced asset (encrypted as the envelope
/// plaintext under `objectType = "asset"`).
public struct SyncedAssetBlob: Sendable, Codable, Equatable {
    public static let version = 1

    public var blobVersion: Int
    /// The asset's stable UUID (matches the envelope's objectId; used as
    /// AAD so a substituted asset id fails closed).
    public var assetId: UUID
    public var kind: String
    public var contentType: String
    /// The SHA-256 hex of `bytes` (matches the asset table's contentHash;
    /// redundantly stored so the receiver can integrity-check before import).
    public var contentHash: String
    public var bytes: Data

    public init(
        blobVersion: Int = SyncedAssetBlob.version,
        assetId: UUID,
        kind: String,
        contentType: String,
        contentHash: String,
        bytes: Data
    ) {
        self.blobVersion = blobVersion
        self.assetId = assetId
        self.kind = kind
        self.contentType = contentType
        self.contentHash = contentHash
        self.bytes = bytes
    }

    public func canonicalJSON() throws -> Data {
        // R3.3 (remediation roadmap 2026-08-15): converged on
        // Domain.CanonicalJSONEncoder (single project-wide canonical
        // boundary — dates ISO 8601 UTC with `Z`).
        try CanonicalJSONEncoder().encode(self)
    }

    public static func fromCanonicalJSON(_ data: Data) throws -> SyncedAssetBlob {
        let decoder = CanonicalJSONDecoder()
        guard let decoded = try? decoder.decode(SyncedAssetBlob.self, from: data) else {
            throw StickyError.remoteCorruption(.invalidEnvelope)
        }
        guard decoded.blobVersion == SyncedAssetBlob.version else {
            throw StickyError.encryption(.unsupportedEnvelopeVersion)
        }
        return decoded
    }
}
