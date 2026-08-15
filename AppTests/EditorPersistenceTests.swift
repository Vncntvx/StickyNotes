import Testing
import Foundation
import Domain
import Persistence
import AppKit
import os
@testable import StickyNotes

// MARK: - Editor + appearance persistence tests (T281, US1/US3)
//
// Per tasks.md T281: the note-window host persists editor block changes and
// appearance edits through the repository (FR-141/FR-141a — 500 ms debounce,
// flush on close) and applies the FR-012a auto-discard decision on close.
// Tests: type text → flush → reopen → content preserved (US1 AC3); appearance
// changes survive a "relaunch" (fresh host over the same DB); a never-content
// note is auto-discarded on close while a previously-content note is never
// auto-deleted when emptied.

@MainActor
@Suite struct EditorPersistenceTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000002")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
        )
    }

    private func makeRichTextBlock(noteId: UUID, text: String) -> Block {
        let doc = RichTextDocument(
            text: text,
            paragraphs: [
                RichTextParagraph(
                    startScalar: 0,
                    endScalar: text.unicodeScalars.count,
                    style: .body,
                    runs: [RichTextRun(startScalar: 0, endScalar: text.unicodeScalars.count, marks: [])]
                )
            ]
        )
        return Block(
            noteId: noteId,
            kind: .richText,
            sortKey: 0,
            payload: .richText(doc),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func typeCloseReopenPreservesContent() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }

        // Simulate typing a block into the window.
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let block = makeRichTextBlock(noteId: noteId, text: "persisted draft content")
        host.updateBlocks([block])
        await host.flush()   // FR-141a flush (window close path)

        // "Reopen": a fresh host over the same database.
        let reopened = NoteWindowHostModel(noteId: noteId, environment: env)
        await reopened.load()
        let fetched = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(fetched.count == 1, "the typed block is persisted")
        if case .richText(let doc) = fetched.first?.payload {
            #expect(doc.text == "persisted draft content")
        } else {
            Issue.record("expected a rich-text block")
        }
    }

    @Test
    func appearanceChangesSurviveRelaunch() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard var note = host.note else {
            Issue.record("note missing")
            return
        }
        // FR-031/FR-034/FR-040a/FR-041a/FR-043a: appearance edits.
        note.title = "Renamed Note"
        note.colorKey = .blue
        note.transparency = 0.6
        note.textSize = 18
        note.alwaysOnTop = true
        host.updateAppearance(note)

        // Wait for the immediate structural write.
        try await Task.sleep(nanoseconds: 300_000_000)

        let reopened = NoteWindowHostModel(noteId: noteId, environment: env)
        await reopened.load()
        let fetched = try await env.persistence.noteRepository!.fetch(id: noteId)
        #expect(fetched?.title == "Renamed Note")
        #expect(fetched?.colorKey == .blue)
        #expect(fetched?.transparency == 0.6)
        #expect(fetched?.textSize == 18)
        #expect(fetched?.alwaysOnTop == true)
    }

    @Test
    func neverContentNoteIsAutoDiscardedOnClose() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()

        // FR-012a: a never-contained-content note MAY be removed on close.
        let mayRemove = await host.close()
        #expect(mayRemove, "never-content note may be auto-removed")
    }

    @Test
    func previouslyContentNoteNeverAutoDeletedWhenEmpty() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        let block = makeRichTextBlock(noteId: noteId, text: "x")  // single char = meaningful (FR-012a)
        host.updateBlocks([block])
        await host.flush()

        // Now the text is emptied — but the note previously contained content.
        let empty = makeRichTextBlock(noteId: noteId, text: "   \n ")
        host.updateBlocks([empty])
        await host.flush()
        let mayRemove = await host.close()
        #expect(!mayRemove, "previously-content note MUST NOT be auto-deleted when empty (FR-013/FR-012a)")
    }

    // MARK: - R1.1 race test infrastructure (remediation-phase1 T005)
    //
    // The removed-block resurrection race (emptyBlockRemovalPersists failed
    // intermittently under parallel full-suite load, verified 2026-08-14):
    // two consecutive structural saves overlap because `updateBlocks`
    // overwrites `pendingEditTask` without chaining, and `persistBlocks`
    // diffs against the DB non-atomically (fetch → delete/insert). When the
    // OLDER snapshot's diff lands after the NEWER save completed, the older
    // diff re-inserts the block the newer save deleted.
    //
    // Red-phase evidence: with the gate holding the first save while the
    // second completes, the pre-fix code failed deterministically in 0.125s
    // (fetched == [first, second] — the deleted block was resurrected).
    //
    // Post-fix the saves are SERIALIZED (chained tasks), so the same gate
    // construction deadlocks by design. The test therefore verifies the
    // serialization contract itself: while the first save is held at the
    // gate, `flush()` must NOT complete (the second save waits for the
    // first); after release, the DB must contain only the surviving block.

    /// A one-shot async gate: the first caller suspends until `open()`
    /// resumes it; every later caller passes through immediately.
    /// (Swift 6 strict concurrency: state guarded by OSAllocatedUnfairLock —
    /// NSLock is unavailable from async contexts.)
    private final class AsyncGate: @unchecked Sendable {
        private struct State {
            var continuation: CheckedContinuation<Void, Never>?
            var isOpen = false
            var firstWaiterPending = false
        }

        private let lock = OSAllocatedUnfairLock(initialState: State())

        /// Suspends ONLY the first caller; every subsequent caller passes
        /// through immediately.
        func waitFirstOnly() async {
            let shouldSuspend = lock.withLock { state in
                if state.isOpen || state.firstWaiterPending { return false }
                state.firstWaiterPending = true
                return true
            }
            guard shouldSuspend else { return }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.withLock { state in
                    if state.isOpen {
                        cont.resume()
                    } else {
                        state.continuation = cont
                    }
                }
            }
        }

        func open() {
            let cont = lock.withLock { state -> CheckedContinuation<Void, Never>? in
                state.isOpen = true
                let c = state.continuation
                state.continuation = nil
                return c
            }
            cont?.resume()
        }
    }

    /// A thread-safe completion flag with a bounded wait.
    private final class AsyncFlag: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: false)

        var isSignaled: Bool { lock.withLock { $0 } }

        func signal() {
            lock.withLock { $0 = true }
        }

        /// Returns true when signaled within `timeout`, false on timeout.
        func waitUntilSignaled(timeout: TimeInterval) async -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if isSignaled { return true }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return isSignaled
        }
    }

    @Test
    func emptyBlockRemovalPersists() async throws {
        // Deleting a block through the host removes it from the database
        // (the autosave sink diffs against the DB).
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        // R1.1 (T005): hold the FIRST structural save at the gate. The
        // second save (and therefore `flush()`) must wait for it.
        let gate = AsyncGate()
        let flushCompleted = AsyncFlag()
        let host = NoteWindowHostModel(noteId: noteId, environment: env, saveGate: { await gate.waitFirstOnly() })
        await host.load()
        let first = makeRichTextBlock(noteId: noteId, text: "keep")
        let second = makeRichTextBlock(noteId: noteId, text: "remove me")
        host.updateBlocks([first, second], isStructural: true)
        // Let the first save task start and suspend at the gate.
        await Task.yield()
        await Task.yield()
        await Task.yield()

        // The user deletes the second block (cursor-exit merge per FR-050a).
        host.updateBlocks([first], isStructural: true)
        let flushTask = Task {
            await host.flush()
            flushCompleted.signal()
        }

        // R1.1 serialization contract: while the first save is held, flush
        // MUST NOT complete — the second save chains behind the first.
        let finishedEarly = await flushCompleted.waitUntilSignaled(timeout: 0.5)
        #expect(finishedEarly == false,
                "R1.1: flush must wait for the prior save (saves are serialized per note)")

        // Release the first save, then verify the final DB state: the
        // second (newest) save diffs against the state the first produced
        // and removes the deleted block.
        gate.open()
        await flushTask.value
        let fetched = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        #expect(fetched.map(\.id) == [first.id], "the removed block is deleted from the database (R1.1: stale snapshot must not resurrect it)")
    }
}
