import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore

// MARK: - Delete-vs-edit conflict tests (T163l / T122, US10)
//
// Per tasks.md T163l: "delete-vs-edit → recovered conflict copy; not lost,
// not resurrected".

@Suite struct DeleteEditConflictTests {

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

    private func makeEngine(_ provider: LocalProvider, _ vault: Vault, _ store: DatabaseStore,
                            resolver: (any ConflictResolver)? = nil) -> SyncEngine {
        SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID(), conflictResolver: resolver)
    }

    @Test
    func deleteOnOneDeviceEditOnOtherRecoversContentAsConflictCopy() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let storeA = try makeStore()
        let storeB = try makeStore()

        // A creates + syncs; B downloads.
        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        let note = Note(title: "precious", lastModifiedDeviceId: UUID(),
                        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await repoA.create(note)
        _ = try await makeEngine(provider, vault, storeA).syncNow()
        _ = try await makeEngine(provider, vault, storeB).syncNow()

        // A deletes the note (to Trash → permanent).
        let deviceA = UUID()
        try await repoA.trash(id: note.id, deviceId: deviceA)
        try await repoA.permanentlyDelete(id: note.id, deviceId: deviceA)
        _ = try await makeEngine(provider, vault, storeA).syncNow()

        // B edits the note offline (diverges from the deleted lineage).
        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        var b = try await repoB.fetch(id: note.id)!
        b.title = "edited offline on B"
        try await repoB.update(b, modifyingDeviceId: UUID())

        // B syncs: the deletion arrives via the tombstone; the divergent
        // local edit must NOT be lost and MUST NOT be resurrected as the
        // original — it becomes a recovered conflict copy.
        let resolver = SyncConflictResolver(store: storeB)
        let summaryB = try await makeEngine(provider, vault, storeB, resolver: resolver).syncNow()

        // The edited content survives.
        let conflictCopies = try await repoB.fetchAll(lifecycle: .conflictCopy, sort: .modified)
        let editedNote = conflictCopies.first(where: { $0.title == "edited offline on B" })
        #expect(editedNote != nil, "the edited content must survive as a recovered conflict copy")
        #expect(conflictCopies.count >= 1)
        _ = summaryB
    }

    @Test
    func deletedNoteIsNotResurrectedByRetry() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let storeA = try makeStore()
        let storeB = try makeStore()

        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        let note = Note(title: "doomed", lastModifiedDeviceId: UUID())
        try await repoA.create(note)
        _ = try await makeEngine(provider, vault, storeA).syncNow()
        _ = try await makeEngine(provider, vault, storeB).syncNow()

        // A permanently deletes and syncs (tombstone propagates).
        try await repoA.permanentlyDelete(id: note.id, deviceId: UUID())
        _ = try await makeEngine(provider, vault, storeA).syncNow()

        // B syncs twice: the note must be gone (tombstone honored), never
        // resurrected on retry.
        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        _ = try await makeEngine(provider, vault, storeB).syncNow()
        _ = try await makeEngine(provider, vault, storeB).syncNow()

        let fetched = try await repoB.fetch(id: note.id)
        #expect(fetched?.lifecycleState == .permanentlyDeleted || fetched == nil,
                "the deleted note must not be resurrected")
        #expect(try await repoB.fetchAll(lifecycle: .active, sort: .modified).count == 0)
    }
}
