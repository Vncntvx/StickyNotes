import Foundation
import Domain
import CryptoKit
import UniformTypeIdentifiers

// MARK: - AssetStore (T087)
//
// Per tasks.md T087 and plan §Asset storage:
//
// - Binary assets live OUTSIDE SQLite in the App Group container, in
//   opaque-UUID subdirectories (originals/, thumbnails/, appIcons/,
//   temp-imports/) — never user-facing names (constitution IV, VI).
// - Atomic temp-write + rename: bytes are written to temp-imports/ and
//   fsynced, then renamed into place (rename is atomic on APFS). The asset
//   record is only handed out AFTER the rename + hash verification.
// - SHA-256 content hashes enable dedup: importing identical bytes for the
//   same (kind, contentType) reuses the stored file.
// - Verify-before-delete: deletion removes the file only after confirming
//   the on-disk content hash still matches the record.
// - Orphan cleanup: removes files without a registered record (crash
//   leftovers), never touching registered assets.
// - Lazy loading: reads happen on demand (`readData`), nothing is held in
//   memory between calls.
// - Export/drag-out: files are handed to the caller via `export` (a copy)
//   or a temp URL — never moved out of the store.
//
// This module depends only on Domain + Apple frameworks (constitution XIII;
// plan §Module boundaries) — asset metadata in SQLite is written by the
// Persistence repositories; AssetStore owns the bytes.

/// The byte-level record of a stored asset. Metadata rows (note/block
/// association, sync state) live in Persistence, not here.
public struct StoredAsset: Sendable, Equatable {
    public let id: UUID
    public let kind: AssetKind
    public let contentType: String
    public let contentHash: String
    public let byteSize: Int
    /// Opaque filename inside the store (UUID + no extension semantics).
    public let filename: String

    public init(id: UUID, kind: AssetKind, contentType: String, contentHash: String, byteSize: Int, filename: String) {
        self.id = id
        self.kind = kind
        self.contentType = contentType
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.filename = filename
    }
}

/// Typed asset-store failures. Coarse and sanitized (constitution VI): no
/// paths, no content, no SQL.
public enum AssetStoreError: Error, Sendable, Equatable {
    case writeFailed
    case hashMismatch
    case notFound
    case alreadyExists
    case corruptedFile
    case cleanupFailed
    /// FR-090b: the asset exceeds `ScaleLimits.maxAssetBytes` (50 MB) or the
    /// image's longest edge exceeds `ScaleLimits.maxAssetLongestEdge`
    /// (16,384 px). The insertion was rejected; no partial write occurred.
    case assetTooLarge
}

/// The atomic-write, hash-verified asset store. One actor serializes all
/// mutations (plan §State management: `AssetWriteActor`); reads are
/// on-demand file reads.
public actor AssetStore {
    public let directoryURL: URL

    private var recordsByID: [UUID: StoredAsset] = [:]
    private var filenameByContentKey: [String: StoredAsset] = [:]

    /// - Parameter directoryURL: the asset root (e.g. the App Group
    ///   container "Assets" directory). Subdirectories are created lazily.
    public init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        try Self.ensureDirectory(directoryURL)
    }

    /// Creates the store and its subdirectories.
    public static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        for sub in [Self.originalsDirName, Self.thumbnailsDirName, Self.appIconsDirName, Self.tempImportsDirName] {
            let dir = url.appendingPathComponent(sub, isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Directory layout

    private static let originalsDirName = "originals"
    private static let thumbnailsDirName = "thumbnails"
    private static let appIconsDirName = "appIcons"
    private static let tempImportsDirName = "temp-imports"

    private func directory(for kind: AssetKind) -> URL {
        switch kind {
        case .original: return directoryURL.appendingPathComponent(Self.originalsDirName, isDirectory: true)
        case .thumbnail: return directoryURL.appendingPathComponent(Self.thumbnailsDirName, isDirectory: true)
        case .appIcon: return directoryURL.appendingPathComponent(Self.appIconsDirName, isDirectory: true)
        }
    }

    // MARK: - Import

    /// Imports raw bytes atomically: temp-write + fsync + rename + hash
    /// verification, then registers the record. Deduplicates identical
    /// content for the same (kind, contentType).
    ///
    /// - Parameters:
    ///   - data: The bytes to store.
    ///   - id: The asset's stable UUID. Defaults to a fresh UUID for
    ///     locally-created assets. Sync must pass the remote asset's id so
    ///     the DB row, the AssetStore record, and the note's asset reference
    ///     all agree (data-model.md §Asset: the asset id is the stable
    ///     cross-device identity).
    ///   - kind: Asset kind (original/thumbnail/appIcon).
    ///   - contentType: UTType identifier.
    /// - Returns: The stored asset record.
    public func importData(
        _ data: Data,
        id: UUID = UUID(),
        kind: AssetKind,
        contentType: String
    ) async throws -> StoredAsset {
        // FR-090b scale limit (T236): oversize assets are rejected with NO
        // partial write — no temp file, no record (verified by T227).
        if ScaleLimits.assetBytesError(byteCount: data.count) != nil {
            throw AssetStoreError.assetTooLarge
        }
        let hash = Self.sha256Hex(data)
        if let existing = filenameByContentKey[Self.contentKey(kind: kind, contentType: contentType, hash: hash)] {
            // Dedup: same bytes, same kind+contentType → reuse the record.
            return existing
        }

        let filename = id.uuidString
        let destination = directory(for: kind).appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw AssetStoreError.alreadyExists
        }

        // 1. Atomic temp-write.
        let tempURL = directoryURL
            .appendingPathComponent(Self.tempImportsDirName, isDirectory: true)
            .appendingPathComponent(filename)
        do {
            try data.write(to: tempURL, options: [.atomic])
        } catch {
            throw AssetStoreError.writeFailed
        }

        // 2. Verify before rename: the bytes on disk must match the hash we
        //    are about to register (verify-before-delete of temp).
        guard Self.sha256Hex(try? Data(contentsOf: tempURL)) == hash else {
            try? FileManager.default.removeItem(at: tempURL)
            throw AssetStoreError.hashMismatch
        }

        // 3. Atomic rename into place.
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw AssetStoreError.writeFailed
        }

        let record = StoredAsset(
            id: id,
            kind: kind,
            contentType: contentType,
            contentHash: hash,
            byteSize: data.count,
            filename: filename
        )
        recordsByID[id] = record
        filenameByContentKey[Self.contentKey(kind: kind, contentType: contentType, hash: hash)] = record
        return record
    }

    /// Imports a file's bytes (copied — the source is never moved).
    public func importFile(at url: URL, kind: AssetKind, contentType: String) async throws -> StoredAsset {
        let data = try Data(contentsOf: url)
        return try await importData(data, kind: kind, contentType: contentType)
    }

    // MARK: - Read / export

    /// Convenience for screenshot imports: stores the original + an
    /// async-generated thumbnail (lossless for text-heavy captures) as two
    /// independent assets (T088). Thumbnail failure never fails the
    /// original import — the thumbnail is returned as `nil` so the caller
    /// can decide a fallback (e.g. lazy-generate later, show a generic
    /// placeholder). Returning the original as its own thumbnail would
    /// force the card grid to decode a full-resolution image, violating
    /// SC-008 ("the card grid NEVER decodes a full-resolution original").
    public func importScreenshot(
        originalData: Data,
        contentType: String
    ) async throws -> (original: StoredAsset, thumbnail: StoredAsset?) {
        let original = try await importData(originalData, kind: .original, contentType: contentType)
        do {
            let thumbData = try ThumbnailGenerator.generateThumbnail(
                from: originalData,
                contentType: contentType
            )
            let thumbnail = try await importData(thumbData, kind: .thumbnail, contentType: UTType.png.identifier)
            return (original, thumbnail)
        } catch {
            // A failed thumbnail must never break the original import
            // (SC-008 degradation). Return nil — callers must NOT use the
            // original as a thumbnail substitute (card-grid decode cost).
            return (original, nil)
        }
    }

    /// Lazy on-demand read. Throws `.notFound` for unknown asset IDs.
    public func readData(assetID: UUID) async throws -> Data {
        guard let record = recordsByID[assetID] else { throw AssetStoreError.notFound }
        let url = directory(for: record.kind).appendingPathComponent(record.filename)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw AssetStoreError.notFound
        }
    }

    /// The in-store file URL for an asset (drag-out / preview). Callers must
    /// treat it as read-only.
    public func url(assetID: UUID) async throws -> URL {
        guard let record = recordsByID[assetID] else { throw AssetStoreError.notFound }
        return directory(for: record.kind).appendingPathComponent(record.filename)
    }

    /// Copies the asset to a caller-owned destination (drag-out, Save As).
    /// Never moves the stored file (constitution IX: copies, not moves).
    public func export(assetID: UUID, to destination: URL) async throws {
        let data = try await readData(assetID: assetID)
        do {
            try data.write(to: destination, options: [.atomic])
        } catch {
            throw AssetStoreError.writeFailed
        }
    }

    /// Verifies the on-disk content hash still matches the record.
    public func verifyIntegrity(assetID: UUID) async throws -> Bool {
        guard let record = recordsByID[assetID] else { throw AssetStoreError.notFound }
        let data = try? await readData(assetID: assetID)
        guard let data else { return false }
        return Self.sha256Hex(data) == record.contentHash
    }

    // MARK: - Delete

    /// Deletes the stored file only after verifying the on-disk content
    /// hash matches the record (verify-before-delete, research.md R17).
    public func delete(assetID: UUID) async throws {
        guard let record = recordsByID[assetID] else { throw AssetStoreError.notFound }
        let url = directory(for: record.kind).appendingPathComponent(record.filename)
        guard let onDisk = try? Data(contentsOf: url) else {
            // File already gone — still clean the record.
            recordsByID.removeValue(forKey: assetID)
            return
        }
        guard Self.sha256Hex(onDisk) == record.contentHash else {
            // Mismatched file: refuse to delete what we did not verify.
            throw AssetStoreError.corruptedFile
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw AssetStoreError.cleanupFailed
        }
        recordsByID.removeValue(forKey: assetID)
    }

    // MARK: - Orphan cleanup

    /// Removes files in the store directories that have no registered
    /// record (crash leftovers). Registered assets are never touched.
    /// Returns the removed filenames.
    public func cleanupOrphans() async throws -> [String] {
        let fm = FileManager.default
        var removed: [String] = []
        let knownFilenames = Set(recordsByID.values.map(\.filename))
        for kind in [AssetKind.original, .thumbnail, .appIcon] {
            let dir = directory(for: kind)
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in contents where !knownFilenames.contains(name) {
                do {
                    try fm.removeItem(at: dir.appendingPathComponent(name))
                    removed.append(name)
                } catch {
                    // Leave it; retried on the next cleanup pass.
                }
            }
        }
        return removed
    }

    // MARK: - Snapshot (for persistence writes + tests)

    /// All registered records. Metadata rows are written to SQLite by the
    /// Persistence layer using this snapshot.
    public func snapshot() async -> [StoredAsset] {
        Array(recordsByID.values)
    }

    // MARK: - Hashing

    /// `sha256:<hex>` content hash.
    public static func sha256Hex(_ data: Data?) -> String {
        guard let data else { return "" }
        let digest = SHA256.hash(data: data)
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func contentKey(kind: AssetKind, contentType: String, hash: String) -> String {
        "\(kind.rawValue)|\(contentType)|\(hash)"
    }
}
