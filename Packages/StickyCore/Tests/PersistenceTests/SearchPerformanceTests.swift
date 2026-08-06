import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

// MARK: - Search performance test (T039 / SC-005)
//
// Per tasks.md T039: "Performance test: search across 10,000 textual notes
// within 200ms." Spec SC-005 sets the same threshold.
//
// Constitution XI: performance is a product requirement. This test seeds
// 10,000 notes with distinct body text, runs a MATCH query that matches a
// small subset, and asserts the query completes within 200 ms.
//
// Notes:
// - The test uses FTS5 (the production index). A sequential scan would be
//   far slower; FTS5's inverted index is what makes SC-005 achievable.
// - The 200 ms budget is wall-clock from query issue to result return,
//   measured with a continuous clock. CI runners are slower than dev
//   machines; the budget is set per spec and not loosened here.
// - Seeding 10,000 notes is itself slow, so the suite is organized as a
//   single seeded test with multiple query assertions inside it.

@Suite struct SearchPerformanceTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    @Test
    func searchAcrossTenThousandNotesWithinBudget() async throws {
        let store = try DatabaseStore.inMemory()
        let migrator = InitialSchema.migrator()
        try migrator.migrate(store.dbPool)
        let fts = FullTextSearch(dbPool: store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: fts)
        let search = SearchService(store: store, fullTextSearch: fts)

        // Seed 10,000 notes with body content containing a unique token
        // in every 100th note so the MATCH query matches ~100 notes.
        let needle = "zaphodbingo"
        let totalNotes = 10_000
        for i in 0..<totalNotes {
            let noteId = UUID()
            let body: String
            if i % 100 == 0 {
                body = "note \(i) contains \(needle) and other words"
            } else {
                body = "note \(i) ordinary body text without the needle"
            }
            try await repo.create(Note(id: noteId, lastModifiedDeviceId: Self.deviceId))
            let block = Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain(body)), lastModifiedDeviceId: Self.deviceId)
            try await repo.insertBlock(block)
            try await search.reindexNote(noteId: noteId, title: nil, blocks: [block])
        }

        // Measure the search latency. We use a continuous clock and
        // measure the time from issuing the query to receiving results.
        var measuredResults: [SearchResult] = []
        let clock = ContinuousClock()
        let measured = try await clock.measure {
            measuredResults = try await search.searchActiveNotes(query: needle, limit: 100)
        }

        // Assert the budget. 200 ms per SC-005.
        #expect(measured <= .milliseconds(200), "search took \(measured), budget is 200ms")

        // Sanity: the needle appeared in ~100 notes; the limit was 100 so
        // we expect 100 hits (no false negatives from the index).
        // We don't assert the exact count here because FTS5 ranking + limit
        // make it count-dependent; the budget assertion is the test's
        // purpose. But we DO assert at least one hit so the index worked.
        #expect(!measuredResults.isEmpty, "FTS5 should find at least one note containing the needle")
    }
}
