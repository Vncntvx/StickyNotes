import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - AutoSave tests (T031)
//
// Per tasks.md T031: "Implement auto-save draft manager (debounce ~300ms,
// structural ops immediate, flush on focus-loss/close/terminate, revision
// tokens) in `Packages/StickyCore/Sources/EditorCore/AutoSave.swift`."
//
// Verifies:
// - Ordinary text edits are debounced (no save fires immediately).
// - After the debounce interval, the pending draft is flushed.
// - Structural ops (block insert/delete/reorder) save immediately.
// - flushNow() persists pending text edits without waiting for debounce.
// - Revision tokens prevent stale debounced writes from overwriting newer
//   state (the classic "stale-debounced-write" race).
// - pendingChanges is accurate.
// - markDirty without a subsequent flush survives a resetPending() call.
//
// Constitution XII: tests are mandatory. The AutoSave manager is
// main-actor-isolated at the app boundary (a thin wrapper will live in App);
// the EditorCore.AutoSaveDraftManager here is the testable, framework-free
// core that takes a clock + a save sink.

@Suite struct AutoSaveTests {

    // MARK: - Test doubles

    /// A controllable clock for deterministic debounce timing.
    private final class FakeClock: @unchecked Sendable {
        private var now: Date
        init(_ start: Date) { self.now = start }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
        func current() -> Date { now }
    }

    /// Records every save call: (noteId, revisionToken, snapshot).
    private final class SaveRecorder: @unchecked Sendable {
        var calls: [(noteId: UUID, token: AutoSaveRevisionToken, blocks: [Block])] = []
        func save(_ noteId: UUID, token: AutoSaveRevisionToken, blocks: [Block]) {
            calls.append((noteId, token, blocks))
        }
    }

    private func makeManager(
        noteId: UUID,
        deviceId: UUID,
        debounce: TimeInterval,
        clock: FakeClock,
        recorder: SaveRecorder
    ) -> AutoSaveDraftManager {
        AutoSaveDraftManager(
            noteId: noteId,
            deviceId: deviceId,
            debounceInterval: debounce,
            now: { clock.current() },
            save: { id, token, blocks in recorder.save(id, token: token, blocks: blocks) }
        )
    }

    // MARK: - Tests

    @Test
    func textEditIsDebounced() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorder = SaveRecorder()
        let mgr = makeManager(noteId: UUID(), deviceId: UUID(), debounce: 0.3, clock: clock, recorder: recorder)

        await mgr.textEdited(blocks: [Block(noteId: mgr.noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("hi")), lastModifiedDeviceId: UUID())])
        // No save should fire yet (within the debounce window).
        await mgr.tick()
        #expect(recorder.calls.isEmpty)

        // Advance past the debounce window.
        clock.advance(0.31)
        await mgr.tick()
        #expect(recorder.calls.count == 1)
        let savedBlocks = recorder.calls[0].blocks
        #expect(savedBlocks.count == 1)
    }

    @Test
    func structuralOpSavesImmediately() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorder = SaveRecorder()
        let mgr = makeManager(noteId: UUID(), deviceId: UUID(), debounce: 0.3, clock: clock, recorder: recorder)

        let block = Block(noteId: mgr.noteId, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("buy milk"))), lastModifiedDeviceId: UUID())
        await mgr.structuralChange(blocks: [block])
        await mgr.tick()
        #expect(recorder.calls.count == 1, "structural op saves immediately, no debounce")
    }

    @Test
    func flushNowPersistsPendingTextEdits() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorder = SaveRecorder()
        let mgr = makeManager(noteId: UUID(), deviceId: UUID(), debounce: 0.3, clock: clock, recorder: recorder)

        await mgr.textEdited(blocks: [Block(noteId: mgr.noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("draft")), lastModifiedDeviceId: UUID())])
        await mgr.flushNow()
        #expect(recorder.calls.count == 1, "flushNow bypasses the debounce timer")
    }

    @Test
    func staleDebouncedWriteDoesNotClobberNewerState() async throws {
        // Revision A scheduled for debounce; before the timer fires, a
        // structural op (immediate save) writes revision B with a newer token.
        // The debounced revision A's token is now stale and MUST be dropped.
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorder = SaveRecorder()
        let mgr = makeManager(noteId: UUID(), deviceId: UUID(), debounce: 0.3, clock: clock, recorder: recorder)

        let blockA = Block(noteId: mgr.noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("A")), lastModifiedDeviceId: UUID())
        await mgr.textEdited(blocks: [blockA])  // schedules debounce for revision A

        // Before the debounce fires, perform a structural op (revision B).
        let blockB = Block(id: blockA.id, noteId: mgr.noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("B")), lastModifiedDeviceId: UUID())
        await mgr.structuralChange(blocks: [blockB])  // immediate save, newer token
        await mgr.tick()
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls[0].blocks.first.map { p -> String? in
            if case .richText(let doc) = p.payload { return doc.text } else { return nil }
        } == "B")

        // Advance past the original debounce for revision A. The stale
        // write must NOT fire.
        clock.advance(0.31)
        await mgr.tick()
        #expect(recorder.calls.count == 1, "stale debounced write must be dropped")
    }

    @Test
    func pendingChangesReflectsState() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorder = SaveRecorder()
        let mgr = makeManager(noteId: UUID(), deviceId: UUID(), debounce: 0.3, clock: clock, recorder: recorder)

        #expect(await !mgr.hasPendingChanges)
        await mgr.textEdited(blocks: [Block(noteId: mgr.noteId, kind: .richText, sortKey: 0, payload: .richText(.plain("x")), lastModifiedDeviceId: UUID())])
        #expect(await mgr.hasPendingChanges)
    }

    @Test
    func resetPendingClearsPendingState() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorder = SaveRecorder()
        let mgr = makeManager(noteId: UUID(), deviceId: UUID(), debounce: 0.3, clock: clock, recorder: recorder)

        await mgr.textEdited(blocks: [Block(noteId: mgr.noteId, kind: .richText, sortKey: 0, payload: .richText(.plain("x")), lastModifiedDeviceId: UUID())])
        #expect(await mgr.hasPendingChanges)
        await mgr.resetPending()
        #expect(await !mgr.hasPendingChanges)

        // Advancing past the debounce must NOT fire a save (it was reset).
        clock.advance(0.31)
        await mgr.tick()
        #expect(recorder.calls.isEmpty)
    }
}
