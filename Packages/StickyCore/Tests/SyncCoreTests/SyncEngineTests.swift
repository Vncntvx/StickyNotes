import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore
import AssetStore

// MARK: - Sync engine tests (T108)
//
// Per tasks.md T108: initial upload/download, incremental update, partial
// asset upload, interrupted manifest commit, repeated retry, wrong password,
// remote corruption, network loss/restoration.

@Suite struct SyncEngineTests {

    /// Fast KDF parameters for tests (production uses m=64MiB; M0 validated).
    private func fastVault() async throws -> (bootstrap: VaultBootstrap, vault: Vault) {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "test-password", secretStore: InMemorySecretStore()
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "test-password")
        return (bootstrap, Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key))
    }

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    private func makeEngine(
        provider: LocalProvider,
        vault: Vault,
        store: DatabaseStore,
        conflictResolver: (any ConflictResolver)? = nil
    ) -> SyncEngine {
        SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID(), conflictResolver: conflictResolver)
    }

    private func makeEngineWithAssets(
        provider: LocalProvider,
        vault: Vault,
        store: DatabaseStore,
        assetStore: AssetStore
    ) -> SyncEngine {
        SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID(), assetStore: assetStore)
    }

    /// Inserts an asset row (isSynced = false) + imports its bytes into the
    /// AssetStore so the engine can read them for upload. The DB row's id
    /// MUST match the AssetStore's record id — the engine reads bytes by
    /// the id it finds in the asset table.
    private func registerAsset(
        _ store: DatabaseStore,
        assetStore: AssetStore,
        kind: AssetKind = .original,
        contentType: String = "image/png",
        bytes: Data = Data(repeating: 0x89, count: 64)
    ) async throws -> UUID {
        let stored = try await assetStore.importData(bytes, kind: kind, contentType: contentType)
        try await store.write { db in
            try db.execute(
                sql: """
                    INSERT INTO asset (id, kind, contentHash, byteSize, contentType, storagePath,
                                       isSynced, syncFailureState, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, 0, 'none', ?)
                    """,
                arguments: [
                    stored.id.uuidString, kind.rawValue, stored.contentHash, bytes.count, contentType,
                    stored.filename, Date()
                ]
            )
        }
        return stored.id
    }

    private func makeNote(id: UUID = UUID(), title: String, lifecycle: NoteLifecycleState = .active) -> Note {
        Note(
            id: id,
            title: title,
            colorKey: .yellow,
            transparency: 0,
            textSize: 13,
            alwaysOnTop: false,
            manualSortKey: 0,
            lifecycleState: lifecycle,
            versionId: UUID(),
            lastModifiedDeviceId: UUID(),
            createdAt: Date(),
            modifiedAt: Date()
        )
    }

    // MARK: - Initial upload

    @Test
    func firstSyncUploadsAllLocalNotes() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()

        // Two local notes (created via the repository to keep rows valid).
        let noteA = makeNote(title: "note A")
        let noteB = makeNote(title: "note B")
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(noteA)
        try await repo.create(noteB)

        let engine = makeEngine(provider: provider, vault: vault, store: store)
        let summary = try await engine.syncNow()

        #expect(summary.uploadedObjects == 2)
        #expect(summary.manifestCommitted)
        #expect(summary.initializedRemote)
        #expect(provider.objectCount() == 2, "two note objects on the remote")
        #expect(provider.manifestCount() == 1)
    }

    // MARK: - Idempotent re-sync

    @Test
    func resyncWithNoChangesCommitsNothing() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(makeNote(title: "only note"))

        let engine = makeEngine(provider: provider, vault: vault, store: store)
        let first = try await engine.syncNow()
        #expect(first.uploadedObjects == 1)

        let second = try await engine.syncNow()
        #expect(second.uploadedObjects == 0, "no dirty notes after first sync")
        #expect(second.downloadedObjects == 0)
    }

    // MARK: - Incremental update (download)

    @Test
    func secondDeviceDownloadsRemoteNotes() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let storeA = try makeStore()
        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        try await repoA.create(makeNote(title: "shared note"))

        // Device A uploads.
        _ = try await makeEngine(provider: provider, vault: vault, store: storeA).syncNow()

        // Device B (empty) downloads.
        let storeB = try makeStore()
        let summaryB = try await makeEngine(provider: provider, vault: vault, store: storeB).syncNow()
        #expect(summaryB.downloadedObjects == 1)

        let notesB = try await SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
            .fetchAll(lifecycle: .active, sort: .modified)
        #expect(notesB.count == 1)
        #expect(notesB.first?.title == "shared note")
    }

    // MARK: - Network loss / restoration

    @Test
    func transientNetworkFailureThenRestoration() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(makeNote(title: "survives"))

        let engine = makeEngine(provider: provider, vault: vault, store: store)

        // First attempt: transient network failure mid-sync.
        provider.inject(.network)
        do {
            _ = try await engine.syncNow()
            Issue.record("network failure must surface")
        } catch ProviderError.network {
            #expect(true)
        }

        // Nothing was committed remotely (fail safe on transient errors).
        #expect(provider.objectCount() == 0)

        // Restoration: the next attempt succeeds (idempotent retry).
        let summary = try await engine.syncNow()
        #expect(summary.uploadedObjects == 1)
    }

    // MARK: - Interrupted manifest commit + retry

    @Test
    func manifestContentionRetriesAndCommits() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(makeNote(title: "contended"))

        // First sync writes the initial manifest.
        _ = try await makeEngine(provider: provider, vault: vault, store: store).syncNow()

        // Second sync: another device commits first (conditionalFailed once),
        // then ours retries and succeeds.
        let store2 = try makeStore()
        let repo2 = SQLiteNoteRepository(store: store2, fullTextSearch: FullTextSearch(dbPool: store2.dbPool))
        try await repo2.create(makeNote(title: "from device two"))
        provider.simulateManifestContentionOnce = true

        let summary = try await makeEngine(provider: provider, vault: vault, store: store2).syncNow()
        #expect(summary.uploadedObjects == 1)
        #expect(summary.manifestCommitted, "contended commit must retry and succeed (bounded)")
    }

    // MARK: - Remote corruption fails closed

    @Test
    func corruptRemoteObjectIsSkippedNotApplied() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let storeA = try makeStore()
        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        try await repoA.create(makeNote(title: "clean note"))
        _ = try await makeEngine(provider: provider, vault: vault, store: storeA).syncNow()

        // Corrupt the remote note object bytes (simulate provider-side
        // tampering / disk corruption).
        var snapshot = provider.snapshot()
        let objectName = snapshot.keys.first!
        snapshot[objectName] = Data("garbage that is not an envelope".utf8)
        provider.overwriteSnapshot(snapshot)

        // Device B must NOT apply the corrupt object (fail closed).
        let storeB = try makeStore()
        let summary = try await makeEngine(provider: provider, vault: vault, store: storeB).syncNow()
        #expect(summary.skippedCorruptObjects == 1)
        #expect(summary.downloadedObjects == 0)
        let notesB = try await SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
            .fetchAll(lifecycle: .active, sort: .modified)
        #expect(notesB.isEmpty, "corrupt remote objects must never be applied")
    }

    // MARK: - Wrong password fails before any mutation

    @Test
    func wrongPasswordFailsBeforeSyncMutatesAnything() async throws {
        let provider = LocalProvider()
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(makeNote(title: "local only"))

        // Wrong vault key: decrypting the (absent) manifest would not fail
        // per se — simulate a corrupt manifest envelope that cannot decrypt.
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "pw-a", secretStore: InMemorySecretStore()
        )
        let keyA = try await VaultBootstrapService.openVault(bootstrap, password: "pw-a")
        let engineA = makeEngine(provider: provider, vault: Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: keyA), store: store)
        _ = try await engineA.syncNow()  // device A creates the remote manifest

        // Device B opens with a DIFFERENT vault (wrong vault id) — manifest
        // decryption fails closed and nothing local changes.
        let bootstrapB = try await VaultBootstrapService.createVault(
            password: "pw-b", secretStore: InMemorySecretStore()
        )
        let keyB = try await VaultBootstrapService.openVault(bootstrapB, password: "pw-b")
        let storeB = try makeStore()
        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        try await repoB.create(makeNote(title: "B local"))

        let engineB = makeEngine(provider: provider, vault: Vault(vaultId: bootstrapB.vaultId, encryptionSuiteVersion: 1, masterKey: keyB), store: storeB)
        do {
            _ = try await engineB.syncNow()
            Issue.record("wrong vault must fail closed on manifest authentication")
        } catch {
            // Fail closed — the local note stays untouched and no remote
            // mutation happened.
            let notes = try await repoB.fetchAll(lifecycle: .active, sort: .modified)
            #expect(notes.count == 1)
            #expect(notes.first?.title == "B local")
        }
    }

    // MARK: - Date round-trip (C2: unified Date storage)
    //
    // Verifies that a note synced from device A and read back via the
    // NoteRepository on device B preserves createdAt/modifiedAt to
    // sub-second precision. This pins the C2 fix: the SyncEngine now writes
    // `Date` values (GRDB's native .datetime encoding) instead of raw
    // `timeIntervalSince1970` doubles, eliminating the dual-format storage
    // that previously broke date round-trips silently.

    @Test
    func syncedNoteDatesRoundTripThroughRepository() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let storeA = try makeStore()

        // A note with known, non-trivial dates.
        let knownCreated = Date(timeIntervalSince1970: 1_700_000_000)
        let knownModified = Date(timeIntervalSince1970: 1_700_000_123)
        let note = Note(
            id: UUID(), title: "dated", colorKey: .yellow, transparency: 0, textSize: 13,
            alwaysOnTop: false, manualSortKey: 0, lifecycleState: .active,
            versionId: UUID(), lastModifiedDeviceId: UUID(),
            createdAt: knownCreated, modifiedAt: knownModified
        )
        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        try await repoA.create(note)

        // Device A uploads.
        _ = try await makeEngine(provider: provider, vault: vault, store: storeA).syncNow()

        // Device B downloads and reads via the repository.
        let storeB = try makeStore()
        _ = try await makeEngine(provider: provider, vault: vault, store: storeB).syncNow()
        let notesB = try await SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
            .fetchAll(lifecycle: .active, sort: .modified)

        #expect(notesB.count == 1)
        let fetched = try #require(notesB.first)
        #expect(abs(fetched.createdAt.timeIntervalSince(knownCreated)) < 1.0,
                "createdAt must round-trip; got \(fetched.createdAt) vs \(knownCreated)")
        #expect(abs(fetched.modifiedAt.timeIntervalSince(knownModified)) < 1.0,
                "modifiedAt must round-trip; got \(fetched.modifiedAt) vs \(knownModified)")
    }

    // MARK: - Asset sync (T108: partial asset upload)
    //
    // Covers: initial asset upload, partial-failure retry via
    // syncFailureState, asset download on a second device, and fail-closed
    // on a corrupt asset object.

    @Test
    func dirtyAssetIsUploadedAndMarkedSynced() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let assetDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: assetDir) }
        let assetStore = try AssetStore(directoryURL: assetDir)

        let assetId = try await registerAsset(store, assetStore: assetStore)

        let engine = makeEngineWithAssets(provider: provider, vault: vault, store: store, assetStore: assetStore)
        let summary = try await engine.syncNow()

        // 1 asset uploaded + the manifest committed.
        #expect(summary.uploadedObjects == 1, "the dirty asset must be uploaded")
        #expect(summary.manifestCommitted)

        // The asset row is now marked synced.
        let isSynced: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT isSynced FROM asset WHERE id = ?",
                             arguments: [assetId.uuidString]) ?? -1
        }
        #expect(isSynced == 1, "asset must be marked isSynced after upload")

        // Re-syncing is a no-op (no dirty assets).
        let secondSummary = try await engine.syncNow()
        #expect(secondSummary.uploadedObjects == 0)
    }

    @Test
    func partialAssetUploadRetriedAfterTransientFailure() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let assetDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-partial-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: assetDir) }
        let assetStore = try AssetStore(directoryURL: assetDir)

        // Establish the manifest with a clean first sync (a note so the
        // manifest is non-empty). The failure must happen during the ASSET
        // upload, not the manifest fetch — otherwise the asset step is
        // never reached.
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(makeNote(title: "establishes manifest"))
        let engine = makeEngineWithAssets(provider: provider, vault: vault, store: store, assetStore: assetStore)
        _ = try await engine.syncNow()  // clean first sync

        // Now add a dirty asset.
        let assetId = try await registerAsset(store, assetStore: assetStore)

        // Inject a transient network failure SPECIFIC to the next upload
        // call (the manifest fetch must succeed so the asset upload step is
        // reached). A global inject would be consumed by fetchManifest.
        provider.failNextUpload(with: .network)

        // The sync pass does NOT throw: a transient ASSET upload failure is
        // a partial failure (the note sync already succeeded); the asset is
        // marked .uploadFailed and retried on the next pass. This is the
        // partial-asset-sync-failure design (data-model.md §Asset).
        let failedSummary = try await engine.syncNow()
        #expect(failedSummary.uploadedObjects == 0,
                "the asset must not be counted as uploaded when the upload failed")

        // The asset is marked .uploadFailed (partial-asset-sync-failure),
        // NOT synced — ready for retry.
        let failureState: String = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT syncFailureState FROM asset WHERE id = ?",
                                arguments: [assetId.uuidString]) ?? ""
        }
        #expect(failureState == "uploadFailed",
                "asset must be marked uploadFailed after a transient failure; got \(failureState)")

        // Restoration: the next attempt succeeds (idempotent retry).
        let summary = try await engine.syncNow()
        #expect(summary.uploadedObjects == 1, "the asset must upload on retry")

        let isSynced: Int = try await store.read { db in
            try Int.fetchOne(db, sql: "SELECT isSynced FROM asset WHERE id = ?",
                             arguments: [assetId.uuidString]) ?? -1
        }
        #expect(isSynced == 1, "asset must be marked synced after the retry succeeds")
        let clearedState: String = try await store.read { db in
            try String.fetchOne(db, sql: "SELECT syncFailureState FROM asset WHERE id = ?",
                                arguments: [assetId.uuidString]) ?? ""
        }
        #expect(clearedState == "none", "failure state must clear on success")
    }

    @Test
    func secondDeviceDownloadsRemoteAsset() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()

        // Device A: a note + an asset.
        let storeA = try makeStore()
        let assetDirA = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-dl-a-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: assetDirA) }
        let assetStoreA = try AssetStore(directoryURL: assetDirA)
        let assetId = try await registerAsset(storeA, assetStore: assetStoreA,
                                              bytes: Data(repeating: 0xAB, count: 128))

        _ = try await makeEngineWithAssets(provider: provider, vault: vault, store: storeA, assetStore: assetStoreA).syncNow()

        // Device B: empty store + a fresh AssetStore. It downloads the asset.
        let storeB = try makeStore()
        let assetDirB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-dl-b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: assetDirB) }
        let assetStoreB = try AssetStore(directoryURL: assetDirB)

        let summaryB = try await makeEngineWithAssets(provider: provider, vault: vault, store: storeB, assetStore: assetStoreB).syncNow()
        #expect(summaryB.downloadedObjects == 1, "device B must download the remote asset")

        // The asset row exists on B, marked synced, with the same contentHash.
        let hash: String = try await storeB.read { db in
            try String.fetchOne(db, sql: "SELECT contentHash FROM asset WHERE id = ?",
                                arguments: [assetId.uuidString]) ?? ""
        }
        let isSyncedB: Int = try await storeB.read { db in
            try Int.fetchOne(db, sql: "SELECT isSynced FROM asset WHERE id = ?",
                             arguments: [assetId.uuidString]) ?? -1
        }
        #expect(isSyncedB == 1)
        #expect(!hash.isEmpty)

        // The bytes round-trip: B can read the downloaded asset's bytes.
        let bytesB = try await assetStoreB.readData(assetID: assetId)
        #expect(bytesB == Data(repeating: 0xAB, count: 128), "downloaded asset bytes must match the original")
    }

    @Test
    func corruptRemoteAssetIsSkippedNotApplied() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()

        // Device A uploads a clean asset.
        let storeA = try makeStore()
        let assetDirA = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-corrupt-a-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: assetDirA) }
        let assetStoreA = try AssetStore(directoryURL: assetDirA)
        _ = try await registerAsset(storeA, assetStore: assetStoreA)
        _ = try await makeEngineWithAssets(provider: provider, vault: vault, store: storeA, assetStore: assetStoreA).syncNow()

        // Corrupt the remote asset object bytes (simulate provider-side tampering).
        var snapshot = provider.snapshot()
        // The manifest object is "manifest"; every other object is an asset.
        let assetObjectName = snapshot.keys.first { $0 != "manifest" && !$0.isEmpty }
        try #require(assetObjectName != nil, "there must be a remote asset object")
        snapshot[assetObjectName!] = Data("garbage not an envelope".utf8)
        provider.overwriteSnapshot(snapshot)

        // Device B must NOT apply the corrupt asset (fail closed).
        let storeB = try makeStore()
        let assetDirB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("asset-corrupt-b-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: assetDirB) }
        let assetStoreB = try AssetStore(directoryURL: assetDirB)
        let summaryB = try await makeEngineWithAssets(provider: provider, vault: vault, store: storeB, assetStore: assetStoreB).syncNow()
        #expect(summaryB.skippedCorruptObjects == 1, "corrupt remote asset must be skipped")
        #expect(summaryB.downloadedObjects == 0)

        let assetCount: Int = try await storeB.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset") ?? 0
        }
        #expect(assetCount == 0, "corrupt asset must never be registered locally")
    }

    // MARK: - R3.6 contentHash contract (remediation roadmap 2026-08-14)

    /// RemoteManifest spec: entry contentHash is 64-char SHA-256 hex. The
    /// audit's convergence pass found SyncEngine's private helper hex-
    /// encoded the raw BYTES instead (2×N chars — self-consistent locally
    /// but contract-violating and ~40× the size for image payloads).
    @Test
    func remoteEntryContentHashIsSHA256Hex() async throws {
        let (_, vault) = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        try await repo.create(makeNote(title: "hash contract"))
        _ = try await makeEngine(provider: provider, vault: vault, store: store).syncNow()

        // Decrypt the remote manifest and inspect the note entry's hash.
        let wire = try await provider.fetch(objectName: ManifestStore.manifestObjectName)
        let envelope = try EncryptedEnvelope.fromCanonicalJSON(wire)
        let decrypted = try vault.decrypt(
            envelope: envelope, objectType: "manifest", schemaVersion: RemoteManifest.schemaVersion
        )
        let manifest = try CanonicalJSONDecoder().decode(RemoteManifest.self, from: decrypted.plaintext)
        let entry = try #require(manifest.entries.first, "the note must produce a remote entry")
        #expect(entry.contentHash.count == 64,
                "contentHash must be 64-char SHA-256 hex per RemoteManifest spec (got \(entry.contentHash.count) chars)")
    }
}
