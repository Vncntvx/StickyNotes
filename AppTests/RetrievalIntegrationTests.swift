import Testing
import Foundation
import Domain
import Persistence
import SystemBridge
@testable import StickyNotes

// MARK: - Retrieval integration tests (T163b / T041, US2)
//
// Per tasks.md T163b: sort switch (modified/created/title/manual) + manual
// reorder persists.

@MainActor
@Suite struct RetrievalIntegrationTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(
                defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
            )
        )
    }

    @Test
    func sortSwitchOrdersCards() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        let repo = env.persistence.noteRepository!

        // Two notes with known timestamps.
        let old = Note(title: "Old", lastModifiedDeviceId: Self.deviceId,
                       createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                       modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let fresh = Note(title: "Fresh", lastModifiedDeviceId: Self.deviceId,
                         createdAt: Date(timeIntervalSince1970: 1_700_100_000),
                         modifiedAt: Date(timeIntervalSince1970: 1_700_100_000))
        try await repo.create(old)
        try await repo.create(fresh)

        await model.reload()
        #expect(model.cards.count == 2)

        model.setSort(.modified)
        await model.reload()
        #expect(model.cards.first?.noteId == fresh.id, "modified DESC puts the fresh note first")

        model.setSort(.title)
        await model.reload()
        #expect(model.cards.first?.noteId == fresh.id, "title ASC: Fresh < Old")
    }

    @Test
    func manualReorderPersists() async throws {
        let env = try makeEnvironment()
        let repo = env.persistence.noteRepository!
        let a = Note(title: "A", lastModifiedDeviceId: Self.deviceId)
        let b = Note(title: "B", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(a)
        try await repo.create(b)

        // Manual order initially follows creation order (0, 1024).
        var manual = try await repo.fetchAll(lifecycle: .active, sort: .manual)
        #expect(manual.map(\.id) == [a.id, b.id])

        // Reorder: move B to the front (sort key below A's).
        try await repo.updateSortKey(id: b.id, sortKey: -1024, deviceId: Self.deviceId)
        manual = try await repo.fetchAll(lifecycle: .active, sort: .manual)
        #expect(manual.map(\.id) == [b.id, a.id], "manual reorder persists")

        // The LibraryModel surfaces it.
        let model = LibraryModel(environment: env)
        model.setSort(.manual)
        await model.reload()
        #expect(model.cards.map(\.noteId) == [b.id, a.id])
    }

    @Test
    func searchFiltersCards() async throws {
        let env = try makeEnvironment()
        let repo = env.persistence.noteRepository!
        try await repo.create(Note(title: "Groceries", lastModifiedDeviceId: Self.deviceId))
        try await repo.create(Note(title: "Books", lastModifiedDeviceId: Self.deviceId))

        let model = LibraryModel(environment: env)
        await model.reload()
        #expect(model.cards.count == 2)

        model.setSearchQuery("groc")
        await model.reload()
        #expect(model.isSearching)
        #expect(model.cards.count == 1)
        #expect(model.cards.first?.title == "Groceries")

        // FR-014c: no-results renders the unified empty-state, never an
        // error (FR-011a).
        model.setSearchQuery("zzz-nothing")
        await model.reload()
        #expect(model.cards.isEmpty)
        #expect(!model.isError, "no-results is never an error (FR-011a)")
    }
}
