import Foundation
import AppKit
import Observation
import Domain
import EditorCore
import Persistence
import SystemBridge

// MARK: - NoteWindowHostModel (T281, FR-141/FR-141a/FR-012a)
//
// Per tasks.md T281: the note-window host bridges the SwiftUI editor surface
// to the repository + the EditorCore AutoSave debouncer (FR-141a: 500 ms
// debounce, single-transaction save, flush before close).
//
// - Appearance edits (title/color/opacity/textSize/alwaysOnTop)
//   persist immediately — they are structural (FR-141a "structural ops persist
//   immediately").
// - Ordinary text edits debounce 500 ms; the save sink diffs the snapshot
//   against the database OFF the main actor (plan §Never on Main Actor) and
//   inserts/updates/deletes in one write path.
// - `close()` flushes pending edits and applies the FR-012a auto-discard
//   decision: a note that NEVER contained meaningful content MAY be removed;
//   a previously-content note is NEVER auto-deleted when its text is empty.
// - Meaningful content = ≥1 non-whitespace Unicode character in the title or
//   any rich-text block, OR the presence of any todo/image/screenshot/code/
//   file-reference block (FR-012a).

@MainActor
@Observable
public final class NoteWindowHostModel {
    public private(set) var note: Note?
    public private(set) var blocks: [Block] = []
    public let noteId: UUID

    /// 004 修复: the window-level shared UndoManager — every block editor
    /// (primary/trailing/todo/code) and every structural change use it, so
    /// ⌘Z/⌘⇧Z span the whole note document.
    public let undoManager = UndoManager()
    /// 004 修复: document-level focus request — the target block's editor
    /// becomes first responder (caret at `position`); RichTextBlockView
    /// clears it once handled.
    public private(set) var pendingFocusRequest: EditorFocusRequest?
    /// 004 修复: structural undo/redo revision — todo rows re-fetch their
    /// TodoItem state when it changes (completion/depth/sort undo).
    public private(set) var undoRevision = 0

    let environment: AppEnvironment
    private let autosave: AutoSaveDraftManager
    private var tickTask: Task<Void, Never>?
    /// The most recent edit task. `flush()` awaits it BEFORE flushing so a
    /// debounced edit scheduled from the main actor cannot race the flush
    /// (the edit is always recorded before the flush hop to the actor).
    private var pendingEditTask: Task<Void, Never>?
    /// R1.1 (remediation-phase1 T005/T007): test-injectable pre-save gate.
    /// When non-nil, every scheduled save task awaits it before touching the
    /// autosave manager. Production passes nil. Used by the deterministic
    /// race test (EditorPersistenceTests.emptyBlockRemovalPersists) to hold
    /// the first structural save while the second completes.
    private let saveGate: (@Sendable () async -> Void)?
    private var hasEverHadMeaningfulContent = false
    /// 004 修复: serializes undo/redo restore effects — a rapid ⌘Z/⌘⇧Z
    /// sequence must apply its persistence effects in submission order.
    private var pendingUndoTask: Task<Void, Never>?

    public init(
        noteId: UUID,
        environment: AppEnvironment,
        saveGate: (@Sendable () async -> Void)? = nil
    ) {
        self.noteId = noteId
        self.environment = environment
        self.saveGate = saveGate
        let deviceId = DeviceIdentity.current.id
        // The save sink runs on the AutoSaveDraftManager actor (off the main
        // actor). It captures the Sendable environment + note id, never self.
        // R1.1 (T007): the revision token is deliberately not consumed here —
        // save ordering is guaranteed by the host's chained task queue, and
        // stale-debounced-write protection lives in the manager (tick's
        // token check, contract-tested in AutoSaveTests). The token is
        // still received so the sink signature stays manager-compatible.
        self.autosave = AutoSaveDraftManager(noteId: noteId, deviceId: deviceId) { [environment] noteId, _, blocks in
            await Self.persistBlocks(blocks, noteId: noteId, environment: environment)
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                await self.autosave.tick()
            }
        }
    }
    // MARK: - Loading

    public func load() async {
        guard let repo = environment.persistence.noteRepository else { return }
        do {
            self.note = try await repo.fetch(id: noteId)
            self.blocks = try await repo.fetchBlocks(noteId: noteId)
            self.hasEverHadMeaningfulContent = note.map { NoteAutoDiscard.hadContent($0, blocks: blocks) } ?? false
            healTrailingEmptyLinesOnLoad()
        } catch {
            self.note = nil
        }
    }

    /// 004 修复 (2026-08-13 用户实测): notes edited under the pre-fix
    /// builds accumulated trailing empty paragraphs inside their rich-text
    /// blocks (degraded insertions left them), rendered as a phantom gap
    /// below the last content line. Consume them once on load — blocks are
    /// separated by the fixed inter-block rhythm, never by trailing
    /// newlines inside a block, so this is both safe and idempotent.
    private func healTrailingEmptyLinesOnLoad() {
        var updated = blocks
        var changed = false
        for idx in updated.indices {
            guard case .richText(let doc) = updated[idx].payload else { continue }
            let trimmed = NoteWindowDerivations.trimmingTrailingEmptyLines(doc)
            guard trimmed.text != doc.text else { continue }
            let b = updated[idx]
            updated[idx] = Block(
                id: b.id, noteId: b.noteId, kind: .richText, sortKey: b.sortKey,
                payload: .richText(trimmed),
                versionId: b.versionId, parentVersionId: b.parentVersionId,
                lastModifiedDeviceId: b.lastModifiedDeviceId,
                createdAt: b.createdAt, modifiedAt: Date()
            )
            changed = true
        }
        guard changed else { return }
        updateBlocks(updated, isStructural: true)
    }

    // MARK: - Editing

    /// Persists an appearance edit immediately (structural op, FR-141a).
    public func updateAppearance(_ updated: Note) {
        self.note = updated
        if NoteAutoDiscard.hadContent(updated, blocks: blocks) {
            hasEverHadMeaningfulContent = true
        }
        let deviceId = DeviceIdentity.current.id
        Task {
            guard let repo = environment.persistence.noteRepository else { return }
            try? await repo.update(updated, modifyingDeviceId: deviceId)
            // FR-023 (T283): keep the FTS document in sync after the title
            // change (the repository's title-only refresh must not drop the
            // block text from the index).
            if let service = environment.persistence.searchService {
                try? await service.reindexNote(noteId: noteId, title: updated.title, blocks: blocks)
            }
            await environment.syncCoordinator?.localContentChanged()
        }
    }

    /// Records a block-model change. Text edits debounce (500 ms, FR-141a);
    /// structural changes (todo toggles, block insert/delete/reorder) save
    /// immediately.
    public func updateBlocks(_ newBlocks: [Block], isStructural: Bool = false) {
        StickyLogger(category: .app).debug("host-updateBlocks", code: "fired", sanitizedContext: "count=\(newBlocks.count)")
        self.blocks = newBlocks
        if let note, NoteAutoDiscard.hadContent(note, blocks: newBlocks) {
            hasEverHadMeaningfulContent = true
        }
        let snapshot = newBlocks
        // R1.1 (remediation-phase1 T007): chain the new save task behind the
        // previous one. Before this fix, overwriting `pendingEditTask`
        // orphaned the prior task, and two overlapping `persistBlocks`
        // invocations (each fetch→diff→write, non-atomic) could interleave —
        // an older snapshot's diff landing after a newer save resurrected
        // deleted blocks (verified 2026-08-14: EditorPersistenceTests
        // emptyBlockRemovalPersists failed intermittently under parallel
        // load). Chaining serializes saves per note so the newest snapshot
        // always diffs against the DB state the previous save produced.
        let previous = pendingEditTask
        pendingEditTask = Task {
            await saveGate?()
            await previous?.value
            if isStructural {
                await autosave.structuralChange(blocks: snapshot)
            } else {
                await autosave.textEdited(blocks: snapshot)
            }
        }
    }

    // MARK: - Unified undo (004 修复: structural change = ONE undo group)
    //
    // Every structural mutation (insert/delete/move/toggle/empty-block
    // removal) registers a single undo group on the shared window-level
    // UndoManager. Revision (2026-08-13 用户实测): the stack is NEVER
    // cleared — the full interleaved history survives, so ⌘Z first undoes
    // typing, then the structural change itself, and keeps going into the
    // pre-change typing. Stale actions targeting deallocated text storages
    // are skipped by NSUndoManager automatically.

    /// Applies an editor-side structural change (e.g. FR-050a empty-block
    /// removal) as ONE undo group.
    public func updateBlocksStructural(_ newBlocks: [Block]) {
        let previous = self.blocks
        guard previous != newBlocks else { return }
        updateBlocks(newBlocks, isStructural: true)
        registerStructuralUndo(
            restoreOld: { [weak self] in self?.updateBlocks(previous, isStructural: true) },
            restoreNew: { [weak self] in self?.updateBlocks(newBlocks, isStructural: true) }
        )
    }

    /// Registers a structural undo group: `restoreOld` runs on ⌘Z,
    /// `restoreNew` on ⌘⇧Z — both restore the in-memory block list and
    /// reconcile persistence (TodoItem rows etc.). The closures swap on
    /// every round trip so undo/redo alternates indefinitely.
    private func registerStructuralUndo(
        restoreOld: @escaping @MainActor () async -> Void,
        restoreNew: @escaping @MainActor () async -> Void
    ) {
        let manager = undoManager
        // 004 修复: register the group with `groupsByEvent = false` so it is
        // a STANDALONE top-level group — with the default, `beginUndoGrouping`
        // NESTS inside the still-open implicit per-event group and adjacent
        // actions (or two structural changes in one turn) collapse into a
        // single undo step. Restore the mode immediately: NSTextView's own
        // typing-coalescing relies on `groupsByEvent == true`.
        let prior = manager.groupsByEvent
        manager.groupsByEvent = false
        manager.beginUndoGrouping()
        registerRedoPair(restoreOld: restoreOld, restoreNew: restoreNew)
        manager.endUndoGrouping()
        manager.groupsByEvent = prior
    }

    private func registerRedoPair(
        restoreOld: @escaping @MainActor () async -> Void,
        restoreNew: @escaping @MainActor () async -> Void
    ) {
        // NSUndoManager retains its target until the action is removed —
        // `close()` clears the stack to break that cycle.
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.enqueueUndoRestore(restoreOld)
                target.registerRedoPair(restoreOld: restoreNew, restoreNew: restoreOld)
            }
        }
    }

    /// Serializes undo/redo restore effects: memory state and persistence
    /// effects run in submission order, then the revision bumps (todo rows
    /// re-fetch their TodoItem state).
    private func enqueueUndoRestore(_ restore: @escaping @MainActor () async -> Void) {
        let previous = pendingUndoTask
        pendingUndoTask = Task { @MainActor in
            await previous?.value
            await restore()
            self.undoRevision += 1
        }
    }

    /// Clears the document-level focus request once the editor handled it.
    public func clearPendingFocusRequest() {
        pendingFocusRequest = nil
    }

    /// Flushes any pending debounced write now (focus loss, window close,
    /// quit). No-op when nothing is pending. Awaits the last recorded edit
    /// first so a just-scheduled debounced edit cannot be missed.
    public func flush() async {
        await pendingEditTask?.value
        await autosave.flushNow()
    }

    // MARK: - Block insertion (T290, FR-050/FR-070/FR-080/FR-100)

    // MARK: 004 (FR-010/Q4, contracts §5): insertion targets
    //
    // All window-level insertion paths (toolbar Insert menu, app menus,
    // BlockInsertionControl) converge on the host methods below, carrying a
    // resolved `InsertionTarget`. Stale contexts degrade to `.append`.

    /// Applies an insertion target to the block list. `makeBlock(sortKey:)`
    /// produces the block to insert; the returned array already contains the
    /// split-trailing rich-text block when the target splits one.
    private func blocksApplyingTarget(
        _ target: InsertionTarget,
        makeBlock: (Int) -> Block
    ) -> [Block] {
        sweepingAbandonedWhitespaceBlocks(applyingTarget(target, makeBlock: makeBlock))
    }

    /// 004 修复 (2026-08-13 用户实测): whitespace-only secondary rich-text
    /// blocks render as phantom empty lines at the insertion site and never
    /// self-heal — FR-050a exit removal needs a focus ENTRY, which an
    /// orphaned tail never receives. They are already "empty" per FR-050a
    /// semantics, so every structural insertion sweeps them. The PRIMARY
    /// surface is exempt: its zero-height caret slot is the caret-at-start
    /// exception (and the empty note's click target).
    private func sweepingAbandonedWhitespaceBlocks(_ updated: [Block]) -> [Block] {
        let primaryId = updated.first(where: { $0.kind == .richText })?.id
        return updated.filter { block in
            guard block.id != primaryId, case .richText(let doc) = block.payload else { return true }
            return !doc.text.allSatisfy(\.isWhitespace)
        }
    }

    private func applyingTarget(
        _ target: InsertionTarget,
        makeBlock: (Int) -> Block
    ) -> [Block] {
        // Rebuilds the rich-text block at `idx` with its trailing empty
        // lines consumed (returns `blocks` unchanged when there is nothing
        // to trim or the block isn't rich text). A block inserted right
        // after must land directly below the LAST content line — never
        // below a phantom gap of trailing empty paragraphs. The
        // caretSplit path consumes the tail via Case A; this covers the
        // degraded `.append` / `.afterBlock` paths (menu commands, stale
        // caret context).
        func consumingTrailingEmptyLines(_ list: [Block], at idx: Int) -> [Block] {
            guard case .richText(let doc) = list[idx].payload else { return list }
            let trimmed = NoteWindowDerivations.trimmingTrailingEmptyLines(doc)
            guard trimmed.text != doc.text else { return list }
            var updated = list
            let b = list[idx]
            updated[idx] = Block(
                id: b.id, noteId: b.noteId, kind: .richText, sortKey: b.sortKey,
                payload: .richText(trimmed),
                versionId: b.versionId, parentVersionId: b.parentVersionId,
                lastModifiedDeviceId: b.lastModifiedDeviceId,
                createdAt: b.createdAt, modifiedAt: Date()
            )
            return updated
        }
        func appendFallback() -> [Block] {
            var base = self.blocks
            if let lastIdx = base.indices.max(by: { base[$0].sortKey < base[$1].sortKey }) {
                base = consumingTrailingEmptyLines(base, at: lastIdx)
            }
            return base + [makeBlock((base.map(\.sortKey).max() ?? 0) + 1024)]
        }
        switch target {
        case .append:
            return appendFallback()
        case .afterBlock(let blockId):
            guard let idx = self.blocks.firstIndex(where: { $0.id == blockId }) else {
                return appendFallback()
            }
            let updated = consumingTrailingEmptyLines(blocks, at: idx)
            let before = updated[idx].sortKey
            let after = updated.indices.contains(idx + 1) ? updated[idx + 1].sortKey : before + 1024
            var result = updated
            result.insert(makeBlock((before + after) / 2), at: idx + 1)
            return result
        case .caretSplit(let blockId, let offset):
            guard let idx = self.blocks.firstIndex(where: { $0.id == blockId }),
                  case .richText(let doc) = self.blocks[idx].payload else {
                return appendFallback()
            }
            let split = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: offset)
            let s = blocks[idx].sortKey
            let after = blocks.indices.contains(idx + 1) ? blocks[idx + 1].sortKey : s + 1024

            // Case A — caret at the block's END (or an entirely empty
            // block): NEVER spawn an empty trailing block (the reported
            // Add-Todo/Add-Code bug). A whitespace-only tail (the newline
            // terminating the last visible line, runs of empty paragraphs)
            // counts as empty — the caret visually sits at the end of the
            // content, so the tail is consumed rather than materialized as
            // a phantom block. Trailing empty paragraphs are consumed;
            // when nothing survives, the new block REPLACES the empty one.
            if split.trailing.text.allSatisfy(\.isWhitespace) {
                let trimmed = NoteWindowDerivations.trimmingTrailingEmptyLines(split.leading)
                if trimmed.text.isEmpty {
                    var updated = blocks
                    updated[idx] = makeBlock(s)
                    return updated
                }
                var updated = blocks
                updated[idx] = Block(
                    id: blockId, noteId: noteId, kind: .richText, sortKey: s,
                    payload: .richText(trimmed),
                    versionId: blocks[idx].versionId, parentVersionId: blocks[idx].parentVersionId,
                    lastModifiedDeviceId: blocks[idx].lastModifiedDeviceId,
                    createdAt: blocks[idx].createdAt, modifiedAt: Date()
                )
                updated.insert(makeBlock((s + after) / 2), at: idx + 1)
                return updated
            }

            // Case B — caret at the block's START: insert BEFORE, no empty
            // leading block. Exception: the PRIMARY surface renders pinned
            // above every secondary block, so there the empty leading half
            // stays as the 0pt primary slot — the only way the new block
            // can appear above the text (FR-050a removes the emptied slot
            // the moment the insertion focus moves on).
            let isPrimarySurface = blocks.firstIndex(where: { $0.kind == .richText }) == idx
            if split.leading.text.isEmpty, !isPrimarySurface {
                let before = idx > 0 ? blocks[idx - 1].sortKey : s - 1024
                var updated = blocks
                updated.insert(makeBlock((before + s) / 2), at: idx)
                return updated
            }

            // Case C — a genuine middle split (and the primary-surface
            // caret-at-start exception above): the block keeps its id; its
            // payload becomes the LEADING text.
            let trailingSort = (s + after) / 2
            let newSort = (s + trailingSort) / 2
            var updated = blocks
            updated[idx] = Block(
                id: blockId, noteId: noteId, kind: .richText, sortKey: s,
                payload: .richText(split.leading),
                versionId: blocks[idx].versionId, parentVersionId: blocks[idx].parentVersionId,
                lastModifiedDeviceId: blocks[idx].lastModifiedDeviceId,
                createdAt: blocks[idx].createdAt, modifiedAt: Date()
            )
            // The trailing text becomes a NEW rich-text block (the editor
            // renders it after the primary surface).
            let trailing = Block(
                id: UUID(), noteId: noteId, kind: .richText, sortKey: trailingSort,
                payload: .richText(split.trailing),
                lastModifiedDeviceId: DeviceIdentity.current.id
            )
            updated.insert(trailing, at: idx + 1)
            // The new block lands between the leading and trailing parts.
            updated.insert(makeBlock(newSort), at: idx + 1)
            return updated
        }
    }

    /// Inserts a new todo block (stable TodoItem identity — FR-071) at the
    /// resolved target and returns its id.
    @discardableResult
    public func insertTodoBlock(target: InsertionTarget? = nil) async -> UUID? {
        guard let todoRepo = environment.persistence.todoRepository else { return nil }
        let now = Date()
        let deviceId = DeviceIdentity.current.id
        let todoId = UUID()
        let blockId = UUID()
        let previous = blocks
        let newBlocks = blocksApplyingTarget(target ?? .append) { sortKey in
            Block(
                id: blockId,
                noteId: noteId,
                kind: .todo,
                sortKey: sortKey,
                payload: .todo(TodoPayload(todoId: todoId, richText: RichTextDocument.plain(""))),
                lastModifiedDeviceId: deviceId,
                createdAt: now,
                modifiedAt: now
            )
        }
        let blockSortKey = newBlocks.first(where: { $0.id == blockId })?.sortKey ?? 0
        let item = TodoItem(
            id: todoId,
            noteId: noteId,
            blockId: blockId,
            sortKey: blockSortKey,
            depth: 0,
            lastModifiedDeviceId: deviceId,
            createdAt: now,
            modifiedAt: now
        )
        do {
            // The TodoItem references the block (FK) — persist the block
            // first (FR-141a: structural ops save immediately; await the
            // autosave so the block exists before the item insert).
            updateBlocks(newBlocks, isStructural: true)
            // 004 修复: ONE undo group — ⌘Z restores the pre-insert blocks
            // and removes the TodoItem row; ⌘⇧Z re-applies both. The flush
            // awaits the block-row persistence BEFORE the TodoItem row
            // write (FK references the block).
            registerStructuralUndo(
                restoreOld: { [weak self] in
                    guard let self else { return }
                    self.updateBlocks(previous, isStructural: true)
                    await self.flush()
                    try? await todoRepo.delete(id: blockId)
                },
                restoreNew: { [weak self] in
                    guard let self else { return }
                    self.updateBlocks(newBlocks, isStructural: true)
                    await self.flush()
                    try? await todoRepo.insert(item)
                }
            )
            pendingFocusRequest = EditorFocusRequest(blockId: blockId, position: .start)
            await flush()
            try await todoRepo.insert(item)
            return blockId
        } catch {
            return nil
        }
    }

    /// Inserts a new code block at the resolved target and returns its id.
    @discardableResult
    public func insertCodeBlock(target: InsertionTarget? = nil) async -> UUID? {
        let blockId = UUID()
        let previous = blocks
        let newBlocks = blocksApplyingTarget(target ?? .append) { sortKey in
            Block(
                id: blockId,
                noteId: noteId,
                kind: .code,
                sortKey: sortKey,
                payload: .code(CodePayload(text: "", language: nil)),
                lastModifiedDeviceId: DeviceIdentity.current.id
            )
        }
        updateBlocks(newBlocks, isStructural: true)
        // 004 修复: ONE undo group.
        registerStructuralUndo(
            restoreOld: { [weak self] in self?.updateBlocks(previous, isStructural: true) },
            restoreNew: { [weak self] in self?.updateBlocks(newBlocks, isStructural: true) }
        )
        pendingFocusRequest = EditorFocusRequest(blockId: blockId, position: .start)
        await flush()
        return blockId
    }

    /// Inserts an empty rich-text paragraph at the resolved target (004
    /// 修复 2026-08-14, P0): "create a paragraph" is a FIRST-CLASS document
    /// operation, not a caret-split side effect. Bypasses the whitespace
    /// sweep (`applyingTarget`, not `blocksApplyingTarget`) — an explicitly
    /// created empty paragraph is intentional and must survive.
    @discardableResult
    public func insertRichTextBlock(
        target: InsertionTarget? = nil,
        focus position: EditorFocusRequest.Position = .start
    ) async -> UUID? {
        let blockId = UUID()
        let previous = blocks
        let newBlocks = applyingTarget(target ?? .append) { sortKey in
            Block(
                id: blockId,
                noteId: noteId,
                kind: .richText,
                sortKey: sortKey,
                payload: .richText(.empty),
                lastModifiedDeviceId: DeviceIdentity.current.id
            )
        }
        updateBlocks(newBlocks, isStructural: true)
        // 004 修复: ONE undo group.
        registerStructuralUndo(
            restoreOld: { [weak self] in self?.updateBlocks(previous, isStructural: true) },
            restoreNew: { [weak self] in self?.updateBlocks(newBlocks, isStructural: true) }
        )
        pendingFocusRequest = EditorFocusRequest(blockId: blockId, position: position)
        await flush()
        return blockId
    }

    /// Continues the document from its tail (004 修复 2026-08-14, P0):
    /// - the last block is rich text → focus the EXISTING trailing
    ///   paragraph with the caret at its end (never materializes a
    ///   duplicate empty paragraph);
    /// - the last block is a special block (or the note has no blocks) →
    ///   materialize an empty rich-text paragraph after it and focus it.
    public func continueDocument() async {
        let ordered = NoteWindowDerivations.orderedBlocks(blocks)
        guard let last = ordered.last else {
            _ = await insertRichTextBlock(target: .append)
            return
        }
        if last.kind == .richText {
            pendingFocusRequest = EditorFocusRequest(blockId: last.id, position: .end)
        } else {
            _ = await insertRichTextBlock(target: .afterBlock(blockId: last.id))
        }
    }

    /// Inserts a file-reference block for a user-selected/dropped file
    /// (FR-100): generic metadata in the payload (FR-105), security-scoped
    /// bookmark bytes device-local via FileLocator. The bookmark-creation
    /// step is injectable for tests. `target` places the block at the
    /// resolved insertion point (004 FR-010).
    public func insertFileReferenceBlock(
        url: URL,
        bookmarkCreator: ((URL) throws -> Data)? = nil,
        target: InsertionTarget? = nil
    ) async -> UUID? {
        guard let locatorRepo = environment.persistence.fileLocatorRepository else { return nil }
        do {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .contentModificationDateKey])
            let blockId = UUID()
            let previous = blocks
            let newBlocks = blocksApplyingTarget(target ?? .append) { sortKey in
                Block(
                    id: blockId,
                    noteId: noteId,
                    kind: .fileRef,
                    sortKey: sortKey,
                    payload: .fileReference(FileReferencePayload(
                        displayName: url.lastPathComponent,
                        contentType: (values?.contentType?.identifier) ?? "public.data",
                        approximateSize: values?.fileSize,
                        originDeviceId: DeviceIdentity.current.id,
                        addedAt: Date()
                    )),
                    lastModifiedDeviceId: DeviceIdentity.current.id
                )
            }
            let bookmark = try (bookmarkCreator ?? Self.defaultBookmarkCreator)(url)
            let locator = FileLocator(
                blockId: blockId,
                bookmarkData: bookmark,
                lastResolvedPath: url.path,
                availabilityStatus: .available,
                stale: false,
                verifiedAt: Date()
            )
            // The locator references the block (FK) — persist the block
            // first.
            updateBlocks(newBlocks, isStructural: true)
            await flush()
            try await locatorRepo.upsert(locator)
            // 004 修复: ONE undo group (block list + device-local locator).
            registerStructuralUndo(
                restoreOld: { [weak self] in
                    guard let self else { return }
                    self.updateBlocks(previous, isStructural: true)
                    await self.flush()
                    try? await locatorRepo.delete(blockId: blockId)
                },
                restoreNew: { [weak self] in
                    guard let self else { return }
                    self.updateBlocks(newBlocks, isStructural: true)
                    // The block row must exist before the locator re-insert
                    // (FK) — flush the structural autosave first.
                    await self.flush()
                    try? await locatorRepo.upsert(locator)
                }
            )
            return blockId
        } catch {
            return nil
        }
    }

    /// Default security-scoped bookmark creation (sandboxed app: dropped /
    /// user-selected files carry read scope).
    private static let defaultBookmarkCreator: (URL) throws -> Data = { url in
        try SecurityScopedBookmarks.createBookmark(for: url)
    }

    /// Removes a block + its cascaded records (todo, locator, association).
    /// `registersUndo` is false when the caller composes its own undo group
    /// (deleteTodo covers block + TodoItem in ONE group).
    public func deleteBlock(id: UUID, registersUndo: Bool = true) async {
        guard let repo = environment.persistence.noteRepository else { return }
        let previous = blocks
        do {
            try await repo.delete(id: id)
            await reloadBlocks()
            let after = blocks
            if registersUndo {
                // 004 修复: ONE undo group — ⌘Z re-inserts the block (the
                // autosave diff re-persists it).
                registerStructuralUndo(
                    restoreOld: { [weak self] in self?.updateBlocks(previous, isStructural: true) },
                    restoreNew: { [weak self] in self?.updateBlocks(after, isStructural: true) }
                )
            }
        } catch {
            // silent (FR-141b: background/structural ops give no toast)
        }
    }

    // MARK: - Block merge into previous (2026-08-14)

    /// 块首 Backspace 的"并入上一块"：非空块（todo/code/正文）的文本接到
    /// 上一块末尾（`BlockMergeOperation.mergingIntoPrevious` 纯函数），本块
    /// 移除。本块为 todo 时其 TodoItem 行与块列表在同一个 undo 组往返
    /// （FK 级联，仿 `removeEmptiedTodoBlock`）；有子 todo 的 todo 不合并
    /// （与 FR-050a 的 children 守卫一致）。焦点去上一块末尾（Q4-A 决策）。
    public func mergeBlockIntoPrevious(blockId: UUID) async {
        let ordered = NoteWindowDerivations.orderedBlocks(blocks)
        guard let idx = ordered.firstIndex(where: { $0.id == blockId }),
              idx > 0 else { return }
        let previous = ordered[idx - 1]
        guard let merged = BlockMergeOperation.mergingIntoPrevious(blocks: ordered, index: idx) else { return }
        let todoRepo = environment.persistence.todoRepository
        let removedItem: TodoItem? = (try? await todoRepo?.fetchTodo(blockId: blockId)) ?? nil
        if let removedItem {
            // A todo with children stays — its row's cascade would orphan
            // the children (same guard as removeEmptiedTodoBlock).
            let all = (try? await todoRepo?.fetchTodos(noteId: noteId)) ?? []
            guard !all.contains(where: { $0.parentTodoId == removedItem.id }) else { return }
            try? await todoRepo?.delete(id: blockId)
        }
        let previousBlocks = blocks
        updateBlocks(merged, isStructural: true)
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                self.updateBlocks(previousBlocks, isStructural: true)
                await self.flush()
                if let removedItem, let repo = self.environment.persistence.todoRepository {
                    try? await repo.insert(removedItem)
                }
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                self.updateBlocks(merged, isStructural: true)
                await self.flush()
                if removedItem != nil, let repo = self.environment.persistence.todoRepository {
                    try? await repo.delete(id: blockId)
                }
            }
        )
        pendingFocusRequest = EditorFocusRequest(blockId: previous.id, position: .end)
        await flush()
    }

    /// FR-054 跨块选区删除的 host 接线（2026-08-14）：删除选中字符、空块
    /// 按 FR-050a 并掉；被删 todo 块的 TodoItem 行级联（FK）；单 undo 组
    /// 恢复；焦点去剩余末块开头。
    public func applySpanningDeletion(selection: CrossBlockSelection) async {
        let ordered = NoteWindowDerivations.orderedBlocks(blocks)
        let updated = EditorAppBridge.deleteSpanningSelection(
            blocks: ordered,
            selection: selection,
            noteId: noteId,
            deviceId: DeviceIdentity.current.id
        )
        guard updated != blocks else { return }
        let todoRepo = environment.persistence.todoRepository
        var removedTodoItems: [(blockId: UUID, item: TodoItem?)] = []
        for block in ordered {
            guard case .todo = block.payload,
                  !updated.contains(where: { $0.id == block.id }) else { continue }
            let item: TodoItem? = (try? await todoRepo?.fetchTodo(blockId: block.id)) ?? nil
            removedTodoItems.append((block.id, item))
            if item != nil { try? await todoRepo?.delete(id: block.id) }
        }
        let previousBlocks = blocks
        updateBlocks(updated, isStructural: true)
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                self.updateBlocks(previousBlocks, isStructural: true)
                await self.flush()
                for entry in removedTodoItems {
                    if let item = entry.item, let repo = self.environment.persistence.todoRepository {
                        try? await repo.insert(item)
                    }
                }
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                self.updateBlocks(updated, isStructural: true)
                await self.flush()
                for entry in removedTodoItems {
                    if let repo = self.environment.persistence.todoRepository {
                        try? await repo.delete(id: entry.blockId)
                    }
                }
            }
        )
        if let last = updated.last {
            pendingFocusRequest = EditorFocusRequest(blockId: last.id, position: .start)
        }
        await flush()
    }

    /// 2026-08-14 (Q2-A/Q3-B): 空块按键删除——todo 走 `removeEmptiedTodoBlock`
    /// （TodoItem 行级联），正文/code 走 FR-050a 视图级路径的 host 版
    /// （单 undo 组）；删除成功后焦点去下一块开头。最后一块（keepFinalBlock）
    /// 与 IME 组合（FR-063）时 no-op。
    public func deleteEmptyBlockOnKey(blockId: UUID) async {
        let ordered = NoteWindowDerivations.orderedBlocks(blocks)
        guard let idx = ordered.firstIndex(where: { $0.id == blockId }) else { return }
        // The NEXT block is resolved BEFORE the removal (index shifts).
        let next = ordered.indices.contains(idx + 1) ? ordered[idx + 1] : nil
        if case .todo = ordered[idx].payload {
            await removeEmptiedTodoBlock(blockId: blockId)
        } else if let updated = EditorAppBridge.applyEmptyBlockRemoval(
            blocks: ordered,
            emptiedBlockIndex: idx,
            hasIMEComposition: false
        ) {
            updateBlocksStructural(updated)
            await flush()
        }
        guard !blocks.contains(where: { $0.id == blockId }) else { return }
        if let next {
            pendingFocusRequest = EditorFocusRequest(blockId: next.id, position: .start)
        }
    }

    // MARK: - Todo editing (T290, FR-070/FR-071/FR-072a)

    /// The todo item backing a todo block (stable identity, FR-071).
    public func todoItem(forBlock blockId: UUID) async -> TodoItem? {
        try? await environment.persistence.todoRepository?.fetchTodo(blockId: blockId)
    }

    /// The full todo list of the note (for reorder/indent sibling logic).
    public func todos() async -> [TodoItem] {
        (try? await environment.persistence.todoRepository?.fetchTodos(noteId: noteId)) ?? []
    }

    /// Persists todo completion immediately (FR-070; TodoRepository-backed).
    public func setTodoComplete(blockId: UUID, isComplete: Bool) async {
        guard let todoRepo = environment.persistence.todoRepository,
              let item = try? await todoRepo.fetchTodo(blockId: blockId) else { return }
        let previousValue = item.isComplete
        try? await todoRepo.setComplete(todoId: item.id, isComplete: isComplete, deviceId: DeviceIdentity.current.id)
        // 004 修复: ONE undo group — ⌘Z restores the previous completion
        // state (the undoRevision bump re-syncs the checkbox UI).
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.setComplete(
                    todoId: item.id, isComplete: previousValue, deviceId: DeviceIdentity.current.id
                )
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.setComplete(
                    todoId: item.id, isComplete: isComplete, deviceId: DeviceIdentity.current.id
                )
            }
        )
    }

    /// Deletes a todo block (children reparent to grandparent — FR-070).
    /// The block and its TodoItem (+ children reparenting) undo in ONE
    /// group.
    public func deleteTodo(blockId: UUID) async {
        guard let todoRepo = environment.persistence.todoRepository else { return }
        let previous = blocks
        let item = try? await todoRepo.fetchTodo(blockId: blockId)
        let children = (try? await todoRepo.fetchTodos(noteId: noteId))?.filter { $0.parentTodoId == item?.id } ?? []
        try? await todoRepo.delete(id: blockId)
        await deleteBlock(id: blockId, registersUndo: false)
        let after = blocks
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                self.updateBlocks(previous, isStructural: true)
                // The block row must exist before the TodoItem re-insert
                // (FK) — flush the structural autosave first.
                await self.flush()
                if let item { try? await todoRepo.insert(item) }
                for child in children {
                    try? await todoRepo.reparent(todoId: child.id, newParentId: item?.id, deviceId: DeviceIdentity.current.id)
                }
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                self.updateBlocks(after, isStructural: true)
                await self.flush()
                try? await todoRepo.delete(id: blockId)
            }
        )
    }

    /// FR-050a empty-block exit for todo blocks (004 修复 P1-6): when the
    /// cursor exits an EMPTIED todo, the block merges away per
    /// `BlockMergeOperation.decide` (keepFinalBlock + FR-063 respected via
    /// `EditorAppBridge.applyEmptyBlockRemoval`). Routed through the host
    /// — not the view-level structural path — because the block row's
    /// removal CASCADES the TodoItem row (FK), so the same undo group must
    /// restore both; a view-level swap would resurrect the block without
    /// its row (broken checkbox after ⌘Z).
    public func removeEmptiedTodoBlock(blockId: UUID) async {
        guard let todoRepo = environment.persistence.todoRepository,
              let idx = blocks.firstIndex(where: { $0.id == blockId }),
              BlockMergeOperation.isEmpty(blocks[idx]) else { return }
        let item = try? await todoRepo.fetchTodo(blockId: blockId)
        if let item {
            // An emptied todo that carries children stays — the block-row
            // cascade would delete the parent row without reparenting.
            let all = (try? await todoRepo.fetchTodos(noteId: noteId)) ?? []
            guard !all.contains(where: { $0.parentTodoId == item.id }) else { return }
        }
        guard let updated = EditorAppBridge.applyEmptyBlockRemoval(
            blocks: blocks,
            emptiedBlockIndex: idx,
            hasIMEComposition: false
        ) else { return }
        let previous = blocks
        updateBlocks(updated, isStructural: true)
        // ONE undo group: block list + TodoItem row round-trip together.
        // The flush inside each restore lands the block row BEFORE the
        // TodoItem re-insert (FK references the block).
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                self.updateBlocks(previous, isStructural: true)
                await self.flush()
                if let item { try? await todoRepo.insert(item) }
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                self.updateBlocks(updated, isStructural: true)
                await self.flush()
                try? await todoRepo.delete(id: blockId)
            }
        )
        await flush()
    }

    /// Moves a todo up/down among its siblings (drag-reorder equivalent).
    public func reorderTodo(blockId: UUID, direction: Int) async {
        guard let todoRepo = environment.persistence.todoRepository,
              let item = try? await todoRepo.fetchTodo(blockId: blockId) else { return }
        let all = (try? await todoRepo.fetchTodos(noteId: noteId)) ?? []
        let siblings = all
            .filter { $0.parentTodoId == item.parentTodoId && $0.id != item.id }
            .sorted { $0.sortKey < $1.sortKey }
        guard let index = siblings.firstIndex(where: { $0.sortKey > item.sortKey }) ?? nil,
              direction != 0 else { return }
        // direction < 0 → move up (swap with the previous sibling).
        let targetIndex = direction < 0 ? index - 1 : index
        guard siblings.indices.contains(targetIndex) else { return }
        let target = siblings[targetIndex]
        let itemSortKey = item.sortKey
        let targetSortKey = target.sortKey
        try? await todoRepo.reorder(todoId: item.id, newSortKey: targetSortKey, deviceId: DeviceIdentity.current.id)
        try? await todoRepo.reorder(todoId: target.id, newSortKey: itemSortKey, deviceId: DeviceIdentity.current.id)
        // 004 修复: ONE undo group — swapping back is its own inverse.
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.reorder(todoId: item.id, newSortKey: itemSortKey, deviceId: DeviceIdentity.current.id)
                try? await self.environment.persistence.todoRepository?.reorder(todoId: target.id, newSortKey: targetSortKey, deviceId: DeviceIdentity.current.id)
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.reorder(todoId: item.id, newSortKey: targetSortKey, deviceId: DeviceIdentity.current.id)
                try? await self.environment.persistence.todoRepository?.reorder(todoId: target.id, newSortKey: itemSortKey, deviceId: DeviceIdentity.current.id)
            }
        )
    }

    /// Indents a todo one level (reparent under the previous sibling) with
    /// the FR-072a depth bound enforced by the repository.
    public func indentTodo(blockId: UUID) async {
        guard let todoRepo = environment.persistence.todoRepository,
              let item = try? await todoRepo.fetchTodo(blockId: blockId) else { return }
        let all = (try? await todoRepo.fetchTodos(noteId: noteId)) ?? []
        let siblings = all
            .filter { $0.parentTodoId == item.parentTodoId && $0.id != item.id && $0.sortKey < item.sortKey }
            .sorted { $0.sortKey < $1.sortKey }
        guard let parent = siblings.last else { return }
        let previousParentId = item.parentTodoId
        try? await todoRepo.reparent(todoId: item.id, newParentId: parent.id, deviceId: DeviceIdentity.current.id)
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.reparent(todoId: item.id, newParentId: previousParentId, deviceId: DeviceIdentity.current.id)
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.reparent(todoId: item.id, newParentId: parent.id, deviceId: DeviceIdentity.current.id)
            }
        )
    }

    /// Outdents a todo one level (reparent under its parent's parent).
    public func outdentTodo(blockId: UUID) async {
        guard let todoRepo = environment.persistence.todoRepository,
              let item = try? await todoRepo.fetchTodo(blockId: blockId),
              let parentId = item.parentTodoId else { return }
        let all = (try? await todoRepo.fetchTodos(noteId: noteId)) ?? []
        let parent = all.first { $0.id == parentId }
        try? await todoRepo.reparent(todoId: item.id, newParentId: parent?.parentTodoId, deviceId: DeviceIdentity.current.id)
        registerStructuralUndo(
            restoreOld: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.reparent(todoId: item.id, newParentId: parentId, deviceId: DeviceIdentity.current.id)
            },
            restoreNew: { [weak self] in
                guard let self else { return }
                try? await self.environment.persistence.todoRepository?.reparent(todoId: item.id, newParentId: parent?.parentTodoId, deviceId: DeviceIdentity.current.id)
            }
        )
    }

    // MARK: - Screenshot cover + captions (T292, FR-094/FR-094b)

    /// Sets (or clears) the note's cover screenshot (at most one per note).
    public func setCover(blockId: UUID?, isCover: Bool) async {
        guard var current = note else { return }
        if isCover, let blockId {
            current.coverScreenshotBlockId = blockId
        } else if current.coverScreenshotBlockId == blockId {
            current.coverScreenshotBlockId = nil
        }
        updateAppearance(current)
        // Keep the block payload's isCover flag in sync.
        var updated = blocks
        for index in updated.indices where updated[index].id == blockId {
            if case .screenshot(var payload) = updated[index].payload {
                payload.isCover = isCover
                updated[index] = Block(
                    id: updated[index].id,
                    noteId: updated[index].noteId,
                    kind: updated[index].kind,
                    sortKey: updated[index].sortKey,
                    payload: .screenshot(payload),
                    versionId: updated[index].versionId,
                    parentVersionId: updated[index].parentVersionId,
                    lastModifiedDeviceId: updated[index].lastModifiedDeviceId,
                    createdAt: updated[index].createdAt,
                    modifiedAt: updated[index].modifiedAt
                )
            }
        }
        if !updated.isEmpty { updateBlocks(updated, isStructural: true) }
    }

    /// Persists a screenshot caption edit (FR-093).
    public func updateCaption(blockId: UUID, caption: String?) async {
        var updated = blocks
        for index in updated.indices where updated[index].id == blockId {
            switch updated[index].payload {
            case .screenshot(var payload):
                payload.caption = caption
                updated[index] = Block(
                    id: updated[index].id, noteId: updated[index].noteId,
                    kind: updated[index].kind, sortKey: updated[index].sortKey,
                    payload: .screenshot(payload),
                    versionId: updated[index].versionId, parentVersionId: updated[index].parentVersionId,
                    lastModifiedDeviceId: updated[index].lastModifiedDeviceId,
                    createdAt: updated[index].createdAt, modifiedAt: updated[index].modifiedAt
                )
            case .image(var payload):
                payload.caption = caption
                updated[index] = Block(
                    id: updated[index].id, noteId: updated[index].noteId,
                    kind: updated[index].kind, sortKey: updated[index].sortKey,
                    payload: .image(payload),
                    versionId: updated[index].versionId, parentVersionId: updated[index].parentVersionId,
                    lastModifiedDeviceId: updated[index].lastModifiedDeviceId,
                    createdAt: updated[index].createdAt, modifiedAt: updated[index].modifiedAt
                )
            default:
                break
            }
        }
        if !updated.isEmpty { updateBlocks(updated, isStructural: true) }
    }

    // MARK: - Capture (T293, US7/FR-091)

    /// Captures a screen region into a new screenshot block. The capture
    /// data source is injectable for tests; the default presents the
    /// region-selection overlay (permission prompted only on invocation —
    /// FR-131). `target` places the block at the resolved insertion point
    /// (004 FR-010 — captured up front, degraded to `.append` on stale
    /// contexts per contracts §5).
    public func captureRegion(dataProvider: (@Sendable () async throws -> Data)? = nil, target: InsertionTarget? = nil) async -> Bool {
        await captureScreenshot(dataProvider: dataProvider ?? { try await CaptureFlow.captureRegionPNG() }, target: target)
    }

    /// Captures an application window via the system picker (FR-091).
    public func captureWindow(dataProvider: (@Sendable () async throws -> Data)? = nil, target: InsertionTarget? = nil) async -> Bool {
        await captureScreenshot(dataProvider: dataProvider ?? { try await CaptureFlow.captureWindowPNG() }, target: target)
    }

    private func captureScreenshot(dataProvider: @escaping @Sendable () async throws -> Data, target: InsertionTarget? = nil) async -> Bool {
        guard let assetStore = environment.assets.store else { return false }
        do {
            let png = try await dataProvider()
            let (original, thumbnail) = try await assetStore.importScreenshot(originalData: png, contentType: "public.png")
            let blockId = UUID()
            let previous = blocks
            let newBlocks = blocksApplyingTarget(target ?? .append) { sortKey in
                Block(
                    id: blockId,
                    noteId: noteId,
                    kind: .screenshot,
                    sortKey: sortKey,
                    payload: .screenshot(ScreenshotPayload(
                        originalAssetId: original.id,
                        thumbnailAssetId: thumbnail?.id ?? original.id,
                        applicationName: nil,
                        windowTitle: nil,
                        caption: nil,
                        capturedAt: Date(),
                        isCover: false
                    )),
                    lastModifiedDeviceId: DeviceIdentity.current.id
                )
            }
            updateBlocks(newBlocks, isStructural: true)
            // 004 修复: ONE undo group (block list; imported assets stay in
            // the store — invisible orphans, same as the delete path).
            registerStructuralUndo(
                restoreOld: { [weak self] in self?.updateBlocks(previous, isStructural: true) },
                restoreNew: { [weak self] in self?.updateBlocks(newBlocks, isStructural: true) }
            )
            await flush()
            return true
        } catch {
            return false
        }
    }

    // MARK: - 004 T031 (FR-010): embedded image insertion (new path)

    /// Inserts an image file (user-picked via NSOpenPanel by the caller) as
    /// an `.image` block. The asset pipeline mirrors the screenshot path
    /// (original + thumbnail import — 004 plan §4.3). `target` places the
    /// block at the resolved insertion point.
    @discardableResult
    public func insertImageBlock(url: URL, target: InsertionTarget? = nil) async -> UUID? {
        guard let assetStore = environment.assets.store else { return nil }
        do {
            let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "public.image"
            let data = try Data(contentsOf: url)
            let (original, thumbnail) = try await assetStore.importScreenshot(originalData: data, contentType: contentType)
            let blockId = UUID()
            let previous = blocks
            let newBlocks = blocksApplyingTarget(target ?? .append) { sortKey in
                Block(
                    id: blockId,
                    noteId: noteId,
                    kind: .image,
                    sortKey: sortKey,
                    payload: .image(EmbeddedImagePayload(
                        originalAssetId: original.id,
                        thumbnailAssetId: thumbnail?.id ?? original.id,
                        caption: nil
                    )),
                    lastModifiedDeviceId: DeviceIdentity.current.id
                )
            }
            updateBlocks(newBlocks, isStructural: true)
            // 004 修复: ONE undo group.
            registerStructuralUndo(
                restoreOld: { [weak self] in self?.updateBlocks(previous, isStructural: true) },
                restoreNew: { [weak self] in self?.updateBlocks(newBlocks, isStructural: true) }
            )
            await flush()
            return blockId
        } catch {
            return nil
        }
    }

    /// The note's screenshot payloads, ordered (viewer input — FR-095).
    public func screenshotPayloads() -> [ScreenshotPayload] {
        blocks.compactMap { block in
            if case .screenshot(let payload) = block.payload { return payload }
            return nil
        }
    }

    /// T297 (FR-095): deletes the screenshot block that owns the given
    /// original asset id (viewer "Delete Association"). FR-094b cover
    /// nullification is handled by the persistence layer (FK ON DELETE SET
    /// NULL in the same transaction as the block deletion).
    public func deleteScreenshotBlock(originalAssetId: UUID) async {
        guard let block = blocks.first(where: { block in
            if case .screenshot(let payload) = block.payload {
                return payload.originalAssetId == originalAssetId
            }
            return false
        }) else { return }
        await deleteBlock(id: block.id)
    }

    // MARK: - File-reference actions (T291, FR-100/FR-101/FR-102/FR-103/FR-105)

    /// Evaluates the FR-100 availability of a file-reference block from its
    /// device-local locator (bookmark resolution — balanced start/stop).
    public func fileAvailability(blockId: UUID) async -> FileAvailability {
        guard let locatorRepo = environment.persistence.fileLocatorRepository,
              let locator = try? await locatorRepo.fetch(blockId: blockId) else {
            // No local locator → synchronized metadata only (FR-104).
            return .onAnotherDevice
        }
        let resolution = SecurityScopedBookmarks.resolve(bookmarkData: locator.bookmarkData)
        let availability = FileAvailabilityClassifier.availability(from: resolution)
        // Persist the evaluated state so the card stays truthful after relaunch.
        var updated = locator
        updated.availabilityStatus = availability
        updated.verifiedAt = Date()
        try? await locatorRepo.upsert(updated)
        return availability
    }

    /// Resolves the locator of a block to a file URL (or nil when missing).
    public func fileURL(blockId: UUID) async -> URL? {
        guard let locatorRepo = environment.persistence.fileLocatorRepository,
              let locator = try? await locatorRepo.fetch(blockId: blockId) else { return nil }
        if case .resolved(let url) = SecurityScopedBookmarks.resolve(bookmarkData: locator.bookmarkData) {
            return url
        }
        return nil
    }

    /// Performs a file-reference card action (T291).
    public func performFileAction(blockId: UUID, action: FileReferenceAction) async {
        switch action {
        case .open:
            if let url = await fileURL(blockId: blockId) {
                NSWorkspace.shared.open(url)
            }
        case .reveal:
            if let url = await fileURL(blockId: blockId) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .copyPath:
            if let url = await fileURL(blockId: blockId) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        case .relink:
            await relinkFile(blockId: blockId)
        case .remove:
            await deleteBlock(id: blockId)
        case .move:
            await moveFile(blockId: blockId)
        }
    }

    /// FR-103: relinks a missing/moved file via the open panel.
    private func relinkFile(blockId: UUID) async {
        guard let locatorRepo = environment.persistence.fileLocatorRepository,
              let repo = environment.persistence.noteRepository,
              let locator = try? await locatorRepo.fetch(blockId: blockId) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let newBookmark = try SecurityScopedBookmarks.relink(bookmarkData: locator.bookmarkData, to: url)
            try await locatorRepo.upsert(FileLocator(
                blockId: blockId,
                bookmarkData: newBookmark,
                lastResolvedPath: url.path,
                availabilityStatus: .available,
                stale: false,
                verifiedAt: Date()
            ))
            // Refresh the card's generic metadata (display name/size).
            var updated = blocks
            for index in updated.indices where updated[index].id == blockId {
                if case .fileReference(var payload) = updated[index].payload {
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
                    payload.displayName = url.lastPathComponent
                    payload.approximateSize = values?.fileSize
                    if let type = values?.contentType { payload.contentType = type.identifier }
                    updated[index] = Block(
                        id: updated[index].id, noteId: updated[index].noteId,
                        kind: updated[index].kind, sortKey: updated[index].sortKey,
                        payload: .fileReference(payload),
                        versionId: updated[index].versionId, parentVersionId: updated[index].parentVersionId,
                        lastModifiedDeviceId: updated[index].lastModifiedDeviceId,
                        createdAt: updated[index].createdAt, modifiedAt: updated[index].modifiedAt
                    )
                }
            }
            if !updated.isEmpty { updateBlocks(updated, isStructural: true) }
            _ = repo
        } catch {
            // silent — the card keeps its current state (FR-103)
        }
    }

    /// FR-102: explicit move with destination picker + confirmation +
    /// verify-before-replace.
    private func moveFile(blockId: UUID) async {
        guard let locatorRepo = environment.persistence.fileLocatorRepository,
              let locator = try? await locatorRepo.fetch(blockId: blockId),
              case .resolved(let sourceURL) = SecurityScopedBookmarks.resolve(bookmarkData: locator.bookmarkData) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = String(localized: "Choose a destination folder for the file (it will be moved, not copied).")
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let destination = folder.appendingPathComponent(sourceURL.lastPathComponent)
        guard let sourceIdentity = FileDragOutBridge.identity(of: sourceURL) else { return }
        let destinationIdentity = FileDragOutBridge.identity(of: destination)
        if FileDragOutBridge.decideReplace(source: sourceIdentity, destination: destinationIdentity) != .safeToProceed {
            let alert = NSAlert()
            alert.messageText = String(localized: "A different file already exists at the destination.")
            alert.informativeText = String(localized: "Replace it? The existing file will be overwritten.")
            alert.addButton(withTitle: String(localized: "Replace"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destination)
            guard FileDragOutBridge.verifyMoveCompleted(source: sourceIdentity, movedFile: FileDragOutBridge.identity(of: destination)) else {
                // Verify-before-replace-bookmark: refuse to re-point the
                // bookmark when the move didn't produce the expected file.
                return
            }
            let newBookmark = try SecurityScopedBookmarks.relink(bookmarkData: locator.bookmarkData, to: destination)
            try await locatorRepo.upsert(FileLocator(
                blockId: blockId,
                bookmarkData: newBookmark,
                lastResolvedPath: destination.path,
                availabilityStatus: .available,
                stale: false,
                verifiedAt: Date()
            ))
        } catch {
            // silent — the original file stays in place (FR-102)
        }
    }

    /// Drag-out COPIES the referenced file to the destination (FR-102 —
    /// never moves or deletes the original).
    public func dragOut(blockId: UUID, to destinationFolder: URL) async {
        guard let url = await fileURL(blockId: blockId) else { return }
        let destination = destinationFolder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.copyItem(at: url, to: destination)
    }

    // MARK: - Embedded-image actions (T292, FR-090)

    /// Performs an embedded-image block action.
    public func performEmbeddedImageAction(blockId: UUID, action: EmbeddedImageAction) async {
        guard let block = blocks.first(where: { $0.id == blockId }),
              case .image(let payload) = block.payload,
              let assetStore = environment.assets.store else { return }
        switch action {
        case .view:
            if let data = try? await assetStore.readData(assetID: payload.originalAssetId),
               let image = NSImage(data: data) {
                MediaPresenters.presentImagePreview(title: blockId.uuidString, image: image)
            }
        case .copy:
            if let data = try? await assetStore.readData(assetID: payload.originalAssetId) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setData(data, forType: .png)
            }
        case .saveAs:
            guard let data = try? await assetStore.readData(assetID: payload.originalAssetId) else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "image.png"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        case .remove:
            await deleteBlock(id: blockId)
        }
    }

    /// Returns the embedded image bytes (drag-out from the card).
    public func embeddedImageData(blockId: UUID) async -> Data? {
        guard let block = blocks.first(where: { $0.id == blockId }),
              case .image(let payload) = block.payload,
              let assetStore = environment.assets.store else { return nil }
        return try? await assetStore.readData(assetID: payload.originalAssetId)
    }

    private func reloadBlocks() async {
        guard let repo = environment.persistence.noteRepository else { return }
        self.blocks = (try? await repo.fetchBlocks(noteId: noteId)) ?? blocks
    }

    /// Flushes pending edits and applies the FR-012a auto-discard decision.
    /// Returns `true` when the note MAY be removed (it never contained
    /// meaningful content and still does not); the caller performs the
    /// removal through the repository.
    public func close() async -> Bool {
        // Await the last recorded edit BEFORE flushing, so the debounced
        // draft cannot be registered after flushNow ran (actor race —
        // verified 2026-08-07: typed text was lost on close).
        await pendingEditTask?.value
        await autosave.flushNow()
        tickTask?.cancel()
        // 004 修复: clear the undo stack — NSUndoManager retains its
        // targets, so a non-empty stack would keep the host alive.
        undoManager.removeAllActions()
        guard !hasEverHadMeaningfulContent else { return false }
        return !(note.map { NoteAutoDiscard.hadContent($0, blocks: blocks) } ?? false)
    }


    // MARK: - Save sink (off the main actor)

    /// Persists a block snapshot by diffing against the database:
    /// inserts new blocks, updates existing, deletes removed. Runs on the
    /// AutoSaveDraftManager actor — never on the main actor.
    private static func persistBlocks(
        _ blocks: [Block],
        noteId: UUID,
        environment: AppEnvironment
    ) async {
        guard let repo = environment.persistence.noteRepository else { return }
        do {
            let existing = try await repo.fetchBlocks(noteId: noteId)
            let existingIds = Set(existing.map(\.id))
            let newIds = Set(blocks.map(\.id))
            for id in existingIds.subtracting(newIds) {
                try await repo.delete(id: id)
            }
            for block in blocks {
                if existingIds.contains(block.id) {
                    try await repo.update(block, modifyingDeviceId: DeviceIdentity.current.id)
                } else {
                    try await repo.insert(block)
                }
            }
            // FR-023 (T283): refresh the FTS search document so todo text,
            // code text, file display names, and screenshot captions become
            // searchable (the repository's block writes only keep the
            // title row in sync).
            if let service = environment.persistence.searchService {
                let title = try? await repo.fetch(id: noteId)?.title
                try? await service.reindexNote(noteId: noteId, title: title, blocks: blocks)
            }
            await environment.syncCoordinator?.localContentChanged()
        } catch {
            // FR-141b: background autosave is SILENT — no toast, no spinner.
            // The next debounced write retries; the crash-loss contract is
            // unchanged (completed autosaves are always recovered).
        }
    }
}
