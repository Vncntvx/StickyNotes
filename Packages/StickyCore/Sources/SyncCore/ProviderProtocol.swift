import Foundation
import Domain

// MARK: - ProviderProtocol (T113)
//
// Per contracts/provider-protocol.md: the provider-neutral repository
// protocol. Adapters contain NO conflict-resolution policy — that lives in
// the sync engine.
//
// Rules the protocol enforces:
// - Idempotent / safely repeatable operations.
// - Opaque object names (RemoteLayout).
// - Normalized errors only (ProviderError).
// - Cancellation propagates as `.canceled`.
// - HTTPS-only enforcement happens in the concrete adapters (T114/T115).

/// Metadata for one remote object.
public struct ObjectMetadata: Sendable, Equatable {
    public let objectName: String
    /// Version token (WebDAV ETag / S3 ETag) — used for conditional ops.
    public let versionToken: String?
    public let byteSize: Int?
    public let modifiedAt: Date?

    public init(objectName: String, versionToken: String?, byteSize: Int?, modifiedAt: Date?) {
        self.objectName = objectName
        self.versionToken = versionToken
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }
}

/// The manifest fetch result: bytes + the version token for conditional
/// replacement.
public struct ManifestFetchResult: Sendable, Equatable {
    public let data: Data
    public let versionToken: String

    public init(data: Data, versionToken: String) {
        self.data = data
        self.versionToken = versionToken
    }
}

/// The provider-neutral repository protocol (provider-protocol.md).
public protocol SyncProviderProtocol: Sendable {
    /// Verify connectivity + credentials; ensure the vault container exists
    /// (create it when absent and authorized).
    func verify() async throws

    /// Fetch metadata for one object (existence, version token, size, time).
    func fetchMetadata(objectName: String) async throws -> ObjectMetadata?

    /// Fetch an object's bytes.
    func fetch(objectName: String) async throws -> Data

    /// Conditionally CREATE an object (`If-None-Match: *`). Throws
    /// `.conditionalFailed` when the object already exists (acceptable,
    /// idempotent).
    func upload(objectName: String, data: Data) async throws

    /// Conditionally REPLACE an object (`If-Match: <versionToken>`). Throws
    /// `.conditionalFailed` when the token is stale.
    func replace(objectName: String, data: Data, ifMatch: String) async throws

    /// Conditionally delete (best-effort `If-Match` where supported; a
    /// missing object is treated as idempotent success).
    func delete(objectName: String, ifMatch: String?) async throws

    /// List object names + metadata under the vault locator (recovery path
    /// when the manifest is missing/corrupt).
    func list() async throws -> [ObjectMetadata]

    /// Fetch the manifest object + its version token.
    func fetchManifest() async throws -> ManifestFetchResult

    /// Conditionally replace the manifest (`If-Match`).
    func replaceManifest(data: Data, ifMatch: String) async throws
}
