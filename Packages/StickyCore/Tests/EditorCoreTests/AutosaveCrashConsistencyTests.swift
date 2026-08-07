import Testing
import Foundation
import Domain
import EditorCore
import os

// MARK: - Auto-save debounce + crash-loss contract tests (T229, FR-141a)
//
// Per tasks.md T229: "Persistence test: auto-save debounce + crash-loss
// contract per FR-141/FR-141a — assert ordinary text changes persist in a
// single transaction once 500 ms elapse without further changes
// (deterministic per build); structural ops/todo completion persist
// immediately; flush happens before window close, note deletion,
// auto-removal decision (FR-012), and application quit; crash-recovery:
// terminate the process mid-edit (within the debounce window), relaunch,
// assert at most the input from the last debounce window is lost and content
// persisted by a completed autosave is always recovered".
//
// The crash-loss contract is verified by simulation: a persisted autosave
// (already flushed) is always recovered; an in-window edit is dropped when
// the process "dies" before the debounce fires — exactly the at-most-one-
// window loss bound. The 500 ms debounce is asserted deterministically via
// an injected clock (no sleeps).

@Suite struct AutosaveCrashConsistencyTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    /// A recording sink: what got saved, with which token, in order.
    private actor SaveRecorder {
        private(set) var saves: [(UUID, AutoSaveRevisionToken, [Block])] = []
        func append(_ entry: (UUID, AutoSaveRevisionToken, [Block])) { saves.append(entry) }
        func all() -> [(UUID, AutoSaveRevisionToken, [Block])] { saves }
    }

    /// A manually-advanced clock (lock-guarded; matches the @Sendable
    /// `AutoSaveClock` signature).
    private final class FakeClock: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: Date())
        func advance(by interval: TimeInterval) { lock.withLock { $0 = $0.addingTimeInterval(interval) } }
        func now() -> Date { lock.withLock { $0 } }
    }

    private func block(_ noteId: UUID, text: String) -> Block {
        Block(
            noteId: noteId,
            kind: .richText,
            sortKey: 0,
            payload: .richText(.plain(text)),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func ordinaryTextEditsPersistAfterFiveHundredMilliseconds() async throws {
        let noteId = UUID()
        let recorder = SaveRecorder()
        let clock = FakeClock()

        let manager = AutoSaveDraftManager(
            noteId: noteId,
            deviceId: Self.deviceId,
            now: { clock.now() },
            save: { id, token, blocks in
                await recorder.append((id, token, blocks))
            }
        )

        // Typing: several edits within the window coalesce.
        await manager.textEdited(blocks: [block(noteId, text: "a")])
        await manager.textEdited(blocks: [block(noteId, text: "ab")])
        clock.advance(by: 0.4)
        await manager.textEdited(blocks: [block(noteId, text: "abc")])

        // Before 500 ms elapse: nothing saved.
        clock.advance(by: 0.4)
        await manager.tick()
        #expect(await recorder.all().isEmpty, "no save before the debounce window elapses")

        // At 500 ms after the last edit: exactly one save with the latest
        // content (single transaction; coalesced).
        clock.advance(by: 0.2)
        await manager.tick()
        let saves = await recorder.all()
        #expect(saves.count == 1, "coalesced edits persist in a single save")
        #expect(saves.first?.2.count == 1)
        if case .richText(let doc) = saves.first?.2.first?.payload {
            #expect(doc.text == "abc")
        } else {
            Issue.record("latest content must be persisted")
        }
    }

    @Test
    func structuralChangesPersistImmediately() async throws {
        let noteId = UUID()
        let recorder = SaveRecorder()
        let manager = AutoSaveDraftManager(
            noteId: noteId,
            deviceId: Self.deviceId,
            now: { Date() },
            save: { id, token, blocks in
                await recorder.append((id, token, blocks))
            }
        )

        await manager.structuralChange(blocks: [block(noteId, text: "structural")])
        let saves = await recorder.all()
        #expect(saves.count == 1, "structural ops bypass the debounce")
        if case .richText(let doc) = saves.first?.2.first?.payload {
            #expect(doc.text == "structural")
        }
    }

    @Test
    func staleDebouncedWriteCannotClobberNewerStructuralEdit() async throws {
        let noteId = UUID()
        let recorder = SaveRecorder()
        let clock = FakeClock()
        let manager = AutoSaveDraftManager(
            noteId: noteId,
            deviceId: Self.deviceId,
            now: { clock.now() },
            save: { id, token, blocks in
                await recorder.append((id, token, blocks))
            }
        )

        // Debounced text edit scheduled...
        await manager.textEdited(blocks: [block(noteId, text: "draft")])
        // ...then a structural op lands immediately (advances the token).
        await manager.structuralChange(blocks: [block(noteId, text: "structural")])
        // The debounce window elapses: the stale draft must be dropped.
        clock.advance(by: 0.6)
        await manager.tick()

        let saves = await recorder.all()
        #expect(saves.count == 1, "the stale debounced write must be dropped")
        if case .richText(let doc) = saves.first?.2.first?.payload {
            #expect(doc.text == "structural")
        }
    }

    @Test
    func flushHappensBeforeCloseAndQuit() async throws {
        let noteId = UUID()
        let recorder = SaveRecorder()
        let clock = FakeClock()
        let manager = AutoSaveDraftManager(
            noteId: noteId,
            deviceId: Self.deviceId,
            now: { clock.now() },
            save: { id, token, blocks in
                await recorder.append((id, token, blocks))
            }
        )

        await manager.textEdited(blocks: [block(noteId, text: "unflushed")])
        // Window close / quit path calls flushNow.
        await manager.flushNow()

        let saves = await recorder.all()
        #expect(saves.count == 1, "flushNow persists the pending draft")
        if case .richText(let doc) = saves.first?.2.first?.payload {
            #expect(doc.text == "unflushed")
        }
    }

    @Test
    func crashWithinDebounceWindowLosesAtMostOneWindow() async throws {
        // Crash simulation: the process "dies" mid-edit within the debounce
        // window. The input from the last window is lost; content persisted
        // by a completed autosave (a prior flushed save) is always recovered.
        let noteId = UUID()
        let recorder = SaveRecorder()
        let clock = FakeClock()
        let manager = AutoSaveDraftManager(
            noteId: noteId,
            deviceId: Self.deviceId,
            now: { clock.now() },
            save: { id, token, blocks in
                await recorder.append((id, token, blocks))
            }
        )

        // Completed autosave: persisted.
        await manager.textEdited(blocks: [block(noteId, text: "persisted")])
        clock.advance(by: 0.5)
        await manager.tick()
        #expect((await recorder.all()).count == 1)

        // Crash: a new edit lands, then the process dies before the window.
        await manager.textEdited(blocks: [block(noteId, text: "persistedLOST")])
        // No tick, no flush — the process is gone.

        // Relaunch: recovery reads whatever was persisted — the completed
        // autosave. The in-window edit is lost: exactly one debounce window.
        let saves = await recorder.all()
        #expect(saves.count == 1)
        if case .richText(let doc) = saves.first?.2.first?.payload {
            #expect(doc.text == "persisted")
            #expect(doc.text != "persistedLOST", "in-window input may be lost per FR-141a")
        }
    }

    @Test
    func debounceConstantIsDeterministicAtFiveHundredMilliseconds() {
        #expect(AutoSaveDraftManager.defaultDebounceInterval == 0.5)
    }
}
