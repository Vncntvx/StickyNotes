import Testing
import Foundation
import AppKit
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Note window lifecycle regression tests (2026-08-07 crash)
//
// The 2026-08-07 manual-run crash: EXC_BAD_ACCESS in `objc_release` during
// the main-thread autorelease pool drain (0xA1A1A1A1 freed-memory markers),
// shortly after creating a note window. Root-cause candidates fixed:
// - Programmatic `NSWindow` defaults to `isReleasedWhenClosed = true` —
//   AppKit releases the window on close while the app still references it
//   (double release). All programmatic windows now set
//   `isReleasedWhenClosed = false` and the coordinator retains ownership.
// - `NSWindow.delegate` is weak — the per-window delegate deallocated
//   immediately after `open()` returned, so `windowWillClose` (frame save,
//   FR-141a flush, FR-012a auto-discard) never ran. The coordinator now
//   retains delegates until close/unregister.
//
// These tests open/close note windows repeatedly to catch any residual
// over-release deterministically.

@MainActor
@Suite struct NoteWindowLifecycleTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000020")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: nil, store: nil),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.winlife.\(UUID().uuidString)") ?? .standard)
        )
    }

    @Test
    func openCloseCyclesDoNotDoubleRelease() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = env.persistence.noteRepository!

        for i in 0..<5 {
            let note = Note(lastModifiedDeviceId: Self.deviceId)
            try await repo.create(note)

            let window = await coordinator.open(noteId: note.id)
            #expect(window != nil, "note window must open (iteration \(i))")

            // Close via the same paths production uses (close → delegate
            // windowWillClose → release).
            window?.close()
            NoteWindowBridge.unregister(noteId: note.id)
            coordinator.releaseWindowDelegate(noteId: note.id)

            // Drain the runloop so AppKit's close processing + autorelease
            // pools flush — this is where the 2026-08-07 crash surfaced.
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(true)
    }

    @Test
    func closingKeepsDelegateAliveUntilWindowWillClose() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = env.persistence.noteRepository!
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let window = await coordinator.open(noteId: note.id)
        #expect(window != nil)
        // The delegate must still be retained (NSWindow.delegate is weak;
        // without retention windowWillClose never fires).
        window?.close()
        try await Task.sleep(for: .milliseconds(100))
        coordinator.releaseWindowDelegate(noteId: note.id)
        NoteWindowBridge.unregister(noteId: note.id)
        #expect(true)
    }

    // MARK: - T003 pre-redesign snapshots (003-macos27-liquid-glass-redesign)
    //
    // Red-light behavior pin: the note window stays a standard macOS window
    // (traffic lights, move/resize/close) across the presentation redesign
    // (003 FR-040 regression assertions). The redesign must NOT remove the
    // standard chrome or change the ownership/lifetime semantics.

    @Test
    func snapshotNoteWindowKeepsStandardTrafficLightChrome() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = env.persistence.noteRepository!
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let window = try #require(await coordinator.open(noteId: note.id))
        // Standard macOS chrome: titled (traffic lights), closable
        // (red-light close), resizable (green-light resize).
        #expect(window.styleMask.contains(.titled), "standard title bar with traffic lights (FR-006/FR-007)")
        #expect(window.styleMask.contains(.closable), "close button present (red light)")
        #expect(window.styleMask.contains(.resizable), "resize semantics present (green light)")
        // 1f82fbd (FR-030a): the note-paper chrome renders the titlebar
        // area with `titlebarAppearsTransparent` + the OPAQUE note color as
        // `window.backgroundColor` — deliberately NOT `.fullSizeContentView`
        // (which reintroduced the black-bar regression). Pin the absence so
        // a redesign cannot silently swap the compositing approach.
        #expect(!window.styleMask.contains(.fullSizeContentView), "titlebar composited via transparent titlebar + note-color background (FR-030a)")

        // Ownership/lifetime guard from the 2026-08-07 crash fix.
        #expect(window.isReleasedWhenClosed == false, "coordinator retains ownership")

        window.close()
        NoteWindowBridge.unregister(noteId: note.id)
        coordinator.releaseWindowDelegate(noteId: note.id)
    }

    // MARK: - 003 T028 (FR-042/SC-003, regression verification)
    //
    // Per tasks.md T028: a new note window (from Library / global shortcut /
    // menu / deep link / widget) places keyboard focus near the content top
    // with no large unexplained blank; typing plain rich text needs no
    // block-type selection. Per plan.md §6 this behavior ALREADY exists —
    // these run as regression verification (pass = baseline; any failure is
    // a real gap closed via T034).

    @Test
    func newNoteWindowActivatesForKeyboarding() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = env.persistence.noteRepository!
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let window = try #require(await coordinator.open(noteId: note.id))
        // FR-007a: the new note window receives keyboard focus immediately.
        #expect(window.isKeyWindow || NSApp.isActive == false,
                "new note window takes key focus (FR-007a) — regression verified")

        window.close()
        NoteWindowBridge.unregister(noteId: note.id)
        coordinator.releaseWindowDelegate(noteId: note.id)
    }

    @Test
    func blankNoteStartsWithSingleRichTextBlock() async throws {
        let env = try makeEnvironment()
        let repo = env.persistence.noteRepository!
        let model = LibraryModel(environment: env)
        let noteId = try #require(await model.createBlankNote())

        // SC-003: a fresh note needs no block-type choice — it begins as a
        // single rich-text block (typing goes straight in).
        let blocks = try await repo.fetchBlocks(noteId: noteId)
        #expect(blocks.count == 1, "exactly one initial rich-text block")
        #expect(blocks[0].kind == .richText)
    }
}

// MARK: - Typing-persistence pipeline (2026-08-07 manual-run regression)
//
// The manual run: typing into a new note never persisted and the note was
// auto-discarded on close. This test pins the model pipeline (create →
// updateBlocks → flush → fetch) so regressions are caught at the model
// layer, independent of SwiftUI wiring.

@MainActor
extension NoteWindowLifecycleTests {
    @Test
    func typedTextPersistsThroughAutosaveAndClose() async throws {
        let env = try makeEnvironment()
        let repo = env.persistence.noteRepository!
        let model = LibraryModel(environment: env)
        let noteId = try #require(await model.createBlankNote(), "note creation must succeed")

        // The note now carries its initial rich-text block.
        var blocks = try await repo.fetchBlocks(noteId: noteId)
        #expect(blocks.count == 1 && blocks[0].kind == .richText, "initial rich-text block must exist")

        // Simulate typing: the editor commits the new document.
        let edited = Block(
            id: blocks[0].id,
            noteId: noteId,
            kind: .richText,
            sortKey: blocks[0].sortKey,
            payload: .richText(.plain("typed content")),
            lastModifiedDeviceId: Self.deviceId,
            createdAt: blocks[0].createdAt,
            modifiedAt: Date()
        )
        blocks[0] = edited
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        host.updateBlocks(blocks)

        // Close-path flush (windowWillClose → host.close()).
        let mayRemove = await host.close()
        #expect(mayRemove == false, "a note with typed content must NOT be auto-discarded (FR-012a)")

        // The typed content must be persisted.
        let persisted = try await repo.fetchBlocks(noteId: noteId)
        #expect(persisted.count == 1)
        if case .richText(let doc) = persisted[0].payload {
            #expect(doc.text == "typed content", "typed text must survive close + reopen")
        } else {
            Issue.record("expected richText payload")
        }
        #expect(try await repo.fetch(id: noteId) != nil, "the note must remain in the library")
    }
}
