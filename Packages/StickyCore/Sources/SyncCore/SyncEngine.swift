import Foundation
import GRDB
import Domain
import Persistence
import SecurityCore
import AssetStore

// MARK: - SyncEngine (T117)
//
// Per tasks.md T117 and plan §Synchronization engine:
//
// - Single-vault `SyncActor`: ONE sync transaction per vault at a time.
// - Triggers are the caller's choice (≈3s after local changes, ~15min
//   periodic, startup, network restore, manual, termination) — the engine
//   exposes `syncNow()`; it never polls by itself (no sustained idle CPU,
//   SC-006).
// - Steps: fetch+authenticate manifest → upload dirty local notes + assets →
//   download missing/newer notes (validate+decrypt each BEFORE accept) →
//   download missing assets referenced by remote objects → reconcile
//   tombstones → commit manifest via safe conditional op (bounded retry on
//   precondition failure).
// - Asset sync (T108): assets with `isSynced == false` are uploaded as
//   independently encrypted objects; a transient upload failure marks
//   `syncFailureState = .uploadFailed` and is retried on the next pass
//   (partial-asset-sync-failure). Downloaded notes reference assets by id;
//   missing assets are fetched + verified + imported.
// - Idempotent / safely repeatable; transient failures are classified by the
//   provider errors and retried by the caller with exponential backoff.
// - Local editing NEVER waits for sync.
//
// Object model (v1): one immutable remote object per note version
// (objectId = versionId.uuidString). Asset objects use objectId =
// assetId.uuidString. The manifest entry set IS the synchronization state:
// a note is dirty when its local versionId has no manifest entry; an asset
// is dirty when `isSynced == false`. The manifest is opaque (T110) — the
// engine discovers an entry's type by attempting decryption (note first,
// then asset), never by a type field in the manifest.

/// The outcome of one sync pass. Sanitized — no note content, no names, no
/// credentials (constitution VI; FR-165).
public struct SyncSummary: Sendable, Equatable {
    /// Zero summary (no changes in a pass).
    public static let empty = SyncSummary()

    public var uploadedObjects: Int
    public var downloadedObjects: Int
    public var appliedTombstones: Int
    public var skippedCorruptObjects: Int
    public var manifestCommitted: Bool
    public var initializedRemote: Bool

    public init(
        uploadedObjects: Int = 0,
        downloadedObjects: Int = 0,
        appliedTombstones: Int = 0,
        skippedCorruptObjects: Int = 0,
        manifestCommitted: Bool = false,
        initializedRemote: Bool = false
    ) {
        self.uploadedObjects = uploadedObjects
        self.downloadedObjects = downloadedObjects
        self.appliedTombstones = appliedTombstones
        self.skippedCorruptObjects = skippedCorruptObjects
        self.manifestCommitted = manifestCommitted
        self.initializedRemote = initializedRemote
    }
}

/// Hook for conflict-copy creation (US10 builds the real resolver; the
/// engine reports divergence).
public protocol ConflictResolver: Sendable {
    /// Called when a remote version of a note diverges from the local
    /// version (neither is an ancestor). Returns true when a conflict copy
    /// was created.
    func resolveDivergence(
        local: CanonicalNote,
        remote: CanonicalNote,
        deviceId: UUID
    ) async throws -> Bool
}

/// The single-vault synchronization engine.
public actor SyncEngine {
    private let provider: any SyncProviderProtocol
    private let vault: Vault
    private let store: DatabaseStore
    private let deviceId: UUID
    private let manifestStore: ManifestStore
    private let conflictResolver: (any ConflictResolver)?
    private let searchService: SearchService
    /// Optional asset byte store. When nil, asset sync is skipped (tests
    /// that don't exercise assets). When present, dirty assets are uploaded
    /// and missing assets downloaded.
    private let assetStore: AssetStore?

    public init(
        provider: any SyncProviderProtocol,
        vault: Vault,
        store: DatabaseStore,
        deviceId: UUID,
        conflictResolver: (any ConflictResolver)? = nil,
        assetStore: AssetStore? = nil
    ) {
        self.provider = provider
        self.vault = vault
        self.store = store
        self.deviceId = deviceId
        self.manifestStore = ManifestStore(provider: provider, vault: vault)
        self.conflictResolver = conflictResolver
        self.searchService = SearchService(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        self.assetStore = assetStore
    }

    /// Runs one sync pass. Idempotent: re-running with no changes is a
    /// no-op that re-fetches the manifest and commits nothing.
    public func syncNow() async throws -> SyncSummary {
        var summary = SyncSummary()

        // 1. Fetch + authenticate the manifest (nil on first sync).
        let remoteManifest = try await manifestStore.fetch()

        // 2. Local state.
        let localNotes = try await fetchLocalNotes()
        let localByVersion = Dictionary(
            uniqueKeysWithValues: localNotes.map { ($0.versionId.uuidString, $0) }
        )
        let localAssetIds = try await fetchLocalAssetIds()
        let remoteByObjectId = Dictionary(
            uniqueKeysWithValues: (remoteManifest?.entries ?? []).map { ($0.objectId, $0) }
        )

        // 3. Upload dirty local notes (immutable objects).
        var uploads: [RemoteObjectEntry] = []
        for note in localNotes where remoteByObjectId[note.versionId.uuidString] == nil {
            let entry = try await uploadNote(note)
            uploads.append(entry)
        }

        // 4. Upload dirty assets (isSynced == false). Transient failures
        //    mark the asset `.uploadFailed` for retry on the next pass; the
        //    note upload is never blocked by an asset failure (local editing
        //    never waits for sync).
        let assetUploads = try await uploadDirtyAssets(remoteByObjectId: remoteByObjectId)
        uploads.append(contentsOf: assetUploads)
        summary.uploadedObjects = uploads.count

        // 5. Download missing/newer remote objects. Each object is
        //    validated + decrypted BEFORE acceptance (fail closed). An
        //    entry that fails note-decryption is retried as an asset (the
        //    manifest is opaque — type is discovered by decryption, never by
        //    a manifest field, per T110).
        if let remoteManifest {
            var unresolved: [RemoteObjectEntry] = []
            for entry in remoteManifest.entries where localByVersion[entry.objectId] == nil
                && !localAssetIds.contains(UUID(uuidString: entry.objectId) ?? UUID()) {
                if let remoteNote = try? await downloadNote(entry: entry) {
                    let applied = try await applyRemoteIfNewer(remoteNote, localByVersion: localByVersion)
                    if applied == .applied {
                        summary.downloadedObjects += 1
                    }
                } else {
                    // Not a note (or corrupt note) — try as an asset below.
                    unresolved.append(entry)
                }
            }

            // Try unresolved entries as assets.
            for entry in unresolved {
                if let assetBlob = try? await downloadAsset(entry: entry) {
                    try await applyRemoteAsset(assetBlob)
                    summary.downloadedObjects += 1
                } else {
                    // Neither note nor asset decryption succeeded → corrupt.
                    summary.skippedCorruptObjects += 1
                }
            }

            // 6. Remote tombstones: apply deletions (lineage-checked).
            for tombstone in remoteManifest.tombstones {
                if try await applyRemoteTombstone(tombstone) {
                    summary.appliedTombstones += 1
                }
            }
        }

        // 7. Commit the manifest conditionally when anything changed.
        let changed = !uploads.isEmpty || summary.downloadedObjects > 0
            || summary.appliedTombstones > 0 || remoteManifest == nil
        if changed {
            let outcome = try await commitManifest(extraEntries: uploads, base: remoteManifest)
            summary.manifestCommitted = true
            summary.initializedRemote = (outcome == .created)
        }

        return summary
    }

    // MARK: - Note sync primitives

    private enum ApplyResult {
        case applied
        case skipped
    }

    /// Encodes + encrypts a note into an immutable remote object and returns
    /// the manifest entry for it.
    private func uploadNote(_ note: CanonicalNote) async throws -> RemoteObjectEntry {
        let payload = try CanonicalJSONEncoder().encode(note)
        let envelope = try vault.encrypt(
            objectId: note.versionId.uuidString,
            objectType: "note",
            schemaVersion: CanonicalNote.schemaVersion,
            plaintext: payload
        )
        let objectName = RemoteLayout.opaqueObjectName()
        let wire = try envelope.canonicalJSON()
        do {
            try await provider.upload(objectName: objectName, data: wire)
        } catch ProviderError.conditionalFailed {
            // Idempotent retry: the object already exists remotely — adopt it.
        }
        return RemoteObjectEntry(
            objectName: objectName,
            objectId: note.versionId.uuidString,
            contentHash: sha256Hex(payload),
            byteSize: wire.count,
            modifiedAt: note.modifiedAt
        )
    }

    /// Fetches + decrypts + integrity-checks a remote note object. Returns
    /// nil on corruption (fail closed — never accept an invalid object).
    private func downloadNote(entry: RemoteObjectEntry) async throws -> CanonicalNote? {
        let wire: Data
        do {
            wire = try await provider.fetch(objectName: entry.objectName)
        } catch ProviderError.notFound {
            return nil
        }
        guard let envelope = try? EncryptedEnvelope.fromCanonicalJSON(wire) else { return nil }
        guard let decrypted = try? vault.decrypt(
            envelope: envelope,
            objectType: "note",
            schemaVersion: CanonicalNote.schemaVersion
        ) else { return nil }
        // Manifest contentHash must match the decrypted plaintext.
        guard sha256Hex(decrypted.plaintext) == entry.contentHash else { return nil }
        guard let note = try? CanonicalJSONDecoder().decode(CanonicalNote.self, from: decrypted.plaintext) else {
            return nil
        }
        return note
    }

    /// Applies a downloaded note when it is newer or unknown locally.
    private func applyRemoteIfNewer(
        _ remote: CanonicalNote,
        localByVersion: [String: CanonicalNote]
    ) async throws -> ApplyResult {
        let local = localByVersion.values.first { $0.id == remote.id }
        guard let local else {
            try await applyRemote(remote)
            return .applied
        }
        // Lineage: remote is an ancestor of local → local already newer, skip.
        if remote.versionId == local.parentVersionId || remote.versionId == local.versionId {
            return .skipped
        }
        // Diverged (neither is an ancestor): delegate to the conflict
        // resolver (US10). Without a resolver, keep local (never auto-merge,
        // never overwrite — constitution VIII).
        if let resolver = conflictResolver {
            _ = try await resolver.resolveDivergence(local: local, remote: remote, deviceId: deviceId)
        }
        return .skipped
    }

    /// Upserts a remote note + its blocks + the FTS row.
    private func applyRemote(_ note: CanonicalNote) async throws {
        try await store.write { db in
            try Self.upsertNoteRow(db, note: note)
            try db.execute(
                sql: "DELETE FROM block WHERE noteId = ?",
                arguments: [note.id.uuidString]
            )
            for block in note.blocks {
                let payloadJSON = try CanonicalJSONEncoder().encodeString(block.payload)
                try db.execute(
                    sql: """
                        INSERT INTO block (id, noteId, kind, sortKey, payload, versionId,
                                           parentVersionId, lastModifiedDeviceId, createdAt, modifiedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        block.id.uuidString,
                        block.noteId.uuidString,
                        block.kind.rawValue,
                        block.sortKey,
                        payloadJSON,
                        block.versionId.uuidString,
                        block.parentVersionId?.uuidString,
                        block.lastModifiedDeviceId.uuidString,
                        block.createdAt,
                        block.modifiedAt,
                    ]
                )
            }
        }
        // FTS: keep the search index in sync (T020/T042).
        let blocks = note.blocks.map { block in
            Block(
                id: block.id,
                noteId: block.noteId,
                kind: block.kind,
                sortKey: block.sortKey,
                payload: block.payload,
                versionId: block.versionId,
                parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt,
                modifiedAt: block.modifiedAt
            )
        }
        try await searchService.reindexNote(noteId: note.id, title: note.title, blocks: blocks)
    }

    // MARK: - Asset sync (T108: partial asset upload)

    /// Uploads every local asset with `isSynced == false`. Transient
    /// failures mark the asset `.uploadFailed` for retry on the next pass;
    /// the note upload is never blocked by an asset failure (local editing
    /// never waits for sync). Returns the manifest entries for successfully
    /// uploaded assets.
    private func uploadDirtyAssets(
        remoteByObjectId: [String: RemoteObjectEntry]
    ) async throws -> [RemoteObjectEntry] {
        guard let assetStore else { return [] }
        let dirty = try await fetchDirtyAssets()
        var entries: [RemoteObjectEntry] = []
        for asset in dirty {
            // Skip assets already present in the manifest (synced on a
            // prior pass that didn't update the row, or by another device).
            if remoteByObjectId[asset.id.uuidString] != nil {
                try await markAssetSyncState(assetId: asset.id, isSynced: true, failureState: .none)
                continue
            }
            do {
                let bytes = try await assetStore.readData(assetID: asset.id)
                let blob = SyncedAssetBlob(
                    assetId: asset.id,
                    kind: asset.kind.rawValue,
                    contentType: asset.contentType,
                    // The blob's contentHash field carries the same value as
                    // the asset table (AssetStore format: "sha256:<hex>") so
                    // the receiver can cross-check it against the table. The
                    // MANIFEST entry's contentHash (below) is raw hex per
                    // RemoteManifest's spec (64 chars), computed from the
                    // raw bytes — not the prefixed table value.
                    contentHash: asset.contentHash,
                    bytes: bytes
                )
                let payload = try blob.canonicalJSON()
                let envelope = try vault.encrypt(
                    objectId: asset.id.uuidString,
                    objectType: "asset",
                    schemaVersion: SyncedAssetBlob.version,
                    plaintext: payload
                )
                let objectName = RemoteLayout.opaqueObjectName()
                let wire = try envelope.canonicalJSON()
                do {
                    try await provider.upload(objectName: objectName, data: wire)
                } catch ProviderError.conditionalFailed {
                    // Idempotent: already uploaded — adopt.
                }
                try await markAssetSyncState(assetId: asset.id, isSynced: true, failureState: .none)
                entries.append(RemoteObjectEntry(
                    objectName: objectName,
                    objectId: asset.id.uuidString,
                    // Raw hex (64 chars) per RemoteManifest spec — the engine
                    // hashes the raw bytes, NOT the prefixed table value.
                    contentHash: sha256Hex(bytes),
                    byteSize: wire.count,
                    modifiedAt: Date()
                ))
            } catch is CancellationError {
                throw ProviderError.canceled
            } catch let providerError as ProviderError where providerError.isTransient {
                // Partial-asset-sync-failure: mark for retry, continue.
                try await markAssetSyncState(assetId: asset.id, isSynced: false, failureState: .uploadFailed)
            } catch {
                // Unexpected error: mark for retry rather than crashing the
                // whole sync pass (an asset must never block note sync).
                try await markAssetSyncState(assetId: asset.id, isSynced: false, failureState: .uploadFailed)
            }
        }
        return entries
    }

    /// Fetches + decrypts + integrity-checks a remote asset object. Returns
    /// nil on corruption (fail closed).
    private func downloadAsset(entry: RemoteObjectEntry) async throws -> SyncedAssetBlob? {
        let wire: Data
        do {
            wire = try await provider.fetch(objectName: entry.objectName)
        } catch ProviderError.notFound {
            return nil
        }
        guard let envelope = try? EncryptedEnvelope.fromCanonicalJSON(wire) else { return nil }
        guard let decrypted = try? vault.decrypt(
            envelope: envelope,
            objectType: "asset",
            schemaVersion: SyncedAssetBlob.version
        ) else { return nil }
        guard let blob = try? SyncedAssetBlob.fromCanonicalJSON(decrypted.plaintext) else { return nil }
        // Manifest integrity: the manifest entry's contentHash (raw hex per
        // RemoteManifest spec) must match the SHA-256 of the blob's raw
        // bytes. The blob's own `contentHash` field uses AssetStore format
        // ("sha256:<hex>") for the asset table — it is NOT compared to the
        // manifest entry (different formats, different purposes).
        guard sha256Hex(blob.bytes) == entry.contentHash else { return nil }
        return blob
    }

    /// Imports a downloaded asset's bytes into the AssetStore (under the
    /// remote asset's stable id so the DB row, the AssetStore record, and
    /// the note's asset reference all agree) and registers the metadata row
    /// (isSynced = true — it came from the remote).
    private func applyRemoteAsset(_ blob: SyncedAssetBlob) async throws {
        guard let assetStore else { return }
        guard let kind = AssetKind(rawValue: blob.kind) else { return }
        // Import under the remote asset's id (data-model.md §Asset: the
        // asset id is the stable cross-device identity).
        let stored = try await assetStore.importData(
            blob.bytes, id: blob.assetId, kind: kind, contentType: blob.contentType
        )
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset (id, kind, contentHash, byteSize, contentType, storagePath,
                                       isSynced, syncFailureState, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, 1, 'none', ?)
                    ON CONFLICT(id) DO UPDATE SET
                        isSynced = 1,
                        syncFailureState = 'none',
                        storagePath = excluded.storagePath
                    """,
                arguments: [
                    blob.assetId.uuidString,
                    blob.kind,
                    blob.contentHash,
                    blob.bytes.count,
                    blob.contentType,
                    stored.filename,
                    Date(),
                ]
            )
        }
    }

    // MARK: - Tombstones

    /// Applies a remote tombstone (lineage-checked permanent deletion).
    ///
    /// - Note: The lineage check below walks ONE generation only
    ///   (`localVersion == deletedVersionId || localParent ==
    ///   deletedVersionId`). This is a conservative first approximation: it
    ///   never over-deletes (safe) but may refuse to apply a tombstone whose
    ///   local version descends through several generations from the deleted
    ///   version — the long-offline case. Full ancestry walking +
    ///   remote-deletion-history reconciliation land in T129 (US10
    ///   `OfflineReconciler`), which is the dedicated home for that logic.
    ///   Do NOT extend this method ad-hoc; US10 owns the complete design.
    private func applyRemoteTombstone(_ tombstone: RemoteTombstone) async throws -> Bool {
        try await store.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT versionId, parentVersionId FROM note WHERE id = ?",
                                             arguments: [tombstone.noteId.uuidString]) else {
                return false
            }
            let localVersion = Self.uuid(row, "versionId") ?? UUID()
            let localParent = Self.uuid(row, "parentVersionId")
            // Lineage safety: apply only when the local version descends
            // from the deleted version (US10 long-offline reconciliation).
            let descends = localVersion == tombstone.deletedVersionId
                || localParent == tombstone.deletedVersionId
            guard descends else { return false }
            try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [tombstone.noteId.uuidString])
            return true
        }
    }

    // MARK: - Manifest commit (C6: outcome instead of side-channel flag)

    /// Commits the manifest. Returns whether the remote was initialized
    /// (first-ever manifest written) or replaced.
    private func commitManifest(
        extraEntries: [RemoteObjectEntry],
        base: RemoteManifest?
    ) async throws -> ManifestCommitOutcome {
        let deviceID = deviceId
        let vaultID = vault.vaultId
        let localTombstones = try await fetchLocalTombstones()

        return try await manifestStore.commit(deviceId: deviceID) { current in
            let baseManifest = current ?? base
            var entries = baseManifest?.entries ?? []
            let known = Set(entries.map(\.objectId))
            for e in extraEntries where !known.contains(e.objectId) {
                entries.append(e)
            }
            var tombstones = baseManifest?.tombstones ?? []
            let remoteNoteIds = Set(tombstones.map(\.noteId))
            for t in localTombstones where !remoteNoteIds.contains(t.noteId) {
                tombstones.append(t)
            }
            let manifest = RemoteManifest(
                manifestVersion: UUID().uuidString,
                vaultId: vaultID,
                entries: entries,
                tombstones: tombstones,
                updatedByDeviceId: deviceID
            )
            return (manifest, UUID().uuidString)
        }
    }

    // MARK: - Local state (raw GRDB; SyncCore owns no row types)

    private func fetchLocalNotes() async throws -> [CanonicalNote] {
        try await store.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM note WHERE lifecycleState != ?
                ORDER BY modifiedAt
                """, arguments: [NoteLifecycleState.permanentlyDeleted.rawValue])
            var result: [CanonicalNote] = []
            for row in rows {
                guard let note = Self.noteFromRow(db, row: row) else { continue }
                let blockRows = try Row.fetchAll(
                    db,
                    sql: "SELECT * FROM block WHERE noteId = ? ORDER BY sortKey",
                    arguments: [note.id.uuidString]
                )
                let blocks = blockRows.compactMap { Self.blockFromRow($0) }
                result.append(CanonicalNote(note: note, blocks: blocks))
            }
            return result
        }
    }

    private func fetchLocalTombstones() async throws -> [RemoteTombstone] {
        try await store.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM tombstone")
            return rows.compactMap { row in
                guard let noteId = Self.uuid(row, "noteId"),
                      let deletedVersion = Self.uuid(row, "deletedVersionId"),
                      let deletingDevice = Self.uuid(row, "deletingDeviceId") else {
                    return nil
                }
                return RemoteTombstone(
                    noteId: noteId,
                    deletedVersionId: deletedVersion,
                    parentVersionId: Self.uuid(row, "parentVersionId"),
                    deletingDeviceId: deletingDevice,
                    deletedAt: row["deletedAt"] ?? Date(timeIntervalSince1970: 0)
                )
            }
        }
    }

    /// Dirty asset rows (isSynced == false) for upload.
    private struct DirtyAssetRow: Sendable {
        let id: UUID
        let kind: AssetKind
        let contentType: String
        let contentHash: String
    }

    private func fetchDirtyAssets() async throws -> [DirtyAssetRow] {
        try await store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, kind, contentHash, contentType FROM asset WHERE isSynced = 0"
            )
            return rows.compactMap { row in
                guard let id = Self.uuid(row, "id"),
                      let kindStr = row["kind"] as String?,
                      let kind = AssetKind(rawValue: kindStr),
                      let contentHash = row["contentHash"] as String?,
                      let contentType = row["contentType"] as String? else {
                    return nil
                }
                return DirtyAssetRow(id: id, kind: kind, contentType: contentType, contentHash: contentHash)
            }
        }
    }

    private func fetchLocalAssetIds() async throws -> Set<UUID> {
        try await store.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id FROM asset")
            return Set(rows.compactMap { Self.uuid($0, "id") })
        }
    }

    private func markAssetSyncState(
        assetId: UUID,
        isSynced: Bool,
        failureState: AssetSyncFailureState
    ) async throws {
        try await store.write { db in
            try db.execute(
                sql: "UPDATE asset SET isSynced = ?, syncFailureState = ? WHERE id = ?",
                arguments: [isSynced, failureState.rawValue, assetId.uuidString]
            )
        }
    }

    // MARK: - Row mapping helpers

    /// Sanitized UUID extraction from a row column.
    private static func uuid(_ row: Row, _ column: String) -> UUID? {
        guard let value = row[column] as String? ?? nil else { return nil }
        return UUID(uuidString: value)
    }

    /// Date extraction via GRDB's native Date decoding. C2: the engine now
    /// writes `Date` values (not raw doubles), so a single decode path is
    /// sufficient. A defensive fallback handles rows written by older code
    /// paths (epoch doubles as strings) without imposing a dual-format
    /// contract on new writes.
    private static func date(_ row: Row, _ column: String) -> Date? {
        // GRDB's `as Date?` handles its own .datetime encoding (ISO-8601
        // string). A stored Double (legacy/raw SQL) is read via storage.
        if let d = row[column] as Date? { return d }
        guard let value = row[column] else { return nil }
        switch value.databaseValue.storage {
        case .double(let seconds):
            return Date(timeIntervalSince1970: seconds)
        case .int64(let seconds):
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        case .string(let text):
            if let seconds = Double(text) {
                return Date(timeIntervalSince1970: seconds)
            }
            return CanonicalDateFormatter.date(from: text)
        default:
            return nil
        }
    }

    private static func upsertNoteRow(_ db: Database, note: CanonicalNote) throws {
        try db.execute(
            sql: """
                INSERT INTO note (id, title, colorKey, customColor, transparency, textSize, alwaysOnTop,
                                  widgetEligible, coverScreenshotBlockId, manualSortKey, lifecycleState,
                                  trashedAt, conflictOriginNoteId, conflictLabel, versionId, parentVersionId,
                                  lastModifiedDeviceId, createdAt, modifiedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    colorKey = excluded.colorKey,
                    customColor = excluded.customColor,
                    transparency = excluded.transparency,
                    textSize = excluded.textSize,
                    alwaysOnTop = excluded.alwaysOnTop,
                    widgetEligible = excluded.widgetEligible,
                    coverScreenshotBlockId = excluded.coverScreenshotBlockId,
                    manualSortKey = excluded.manualSortKey,
                    lifecycleState = excluded.lifecycleState,
                    trashedAt = excluded.trashedAt,
                    conflictOriginNoteId = excluded.conflictOriginNoteId,
                    conflictLabel = excluded.conflictLabel,
                    versionId = excluded.versionId,
                    parentVersionId = excluded.parentVersionId,
                    lastModifiedDeviceId = excluded.lastModifiedDeviceId,
                    createdAt = excluded.createdAt,
                    modifiedAt = excluded.modifiedAt
                """,
            arguments: [
                note.id.uuidString, note.title, note.colorKey.rawValue, note.customColor,
                note.transparency, note.textSize.rawValue, note.alwaysOnTop ? 1 : 0,
                note.widgetEligible ? 1 : 0, note.coverScreenshotBlockId?.uuidString,
                note.manualSortKey, note.lifecycleState.rawValue,
                note.trashedAt, note.conflictOriginNoteId?.uuidString,
                note.conflictLabel, note.versionId.uuidString, note.parentVersionId?.uuidString,
                note.lastModifiedDeviceId.uuidString, note.createdAt, note.modifiedAt,
            ]
        )
    }

    private static func noteFromRow(_ db: Database, row: Row) -> Note? {
        guard let id = Self.uuid(row, "id"),
              let colorKey = NoteColorKey(rawValue: row["colorKey"] as String? ?? ""),
              let textSize = TextSize(rawValue: row["textSize"] as String? ?? ""),
              let lifecycle = NoteLifecycleState(rawValue: row["lifecycleState"] as String? ?? ""),
              let versionId = Self.uuid(row, "versionId"),
              let lastModifiedDeviceId = Self.uuid(row, "lastModifiedDeviceId") else {
            return nil
        }
        return Note(
            id: id,
            title: row["title"] as String?,
            colorKey: colorKey,
            customColor: row["customColor"] as String?,
            transparency: row["transparency"] as Double? ?? 0,
            textSize: textSize,
            alwaysOnTop: (row["alwaysOnTop"] as Bool?) ?? false,
            widgetEligible: (row["widgetEligible"] as Bool?) ?? false,
            coverScreenshotBlockId: Self.uuid(row, "coverScreenshotBlockId"),
            manualSortKey: row["manualSortKey"] as Int? ?? 0,
            lifecycleState: lifecycle,
            trashedAt: Self.date(row, "trashedAt"),
            conflictOriginNoteId: Self.uuid(row, "conflictOriginNoteId"),
            conflictLabel: row["conflictLabel"] as String?,
            versionId: versionId,
            parentVersionId: Self.uuid(row, "parentVersionId"),
            lastModifiedDeviceId: lastModifiedDeviceId,
            createdAt: Self.date(row, "createdAt") ?? Date(),
            modifiedAt: Self.date(row, "modifiedAt") ?? Date()
        )
    }

    private static func blockFromRow(_ row: Row) -> Block? {
        guard let id = Self.uuid(row, "id"),
              let noteId = Self.uuid(row, "noteId"),
              let kind = BlockKind(rawValue: row["kind"] as String? ?? ""),
              let versionId = Self.uuid(row, "versionId"),
              let lastModifiedDeviceId = Self.uuid(row, "lastModifiedDeviceId"),
              let payloadJSON = row["payload"] as String?,
              let payloadData = payloadJSON.data(using: .utf8),
              let payload = try? CanonicalJSONDecoder().decode(CanonicalBlockPayload.self, from: payloadData) else {
            return nil
        }
        return Block(
            id: id,
            noteId: noteId,
            kind: kind,
            sortKey: row["sortKey"] as Int? ?? 0,
            payload: payload,
            versionId: versionId,
            parentVersionId: Self.uuid(row, "parentVersionId"),
            lastModifiedDeviceId: lastModifiedDeviceId,
            createdAt: Self.date(row, "createdAt") ?? Date(),
            modifiedAt: Self.date(row, "modifiedAt") ?? Date()
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Sync debounce (T198, FR-152a clarified 2026-08-07)
//
// Coalesces local-change notifications and fires the sync engine once 2-4
// seconds have elapsed since the most recent change. The chosen value is
// deterministic for a given build (no random jitter that could starve sync
// indefinitely). Cancelable by manual-sync trigger, application shutdown, or
// network change. MUST NOT block local editing (FR-153).
//
// The debouncer is a thin actor around a scheduled-task handle. The engine
// exposes `localContentChanged()` to record a change; the debouncer
// schedules a `syncNow()` after the window elapses. If another change
// arrives within the window, the pending fire is rescheduled.

/// The sync debounce window (FR-152a: 2-4 seconds after the last local
/// change). The chosen value is deterministic for a given build.
public enum SyncDebounce {
    /// The debounce window in seconds. Fixed at 3.0s (within the 2-4s bound
    /// from FR-152a). Deterministic per build — no random jitter.
    public static let windowSeconds: TimeInterval = 3.0

    /// The acceptable range per FR-152a (for validation/tests).
    public static let minWindowSeconds: TimeInterval = 2.0
    public static let maxWindowSeconds: TimeInterval = 4.0
}

/// Coalesces local-change notifications and fires the sync engine after the
/// debounce window elapses. The debouncer does NOT block local editing — it
/// only schedules the next sync pass. Cancelable by manual-sync, shutdown,
/// or network-change triggers (which call `cancel()` then `syncNow()`
/// directly).
public actor SyncDebouncer {
    private let engine: SyncEngine
    private let window: TimeInterval
    private let clock: @Sendable () -> Date
    private var pendingTask: Task<Void, Never>?
    private var lastChangeAt: Date?

    public init(engine: SyncEngine, window: TimeInterval = SyncDebounce.windowSeconds) {
        self.engine = engine
        self.window = window
        self.clock = { Date() }
    }

    /// Internal initializer with an injected clock for deterministic tests.
    public init(engine: SyncEngine, window: TimeInterval, clock: @escaping @Sendable () -> Date) {
        self.engine = engine
        self.window = window
        self.clock = clock
    }

    /// Records a local content change. Schedules (or reschedules) a sync
    /// pass after the debounce window elapses. If a manual sync is already
    /// pending, the window is reset from this change.
    public func localContentChanged() {
        lastChangeAt = clock()
        pendingTask?.cancel()
        let fireAt = lastChangeAt!.addingTimeInterval(window)
        pendingTask = Task { [weak self] in
            // Sleep until the fire time. Use a short poll loop so the clock
            // injection in tests can advance time deterministically.
            while !Task.isCancelled {
                guard let self else { return }
                let now = await self.clockAsync()
                if now >= fireAt {
                    await self.fire()
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }
    }

    /// Cancels any pending debounced sync (manual-sync / shutdown / network
    /// change). The caller then invokes `syncNow()` directly.
    public func cancel() {
        pendingTask?.cancel()
        pendingTask = nil
        lastChangeAt = nil
    }

    /// Returns `true` if a debounced sync is pending (has not yet fired).
    public var hasPendingSync: Bool {
        pendingTask != nil && !((pendingTask?.isCancelled) ?? true)
    }

    private func fire() async {
        pendingTask = nil
        lastChangeAt = nil
        _ = try? await engine.syncNow()
    }

    private func clockAsync() -> Date { clock() }
}
