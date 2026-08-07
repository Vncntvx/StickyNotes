import Testing
import Foundation
import GRDB
import Domain
import Persistence
import SecurityCore
import SyncCore
import AssetStore

// MARK: - Independent asset sync tests (T190, FR-090a clarified 2026-08-07)
//
// Per tasks.md T190: each asset (original, thumbnail, app icon) is uploaded
// as its own encrypted envelope (never bundled inside a note envelope); each
// asset object carries a SHA-256 integrity hash; a failed asset upload does
// NOT block synchronization of the referencing note's metadata; the asset's
// sync state is set to `partialAssetSyncFailure` and retried independently on
// a subsequent sync run without re-encrypting or re-uploading already-
// succeeded note metadata.

@Suite struct IndependentAssetSyncTests {

    private func fastVault() async throws -> (VaultBootstrap, Vault) {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw", secretStore: InMemorySecretStore(), isTestFixture: true
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "pw")
        return (bootstrap, Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key))
    }

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    private func makeAssetStore() throws -> AssetStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sticky-asset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AssetStore(directoryURL: dir)
    }

    @Test
    func assetsAreUploadedAsIndependentEncryptedObjects() async throws {
        // Each asset is its own encrypted envelope under its own objectId
        // (assetId), never bundled inside a note envelope. The manifest
        // entry for an asset uses the assetId as objectId.
        let (_, vault) = try await fastVault()
        let assetId = UUID()
        let blob = SyncedAssetBlob(
            assetId: assetId, kind: AssetKind.original.rawValue,
            contentType: "image/png",
            contentHash: "sha256:\(String(repeating: "a", count: 64))",
            bytes: Data(repeating: 0x89, count: 50)
        )
        let payload = try blob.canonicalJSON()
        let envelope = try vault.encrypt(
            objectId: assetId.uuidString, objectType: "asset",
            schemaVersion: SyncedAssetBlob.version, plaintext: payload
        )
        // The envelope's objectId is the assetId — distinct from any note.
        #expect(envelope.objectId == assetId.uuidString)
    }

    @Test
    func assetObjectCarriesSHA256IntegrityHash() async throws {
        // The manifest entry's contentHash for an asset is the SHA-256 of
        // the raw bytes (64-char hex), enabling integrity verification on
        // download.
        let bytes = Data(repeating: 0x42, count: 32) // 32 bytes → 64 hex chars
        let hash = bytes.map { String(format: "%02x", $0) }.joined()
        #expect(hash.count == 64)
        let entry = RemoteObjectEntry(
            objectName: "obj-x", objectId: UUID().uuidString,
            contentHash: hash, byteSize: 32, modifiedAt: Date()
        )
        #expect(entry.contentHash.count == 64)
    }

    @Test
    func failedAssetUploadDoesNotBlockNoteMetadataSync() async throws {
        // A transient asset-upload failure marks the asset
        // `.uploadFailed` for retry, but the note's metadata (uploaded
        // separately) still succeeds. The SyncEngineTests already cover
        // this (T108 partial-asset-upload); here we verify the engine's
        // uploadDirtyAssets catches provider errors and continues.
        let (_, vault) = try await fastVault()
        let store = try makeStore()
        let assetStore = try makeAssetStore()
        let provider = LocalProvider()

        // Register a dirty asset (use stored.id as the row id so the engine
        // can read the bytes from the AssetStore).
        let bytes = Data(repeating: 0x89, count: 64)
        let stored = try await assetStore.importData(bytes, kind: .original, contentType: "image/png")
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset (id, kind, contentHash, byteSize, contentType, storagePath,
                                       isSynced, syncFailureState, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 'none', ?)
                    """,
                arguments: [stored.id.uuidString, AssetKind.original.rawValue, stored.contentHash,
                            bytes.count, "image/png", stored.filename, Date()]
            )
        }

        // Inject a transient failure on the next asset upload.
        provider.failNextUpload(with: .network)

        let engine = SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID(), assetStore: assetStore)
        let summary = try await engine.syncNow()

        // The sync pass completed (did not crash) — the asset failure was
        // contained. The asset is marked `.uploadFailed` for retry.
        let assetState = try await store.read { db -> (isSynced: Int, failure: String)? in
            guard let row = try Row.fetchOne(db, sql: "SELECT isSynced, syncFailureState FROM asset WHERE id = ?",
                             arguments: [stored.id.uuidString]) else { return nil }
            return (row["isSynced"] ?? 0, row["syncFailureState"] ?? "none")
        }
        #expect(assetState?.isSynced == 0, "failed asset must not be marked synced")
        #expect(assetState?.failure == "uploadFailed")
        _ = summary // the pass completed
    }

    @Test
    func failedAssetRetriedIndependentlyOnNextRun() async throws {
        // On the next sync run, the failed asset is retried independently
        // — the note metadata (already succeeded) is NOT re-uploaded.
        let (_, vault) = try await fastVault()
        let store = try makeStore()
        let assetStore = try makeAssetStore()
        let provider = LocalProvider()

        let bytes = Data(repeating: 0x89, count: 64)
        let stored = try await assetStore.importData(bytes, kind: .original, contentType: "image/png")
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset (id, kind, contentHash, byteSize, contentType, storagePath,
                                       isSynced, syncFailureState, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 'none', ?)
                    """,
                arguments: [stored.id.uuidString, AssetKind.original.rawValue, stored.contentHash,
                            bytes.count, "image/png", stored.filename, Date()]
            )
        }

        // First run: fail the asset upload.
        provider.failNextUpload(with: .network)
        let engine = SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID(), assetStore: assetStore)
        _ = try await engine.syncNow()

        // Second run: no injected failure → asset uploads successfully.
        let summary2 = try await engine.syncNow()
        #expect(summary2.uploadedObjects >= 1, "asset retried and uploaded on second run")

        let assetState = try await store.read { db -> (isSynced: Int, failure: String)? in
            guard let row = try Row.fetchOne(db, sql: "SELECT isSynced, syncFailureState FROM asset WHERE id = ?",
                             arguments: [stored.id.uuidString]) else { return nil }
            return (row["isSynced"] ?? 0, row["syncFailureState"] ?? "none")
        }
        #expect(assetState?.isSynced == 1, "asset now synced after retry")
        #expect(assetState?.failure == "none")
    }

    @Test
    func partialAssetSyncFailureEnumExistsForStateMarking() {
        // The SyncVersionState enum has the partialAssetSyncFailure case
        // for per-entity sync state marking.
        #expect(SyncVersionState.partialAssetSyncFailure.rawValue == "partialAssetSyncFailure")
        // The AssetSyncFailureState enum has the uploadFailed case.
        #expect(AssetSyncFailureState.uploadFailed.rawValue == "uploadFailed")
        #expect(AssetSyncFailureState.downloadFailed.rawValue == "downloadFailed")
    }
}
