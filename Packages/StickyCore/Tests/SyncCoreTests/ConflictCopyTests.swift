import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore
import AssetStore
@testable import SyncCore

// MARK: - Conflict copy tests (T163k / T121, US10)
//
// Per tasks.md T163k: "SyncCore test: simultaneous edit → conflict copy;
// conflict deduplication (retry does not create unbounded duplicates)".

@Suite struct ConflictCopyTests {

    private func fastVault() async throws -> Vault {
        let bootstrap = try await VaultBootstrapService.createVault(
            password: "test-password", secretStore: InMemorySecretStore()
        )
        let key = try await VaultBootstrapService.openVault(bootstrap, password: "test-password")
        return Vault(vaultId: bootstrap.vaultId, encryptionSuiteVersion: 1, masterKey: key)
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
        resolver: (any ConflictResolver)?
    ) -> SyncEngine {
        SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID(), conflictResolver: resolver)
    }

    private func makeNote(id: UUID = UUID(), title: String) -> Note {
        Note(
            id: id,
            title: title,
            lastModifiedDeviceId: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    /// Two devices edit the same note offline, then sync in sequence.
    /// Returns (storeA, storeB, noteId, conflictStore) — the conflict copy
    /// lives on storeB (the device that received the divergent version).
    private func createDivergence(
        provider: LocalProvider,
        vault: Vault
    ) async throws -> (storeA: DatabaseStore, storeB: DatabaseStore, noteId: UUID) {
        let storeA = try makeStore()
        let storeB = try makeStore()

        // Device A creates + syncs the note.
        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        let note = makeNote(title: "shared")
        try await repoA.create(note)
        _ = try await makeEngine(provider: provider, vault: vault, store: storeA, resolver: nil).syncNow()

        // Device B downloads it.
        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        _ = try await makeEngine(provider: provider, vault: vault, store: storeB, resolver: nil).syncNow()

        // Both devices edit (divergent versions).
        var a = try await repoA.fetch(id: note.id)!
        a.title = "edited on A"
        try await repoA.update(a, modifyingDeviceId: UUID())
        var b = try await repoB.fetch(id: note.id)!
        b.title = "edited on B"
        try await repoB.update(b, modifyingDeviceId: UUID())

        // Device A syncs its edit.
        _ = try await makeEngine(provider: provider, vault: vault, store: storeA, resolver: nil).syncNow()

        return (storeA, storeB, note.id)
    }

    @Test
    func simultaneousEditProducesConflictCopy() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let (_, storeB, noteId) = try await createDivergence(provider: provider, vault: vault)

        // Device B syncs with the conflict resolver installed: its local
        // version stays the original; the remote (A's) version becomes a
        // labeled conflict copy.
        let resolver = SyncConflictResolver(store: storeB)
        _ = try await makeEngine(provider: provider, vault: vault, store: storeB, resolver: resolver).syncNow()

        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        let notes = try await repoB.fetchAll(lifecycle: .conflictCopy, sort: .modified)
        #expect(notes.count == 1, "one labeled conflict copy must exist")
        let conflict = notes.first!
        #expect(conflict.conflictOriginNoteId == noteId, "conflict copy links back to the original")
        #expect(conflict.conflictLabel != nil)
        #expect(conflict.conflictLabel?.hasPrefix("conflict-copy-") == true)

        // The original (local) version is untouched.
        let original = try await repoB.fetch(id: noteId)
        #expect(original?.title == "edited on B")
    }

    @Test
    func retryDoesNotCreateUnboundedDuplicates() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let (_, storeB, _) = try await createDivergence(provider: provider, vault: vault)

        let resolver = SyncConflictResolver(store: storeB)
        let engine = makeEngine(provider: provider, vault: vault, store: storeB, resolver: resolver)

        // First sync creates the conflict copy.
        _ = try await engine.syncNow()
        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        #expect(try await repoB.fetchAll(lifecycle: .conflictCopy, sort: .modified).count == 1)

        // Retry (idempotent): the dedup record keyed by
        // (originalNoteId, localVersionId, remoteVersionId) prevents a
        // second copy.
        _ = try await engine.syncNow()
        _ = try await engine.syncNow()
        #expect(try await repoB.fetchAll(lifecycle: .conflictCopy, sort: .modified).count == 1,
                "retried syncs must not create unbounded duplicates")
    }

    @Test
    func conflictCopySyncsNormallyToRemote() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let (_, storeB, _) = try await createDivergence(provider: provider, vault: vault)

        let resolver = SyncConflictResolver(store: storeB)
        _ = try await makeEngine(provider: provider, vault: vault, store: storeB, resolver: resolver).syncNow()

        // The conflict copy uploads like any other note (it is just a note).
        let before = provider.objectCount()
        let summary = try await makeEngine(provider: provider, vault: vault, store: storeB, resolver: resolver).syncNow()
        #expect(summary.uploadedObjects >= 1, "conflict copy must sync normally")
        #expect(provider.objectCount() > before)
    }
}
