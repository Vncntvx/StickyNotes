import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - File-reference availability tests (T291, FR-100/FR-105)
//
// Per tasks.md T291: the FR-100 four-state availability is evaluated from
// the device-local FileLocator bookmark (never hardcoded `.available`), and
// the locator persists round-trip (bookmark bytes never sync — FR-105).

@MainActor
@Suite struct FileReferenceAvailabilityTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000011")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
        )
    }

    @Test
    func locatorRoundTrips() async throws {
        let env = try makeEnvironment()
        // The locator row references a block (FK cascade); create the note
        // + file-reference block first.
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let blockId = UUID()
        try await env.persistence.noteRepository!.insert(Block(
            id: blockId,
            noteId: noteId,
            kind: .fileRef,
            sortKey: 0,
            payload: .fileReference(FileReferencePayload(
                displayName: "example.txt",
                contentType: "public.text",
                originDeviceId: UUID(),
                addedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        ))
        let repo = env.persistence.fileLocatorRepository!
        let locator = FileLocator(
            blockId: blockId,
            bookmarkData: Data([0x01, 0x02, 0x03]),
            lastResolvedPath: FileManager.default.temporaryDirectory.appendingPathComponent("example.txt").path,
            availabilityStatus: .missing,
            stale: true,
            verifiedAt: Date()
        )
        try await repo.upsert(locator)
        let fetched = try await repo.fetch(blockId: blockId)
        #expect(fetched != nil)
        #expect(fetched?.bookmarkData == Data([0x01, 0x02, 0x03]))
        #expect(fetched?.availabilityStatus == .missing)
        #expect(fetched?.stale == true)
        try await repo.delete(blockId: blockId)
        let gone = try await repo.fetch(blockId: blockId)
        #expect(gone == nil)
    }

    @Test
    func availabilityDefaultsToOnAnotherDeviceWithoutLocator() async throws {
        // FR-104: synchronized generic metadata with no local file.
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        // Insert a file-reference block whose locator was never created on
        // this device (the synchronized-metadata case).
        let repo = env.persistence.noteRepository!
        let blockId = UUID()
        let block = Block(
            id: blockId,
            noteId: noteId,
            kind: .fileRef,
            sortKey: 0,
            payload: .fileReference(FileReferencePayload(
                displayName: "remote.pdf",
                contentType: "public.pdf",
                originDeviceId: UUID(),
                addedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.insert(block)
        let availability = await host.fileAvailability(blockId: blockId)
        #expect(availability == .onAnotherDevice, "no local locator → on-another-device (FR-104/FR-100)")
    }

    @Test
    func availabilityClassifiesStaleBookmark() async throws {
        // Garbage bookmark data cannot resolve → .stale (FR-100 "bookmark
        // unresolved but the file may exist").
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let repo = env.persistence.noteRepository!
        let blockId = UUID()
        let block = Block(
            id: blockId,
            noteId: noteId,
            kind: .fileRef,
            sortKey: 0,
            payload: .fileReference(FileReferencePayload(
                displayName: "gone.pdf",
                contentType: "public.pdf",
                originDeviceId: UUID(),
                addedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.insert(block)
        try await env.persistence.fileLocatorRepository!.upsert(FileLocator(
            blockId: blockId,
            bookmarkData: Data("corrupt-bookmark".utf8),
            lastResolvedPath: FileManager.default.temporaryDirectory.appendingPathComponent("gone.pdf").path,
            availabilityStatus: .available,
            stale: false
        ))
        let availability = await host.fileAvailability(blockId: blockId)
        #expect(availability == .stale, "unresolvable bookmark → stale (FR-100)")
    }

    @Test
    func removeReferenceDeletesBlock() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let repo = env.persistence.noteRepository!
        let blockId = UUID()
        let block = Block(
            id: blockId,
            noteId: noteId,
            kind: .fileRef,
            sortKey: 0,
            payload: .fileReference(FileReferencePayload(
                displayName: "x.txt",
                contentType: "public.text",
                originDeviceId: UUID(),
                addedAt: Date()
            )),
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.insert(block)
        await host.performFileAction(blockId: blockId, action: .remove)
        let blocks = try await repo.fetchBlocks(noteId: noteId)
        #expect(!blocks.contains { $0.id == blockId }, "remove deletes the reference block (FR-101)")
    }
}
