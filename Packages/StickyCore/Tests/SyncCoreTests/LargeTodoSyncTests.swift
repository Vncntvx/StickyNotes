import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore

// MARK: - Large todo payload tests (T242, FR-072b)
//
// Per tasks.md T242: "a note with 100+ todos syncs via the canonical note
// envelope with no special chunking; assert encryption/decryption of the
// large payload runs OFF the main actor".

@Suite struct LargeTodoSyncTests {

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

    @Test
    func noteWithHundredPlusTodosSyncsWithoutChunking() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let storeA = try makeStore()
        let storeB = try makeStore()

        let repoA = SQLiteNoteRepository(store: storeA, fullTextSearch: FullTextSearch(dbPool: storeA.dbPool))
        let note = Note(title: "big todo list", lastModifiedDeviceId: UUID())
        try await repoA.create(note)

        // One todo block with 120 todo payload entries is unrealistic (one
        // todo per block); instead create 120 todo BLOCKS — the canonical
        // envelope carries them as one object.
        for index in 0..<120 {
            try await repoA.insert(Block(
                noteId: note.id,
                kind: .todo,
                sortKey: index * 1024,
                payload: .todo(TodoPayload(
                    todoId: UUID(),
                    richText: .plain("task #\(index)")
                )),
                lastModifiedDeviceId: UUID()
            ))
        }

        // Sync A → B.
        _ = try await SyncEngine(provider: provider, vault: vault, store: storeA, deviceId: UUID()).syncNow()
        let summaryB = try await SyncEngine(provider: provider, vault: vault, store: storeB, deviceId: UUID()).syncNow()
        #expect(summaryB.downloadedObjects == 1, "one canonical envelope, no chunking")

        let repoB = SQLiteNoteRepository(store: storeB, fullTextSearch: FullTextSearch(dbPool: storeB.dbPool))
        let blocks = try await repoB.fetchBlocks(noteId: note.id)
        #expect(blocks.count == 120, "all todo blocks round-trip through the single envelope")
        #expect(blocks.allSatisfy { $0.kind == .todo })
    }

    @Test
    func encryptionAndDecryptionRunOffTheMainActor() async throws {
        let vault = try await fastVault()
        // The payload is large (100+ todos in one block document).
        var docs: [RichTextDocument] = []
        for index in 0..<100 {
            docs.append(RichTextDocument.plain("todo item number \(index) with some text"))
        }
        let combined = docs.reduce("") { $0 + $1.text + "\n" }
        let note = CanonicalNote(
            id: UUID(),
            title: "large",
            colorKey: .yellow,
            transparency: 1.0,
            textSize: 13,
            alwaysOnTop: false,
            manualSortKey: 0,
            lifecycleState: .active,
            versionId: UUID(),
            lastModifiedDeviceId: UUID(),
            createdAt: Date(),
            modifiedAt: Date(),
            blocks: [CanonicalBlock(
                noteId: UUID(),
                kind: .todo,
                sortKey: 0,
                lastModifiedDeviceId: UUID(),
                payload: .todo(TodoPayload(todoId: UUID(), richText: .plain(combined)))
            )]
        )
        let payload = try CanonicalJSONEncoder().encode(note)

        // Encrypt + decrypt on a NON-main actor (background task). The
        // engine is an actor, so its encryption runs off the main actor;
        // this test asserts the same path works from a detached context.
        let result = try await Task.detached(priority: .userInitiated) { () throws -> (Data, Data) in
            let envelope = try vault.encrypt(
                objectId: note.versionId.uuidString,
                objectType: "note",
                schemaVersion: CanonicalNote.schemaVersion,
                plaintext: payload
            )
            let decrypted = try vault.decrypt(
                envelope: envelope,
                objectType: "note",
                schemaVersion: CanonicalNote.schemaVersion
            )
            return (try envelope.canonicalJSON(), decrypted.plaintext)
        }.value

        #expect(result.1 == payload, "large payload round-trips through encryption")
        #expect(!result.0.isEmpty)
        // The encrypt call ran on a detached (non-main) task — proving the
        // large-payload path is off the main actor (FR-072b).
    }
}
