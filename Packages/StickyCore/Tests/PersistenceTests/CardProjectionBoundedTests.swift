import Testing
import Foundation
import Domain
import GRDB
@testable import Persistence

// MARK: - R3.7 CardProjection bounded-load tests (T028)
//
// Per remediation roadmap 2026-08-15 R3.7 (A-9): the card projection's
// aggregation queries (previews/todo aggregates/indicators) scanned the
// WHOLE block table — no lifecycle/limit filter — so "bounded loads" only
// bounded the final note-row fetch while decoding every richText block in
// the library (including trashed notes). The fix constrains the
// aggregations to the requested note set; these tests pin the bounded
// DECODE contract through the injected counting decoder.

@Suite struct CardProjectionBoundedTests {

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    /// Seeds `noteCount` notes (of which `trashedCount` are trashed), each
    /// with one richText block whose text carries `blockTag`.
    private func seedLibrary(
        store: DatabaseStore,
        noteCount: Int,
        trashedCount: Int,
        blockTag: String
    ) async throws {
        let noteRepo = SQLiteNoteRepository(
            store: store,
            fullTextSearch: FullTextSearch(dbPool: store.dbPool)
        )
        let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-0000000000f7")!
        for i in 0..<noteCount {
            let noteId = UUID()
            let note = Note(
                id: noteId,
                title: "note-\(i)",
                lifecycleState: i < trashedCount ? .trashed : .active,
                lastModifiedDeviceId: deviceId
            )
            try await noteRepo.create(note)
            try await noteRepo.insertBlock(Block(
                noteId: noteId,
                kind: .richText,
                sortKey: 0,
                payload: .richText(.plain("\(blockTag)-\(i) content")),
                lastModifiedDeviceId: deviceId
            ))
        }
    }

    @Test
    func decodeCountIsBoundedByRequestedNotes() async throws {
        // 2,000 notes: 1,500 trashed + 500 active. An active-scope fetch of
        // 500 rows must decode at most ~500 payloads (one preview per
        // returned card) — NOT all 2,000 blocks.
        let store = try makeStore()
        try await seedLibrary(
            store: store,
            noteCount: 2000,
            trashedCount: 1500,
            blockTag: "TAG"
        )

        let counter = DecodeCounter()
        let projections = try await CardProjection.fetchCardProjections(
            store: store,
            lifecycleStates: [.active],
            sort: .title,
            limit: 500,
            previewPayloadDecoder: counter.counter
        )
        #expect(projections.count == 500, "active scope must return exactly the 500 active notes")
        #expect(counter.count <= 500,
                "preview decode count must be bounded by the returned card count (got \(counter.count))")
    }

    @Test
    func trashedNoteBlocksAreNeverDecoded() async throws {
        let store = try makeStore()
        try await seedLibrary(
            store: store,
            noteCount: 2000,
            trashedCount: 1500,
            blockTag: "TAG"
        )

        let counter = DecodeCounter()
        _ = try await CardProjection.fetchCardProjections(
            store: store,
            lifecycleStates: [.active],
            sort: .title,
            limit: 10,
            previewPayloadDecoder: counter.counter
        )
        // 10 active cards → at most 10 preview decodes (trashed blocks
        // excluded from the bounded aggregation).
        #expect(counter.count <= 10,
                "small bounded fetch must not decode the whole library (got \(counter.count))")
    }

    @Test
    func searchResultScopeStaysUnbounded() async throws {
        // FTS path (noteIds non-nil) must still return ALL matching notes
        // (FR-023/SC-005: search results are not bounded by the 500 row
        // cap) — and decode exactly those notes' previews.
        let store = try makeStore()
        try await seedLibrary(
            store: store,
            noteCount: 60,
            trashedCount: 0,
            blockTag: "TAG"
        )
        let notes = try await SQLiteNoteRepository(
            store: store,
            fullTextSearch: FullTextSearch(dbPool: store.dbPool)
        ).fetchAll(lifecycle: .active, sort: .title)
        let allIds = Set(notes.map(\.id))
        let counter = DecodeCounter()
        let projections = try await CardProjection.fetchCardProjections(
            store: store,
            lifecycleStates: [.active],
            sort: .title,
            limit: CardProjection.maxRows,
            noteIds: allIds,
            previewPayloadDecoder: counter.counter
        )
        #expect(projections.count == 60)
        #expect(counter.count <= 60)
    }
}

/// Thread-safe decode counter for the injection seam.
private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    func counter(_ data: Data) -> CanonicalBlockPayload? {
        lock.lock(); defer { lock.unlock() }
        _count += 1
        let decoder = CanonicalJSONDecoder()
        return try? decoder.decode(CanonicalBlockPayload.self, from: data)
    }
}
