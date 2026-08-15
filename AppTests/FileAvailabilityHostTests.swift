import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - R2.3 file-availability host evaluation (Phase 2)
//
// The library cards must reflect the REAL FR-100 file state (the silent
// `.onAnotherDevice` default masked missing wiring — audit S-6). The host
// evaluator resolves the device-local locator (bookmark bytes) through
// SecurityScopedBookmarks and classifies per FR-100. In the sandboxed test
// environment only two states are reachable (no user-granted security
// scope): no locator → onAnotherDevice; an unresolvable bookmark → stale.
// The `.available`/`.missing` states are covered by the SystemBridge
// classifier tests (FileReferenceAccessTests).

@MainActor
@Suite struct FileAvailabilityHostTests {

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
        )
    }

    /// Creates a note + file-reference block (the locator row FK-references
    /// the block — the constraint requires the block to exist first).
    private func makeFileRefBlock(env: AppEnvironment) async throws -> (noteId: UUID, blockId: UUID) {
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            throw StickyError.persistence(.databaseOpenFailed)
        }
        let blockId = UUID()
        try await env.persistence.noteRepository!.insert(Block(
            id: blockId,
            noteId: noteId,
            kind: .fileRef,
            sortKey: 0,
            payload: .fileReference(FileReferencePayload(
                displayName: "example.pdf",
                contentType: "public.pdf",
                originDeviceId: UUID(),
                addedAt: Date()
            )),
            lastModifiedDeviceId: UUID()
        ))
        return (noteId, blockId)
    }

    @Test
    func missingLocatorReportsOnAnotherDevice() async throws {
        let env = try makeEnvironment()
        let host = NoteWindowHostModel(noteId: UUID(), environment: env)
        // No fileLocator row for this block → synchronized metadata only
        // (FR-104): the card must NOT guess .available.
        let availability = await host.fileAvailability(blockId: UUID())
        #expect(availability == .onAnotherDevice)
    }

    @Test
    func unresolvableBookmarkReportsStale() async throws {
        let env = try makeEnvironment()
        let (_, blockId) = try await makeFileRefBlock(env: env)
        // A locator row with garbage bookmark bytes — resolution fails →
        // FR-100 "stale" (the file may still exist).
        try await env.persistence.fileLocatorRepository?.upsert(FileLocator(
            blockId: blockId,
            bookmarkData: Data("not-a-real-bookmark".utf8),
            lastResolvedPath: "/tmp/whatever.pdf",
            availabilityStatus: .available,
            stale: false
        ))
        let host = NoteWindowHostModel(noteId: UUID(), environment: env)
        let availability = await host.fileAvailability(blockId: blockId)
        #expect(availability == .stale, "an unresolvable bookmark is stale, never silently available")
    }

    @Test
    func evaluationPersistsBackToLocatorRow() async throws {
        let env = try makeEnvironment()
        let (_, blockId) = try await makeFileRefBlock(env: env)
        try await env.persistence.fileLocatorRepository?.upsert(FileLocator(
            blockId: blockId,
            bookmarkData: Data("garbage".utf8),
            lastResolvedPath: "/tmp/x.pdf",
            availabilityStatus: .available,
            stale: false
        ))
        let host = NoteWindowHostModel(noteId: UUID(), environment: env)
        _ = await host.fileAvailability(blockId: blockId)
        let refreshed = try await env.persistence.fileLocatorRepository?.fetch(blockId: blockId)
        #expect(refreshed?.availabilityStatus == .stale, "the evaluated state is persisted (truthful after relaunch)")
        #expect(refreshed?.verifiedAt != nil)
    }
}
