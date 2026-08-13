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
// - Appearance edits (title/color/opacity/textSize/alwaysOnTop/widgetEligible)
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
    /// 004 修复: insertion-focus request — the newly inserted block's id;
    /// RichTextBlockView makes that editor first responder, then clears it.
    public private(set) var pendingFocusBlockId: UUID?
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
    private var hasEverHadMeaningfulContent = false
    /// 004 修复: serializes undo/redo restore effects — a rapid ⌘Z/⌘⇧Z
    /// sequence must apply its persistence effects in submission order.
    private var pendingUndoTask: Task<Void, Never>?

    public init(noteId: UUID, environment: AppEnvironment) {
        self.noteId = noteId
        self.environment = environment
        let deviceId = DeviceIdentity.current.id
        // The save sink runs on the AutoSaveDraftManager actor (off the main
        // actor). It captures the Sendable environment + note id, never self.
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

    /// The shared undo manager factory (see `undoManager` above).
    private static func makeUndoManager() -> UndoManager {
        UndoManager()
    }

    // MARK: - Loading

    public func load() async {
        guard let repo = environment.persistence.noteRepository else { return }
        do {
            self.note = try await repo.fetch(id: noteId)
            self.blocks = try await repo.fetchBlocks(noteId: noteId)
            self.hasEverHadMeaningfulContent = Self.isMeaningful(note, blocks: blocks)
        } catch {
            self.note = nil
        }
    }

    // MARK: - Editing

    /// Persists an appearance edit immediately (structural op, FR-141a).
    public func updateAppearance(_ updated: Note) {
        let eligibilityChanged = (note?.widgetEligible != updated.widgetEligible)
        self.note = updated
        if Self.isMeaningful(updated, blocks: blocks) {
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
        // FR-110a (T294): widget-eligibility changes refresh eligible kinds.
        if eligibilityChanged {
            WidgetRefreshCoordinator.reload(for: .eligibilityChanged)
        }
    }

    /// Records a block-model change. Text edits debounce (500 ms, FR-141a);
    /// structural changes (todo toggles, block insert/delete/reorder) save
    /// immediately.
    public func updateBlocks(_ newBlocks: [Block], isStructural: Bool = false) {
        StickyLogger(category: .app).debug("host-updateBlocks", code: "fired", sanitizedContext: "count=\(newBlocks.count)")
        self.blocks = newBlocks
        if Self.isMeaningful(note, blocks: newBlocks) {
            hasEverHadMeaningfulContent = true
        }
        let snapshot = newBlocks
        pendingEditTask = Task {
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

    /// Clears the insertion-focus request once the editor handled it.
    public func clearPendingFocusRequest() {
        pendingFocusBlockId = nil
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
        func appendFallback() -> [Block] {
            self.blocks + [makeBlock((self.blocks.map(\.sortKey).max() ?? 0) + 1024)]
        }
        switch target {
        case .append:
            return appendFallback()
        case .afterBlock(let blockId):
            guard let idx = self.blocks.firstIndex(where: { $0.id == blockId }) else {
                return appendFallback()
            }
            let before = blocks[idx].sortKey
            let after = blocks.indices.contains(idx + 1) ? blocks[idx + 1].sortKey : before + 1024
            var updated = blocks
            updated.insert(makeBlock((before + after) / 2), at: idx + 1)
            return updated
        case .caretSplit(let blockId, let offset):
            guard let idx = self.blocks.firstIndex(where: { $0.id == blockId }),
                  case .richText(let doc) = self.blocks[idx].payload else {
                return appendFallback()
            }
            let split = NoteWindowDerivations.splitRichTextBlock(payload: doc, offset: offset)
            let s = blocks[idx].sortKey
            let after = blocks.indices.contains(idx + 1) ? blocks[idx + 1].sortKey : s + 1024
            let trailingSort = (s + after) / 2
            let newSort = (s + trailingSort) / 2
            var updated = blocks
            // The block keeps its id; its payload becomes the LEADING text.
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
            pendingFocusBlockId = blockId
            await flush()
            try await todoRepo.insert(item)
            notifyWidgetRefresh(.todoToggled)
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
        pendingFocusBlockId = blockId
        await flush()
        notifyWidgetRefresh(.noteCreatedEditedDeletedTrashedRestored)
        return blockId
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
            notifyWidgetRefresh(.noteCreatedEditedDeletedTrashedRestored)
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
            notifyWidgetRefresh(.noteCreatedEditedDeletedTrashedRestored)
        } catch {
            // silent (FR-141b: background/structural ops give no toast)
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
        notifyWidgetRefresh(.todoToggled)
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
        notifyWidgetRefresh(.todoToggled)
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
        notifyWidgetRefresh(.todoToggled)
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
        notifyWidgetRefresh(.todoToggled)
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
        notifyWidgetRefresh(.noteCreatedEditedDeletedTrashedRestored)
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
            notifyWidgetRefresh(.noteCreatedEditedDeletedTrashedRestored)
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
            notifyWidgetRefresh(.noteCreatedEditedDeletedTrashedRestored)
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

    // MARK: - Widget refresh (T294, FR-110a)

    private func notifyWidgetRefresh(_ change: WidgetRefreshCoordinator.Change) {
        WidgetRefreshCoordinator.reload(for: change)
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
        return !Self.isMeaningful(note, blocks: blocks)
    }

    // MARK: - FR-012a meaningful-content rule

    /// FR-012a: at least one non-whitespace Unicode character in the title or
    /// any rich-text block, OR the presence of any todo/image/screenshot/
    /// code/file-reference block. Whitespace-only does not qualify.
    public static func isMeaningful(_ note: Note?, blocks: [Block]) -> Bool {
        if let title = note?.title,
           title.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil {
            return true
        }
        for block in blocks {
            switch block.kind {
            case .richText:
                if case .richText(let doc) = block.payload,
                   doc.text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil {
                    return true
                }
            case .todo, .code, .fileRef, .image, .screenshot:
                return true
            }
        }
        return false
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
