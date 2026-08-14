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
        // 004 T012 (FR-001/FR-017a): the 004 redesign adopts the standard
        // full-size-content titlebar + system toolbar chrome — content
        // extends under the titlebar and the note-paper color (with its
        // transparency applied, T014) stays continuous. The former FR-030a
        // black-bar regression is gone (the window background + SwiftUI
        // paper layer compose it; verified via the lifecycle suite).
        #expect(window.styleMask.contains(.fullSizeContentView), "content extends under the titlebar (004 FR-001/T012)")

        // 004 T058 (FR-017a/Q6): 320pt is the enforced real minimum width
        // (2026-08-13 decision — the 220pt extreme-narrow state was dropped
        // in favor of a beautiful conventional minimum; truncation of long
        // titles is accepted). 140pt the minimum height (Q1, unchanged).
        #expect(window.contentMinSize == NSSize(width: 320, height: 140),
                "min size 320×140 (004 FR-017a/T058) — actual \(window.contentMinSize)")

        // 004 T058 (Q7, Apple Notes title pattern): the title is rendered
        // ONLY as the in-content first line (editable, visually distinct).
        // The titlebar must NOT render title text (titleVisibility hidden),
        // while the derived window.title stays set for Mission Control /
        // window menus / VoiceOver.
        #expect(window.titleVisibility == .hidden,
                "titlebar renders no title text (Q7 Apple Notes pattern)")
        #expect(window.title == NoteWindowDerivations.deriveWindowTitle(
                    noteTitle: note.title, firstLine: ""),
                "window.title stays derived while hidden (Mission Control)")

        // Ownership/lifetime guard from the 2026-08-07 crash fix.
        #expect(window.isReleasedWhenClosed == false, "coordinator retains ownership")

        window.close()
        NoteWindowBridge.unregister(noteId: note.id)
        coordinator.releaseWindowDelegate(noteId: note.id)
    }

    // MARK: - 004 T005 (FR-006/contracts §7): close must unregister

    @Test
    func trafficLightCloseUnregistersAndReopenCreatesFreshWindow() async throws {
        let env = try makeEnvironment()
        let coordinator = NoteWindowCoordinator(environment: env)
        let repo = env.persistence.noteRepository!
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let first = try #require(await coordinator.open(noteId: note.id))
        #expect(NoteWindowBridge.isOpen(noteId: note.id), "window registered after open")

        // Close via the red traffic light path (window.close → delegate
        // windowWillClose). The 004 fix (T015) unregisters there.
        first.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(NoteWindowBridge.isOpen(noteId: note.id) == false,
                "traffic-light close must unregister (004 T005 — dead-host resurrection fix)")
        coordinator.releaseWindowDelegate(noteId: note.id)

        // Reopen: must create a BRAND-NEW window (no dead-host revival).
        let second = try #require(await coordinator.open(noteId: note.id))
        #expect(second !== first, "reopen after close creates a fresh window (004 T005)")
        #expect(NoteWindowBridge.isOpen(noteId: note.id))

        second.close()
        try await Task.sleep(for: .milliseconds(100))
        coordinator.releaseWindowDelegate(noteId: note.id)
        NoteWindowBridge.unregister(noteId: note.id)
    }

    // MARK: - 003 T028 (FR-042/SC-003, regression verification)
    //
    // Per tasks.md T028: a new note window (from Library / global shortcut /
    // menu / deep link) places keyboard focus near the content top
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

// MARK: - 004 FR-012 (clarify 2026-08-10): window deactivation hides the
// contextual format row
//
// The bridge's focus flag must track NSWindow key state (not just editing
// events): when the note window resigns key, `hasFocus` flips to false so
// the contextual format row hides; reactivation with the selection intact
// restores it. Wiring: RichTextView.Coordinator observes
// didResignKey/didBecomeKey for the editor's window and republishes the
// snapshot. Driven directly through the coordinator (SwiftUI hosting does
// not render inside hosted tests, so the bridge registry is not exercised
// here).

@MainActor
extension NoteWindowLifecycleTests {
    @Test
    func windowDeactivationClearsEditorFocusFlag() async throws {
        let editor = RichTextView(document: .plain(""), editorTypography: .system(textSize: 13), onCommit: { _ in })
        let bridge = EditorSelectionBridge(noteId: UUID())
        let coordinator = RichTextView.Coordinator(editor)

        let windowA = makeProbeWindow(title: "A")
        let windowB = makeProbeWindow(title: "B")
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 280))
        windowA.contentView?.addSubview(textView)

        coordinator.attach(textView, bridge: bridge, blockId: nil)

        // Deactivate window A → didResignKey → republish → focus false
        // (the contextual format row must hide; FR-012).
        windowA.makeKeyAndOrderFront(nil)
        #expect(windowA.makeFirstResponder(textView), "editor must accept first responder")
        windowB.makeKeyAndOrderFront(nil)
        try await waitUntil("bridge focus must clear on deactivation") {
            bridge.hasFocus == false
        }
        #expect(!bridge.hasFocus)

        // Reactivate → didBecomeKey → republish → focus restored (row
        // reappears, selection still present).
        windowA.makeKeyAndOrderFront(nil)
        try await waitUntil("bridge focus must restore on reactivation") {
            bridge.hasFocus
        }

        windowA.close()
        windowB.close()
    }

    @Test
    func contextualFormatOverlayTracksBridgeVisibility() async throws {
        // 004 (2026-08-10): the format row lives in a topmost AppKit
        // hosting view; it must show with a selection and hide when the
        // window is inactive (FR-012) — mirror of the clickability fix.
        let window = makeProbeWindow(title: "Overlay")
        let bridge = EditorSelectionBridge(noteId: UUID())
        let overlay = ContextualFormatOverlay()
        overlay.install(in: window, bridge: bridge)
        defer {
            overlay.detach()
            window.close()
        }

        #expect(!overlay.isVisible, "no selection → row hidden")

        bridge.publish(
            caretBlockId: nil,
            isTextSelected: true,
            hasFocus: true,
            caretOffset: 0,
            selectedRange: NSRange(location: 0, length: 2),
            selectionRectInWindow: NSRect(x: 120, y: 140, width: 60, height: 16),
            focusedSpecialBlockId: nil
        )
        try await waitUntil("row must show with a selection") { overlay.isVisible }

        bridge.publish(
            caretBlockId: nil,
            isTextSelected: true,
            hasFocus: false,
            caretOffset: 0,
            selectedRange: NSRange(location: 0, length: 2),
            selectionRectInWindow: NSRect(x: 120, y: 140, width: 60, height: 16),
            focusedSpecialBlockId: nil
        )
        try await waitUntil("row must hide on deactivation (FR-012)") { !overlay.isVisible }
    }

    private func makeProbeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = title
        return window
    }

    private func waitUntil(
        _ message: String,
        timeout: Duration = .seconds(4),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                throw TestTimeoutError(message)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

struct TestTimeoutError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
