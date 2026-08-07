import Testing
import Foundation
import Domain
import Persistence
import SecurityCore
import SyncCore

// MARK: - Sort-key last-writer-wins tests (T223, FR-022b)
//
// Per tasks.md T223: "(a) two devices reorder the same notes differently
// with NO content change → sync applies the most recently written sort key
// per note (deterministic via version timestamp/sequence), NO conflict copy
// is created; (b) crossed reorder resolves deterministically per-note by
// version recency; (c) sort-key divergence combined with real content
// divergence → a content conflict copy IS still created; (d) assert content
// fields are the ONLY divergence trigger".

@Suite struct SortKeyLastWriterWinsTests {

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

    private func canonicalNote(title: String, sortKey: Int, modifiedAt: Date, versionId: UUID = UUID()) -> CanonicalNote {
        CanonicalNote(
            id: UUID(),
            title: title,
            colorKey: .yellow,
            customColor: nil,
            transparency: 1.0,
            textSize: 13,
            alwaysOnTop: false,
            widgetEligible: true,
            coverScreenshotBlockId: nil,
            manualSortKey: sortKey,
            lifecycleState: .active,
            trashedAt: nil,
            conflictOriginNoteId: nil,
            conflictLabel: nil,
            versionId: versionId,
            parentVersionId: nil,
            lastModifiedDeviceId: UUID(),
            createdAt: modifiedAt,
            modifiedAt: modifiedAt,
            blocks: []
        )
    }

    // MARK: - Classifier

    @Test
    func differsOnlyBySortKeyDetectsSortKeyOnlyDivergence() {
        let base = canonicalNote(title: "same", sortKey: 1024, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var reordered = base
        reordered.manualSortKey = 2048
        reordered.versionId = UUID()

        #expect(ContentDivergence.differsOnlyBySortKey(base, reordered))
        #expect(ContentDivergence.contentFieldsAreEqual(base, reordered))

        // Content divergence (title) is NOT sort-key-only.
        var changed = reordered
        changed.title = "different"
        #expect(!ContentDivergence.differsOnlyBySortKey(base, changed))
    }

    @Test
    func lastWriterWinsByVersionRecency() {
        let older = canonicalNote(title: "n", sortKey: 1024, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var newer = older
        newer.manualSortKey = 3072
        newer.modifiedAt = Date(timeIntervalSince1970: 1_700_100_000)

        #expect(ContentDivergence.lastWriterWinsSortKey(local: older, remote: newer) == 3072,
                "the newer version's sort key wins")
        #expect(ContentDivergence.lastWriterWinsSortKey(local: newer, remote: older) == 3072)
    }

    @Test
    func crossedReorderResolvesDeterministicallyPerNote() {
        // A moves X above Y; B moves Y above X — resolved per-note by
        // version recency, no global arbitration.
        let xLocal = canonicalNote(title: "X", sortKey: 0, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let xRemote = canonicalNote(title: "X", sortKey: 2048, modifiedAt: Date(timeIntervalSince1970: 1_700_100_000))
        #expect(ContentDivergence.lastWriterWinsSortKey(local: xLocal, remote: xRemote) == 2048)

        let yLocal = canonicalNote(title: "Y", sortKey: 1024, modifiedAt: Date(timeIntervalSince1970: 1_700_100_000))
        let yRemote = canonicalNote(title: "Y", sortKey: 0, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(ContentDivergence.lastWriterWinsSortKey(local: yLocal, remote: yRemote) == 1024)
    }

    @Test
    func contentFieldsAreTheOnlyDivergenceTrigger() {
        // Every content field participates in the comparison.
        var a = canonicalNote(title: "t", sortKey: 0, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        var b = a
        b.title = "t2"
        b.manualSortKey = 5
        #expect(!ContentDivergence.differsOnlyBySortKey(a, b), "title difference must trigger content divergence")

        a = canonicalNote(title: "t", sortKey: 0, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        b = a
        b.textSize = 18
        b.manualSortKey = 5
        #expect(!ContentDivergence.differsOnlyBySortKey(a, b), "textSize difference must trigger content divergence")
    }

    // MARK: - Resolver integration

    @Test
    func sortKeyOnlyDivergenceCreatesNoConflictCopy() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "stable", lastModifiedDeviceId: UUID())
        try await repo.create(note)
        var updated = try await repo.fetch(id: note.id)!
        updated.manualSortKey = 4096
        try await repo.update(updated, modifyingDeviceId: UUID())

        // Remote version: same content, different (newer) sort key.
        let local = try await repo.fetch(id: note.id)!
        var remote = CanonicalNote(note: local, blocks: [])
        remote.manualSortKey = 8192
        remote.modifiedAt = Date().addingTimeInterval(3600)
        remote.versionId = UUID()

        let resolver = SyncConflictResolver(store: store)
        let outcome = try await resolver.resolveDivergence(
            local: remote,   // remote is newer — still no conflict
            remote: CanonicalNote(note: local, blocks: []),
            deviceId: UUID()
        )
        // With only the sort key differing, NO conflict copy is created.
        let conflicts = try await repo.fetchAll(lifecycle: .conflictCopy, sort: .modified)
        #expect(conflicts.isEmpty, "sort-key-only divergence must never create a conflict copy (FR-022b)")
        #expect(outcome == .notAContentConflict)
    }

    @Test
    func contentDivergenceStillCreatesConflictCopy() async throws {
        let vault = try await fastVault()
        let provider = LocalProvider()
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        let note = Note(title: "original", lastModifiedDeviceId: UUID())
        try await repo.create(note)
        _ = try await SyncEngine(provider: provider, vault: vault, store: store, deviceId: UUID()).syncNow()

        // Edit + reorder locally (content divergence + sort-key divergence).
        var edited = try await repo.fetch(id: note.id)!
        edited.title = "edited content"
        edited.manualSortKey = 2048
        try await repo.update(edited, modifyingDeviceId: UUID())

        // Simulate a remote version with different content (older lineage).
        var remote = CanonicalNote(note: edited, blocks: [])
        remote.title = "remote content"
        remote.manualSortKey = 1024
        remote.versionId = UUID()
        remote.parentVersionId = edited.parentVersionId

        let resolver = SyncConflictResolver(store: store)
        let created = try await resolver.resolveDivergence(local: CanonicalNote(note: edited, blocks: []),
                                                           remote: remote,
                                                           deviceId: UUID())
        #expect(created == .created, "content divergence MUST create a conflict copy")
        #expect(try await repo.fetchAll(lifecycle: .conflictCopy, sort: .modified).count == 1)
    }
}
