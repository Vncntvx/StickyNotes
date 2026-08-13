import Foundation
import Domain

// MARK: - Repository protocols (T021)
//
// Per plan §Module boundaries: Persistence exposes repository protocols;
// concrete DB rows are NOT exported as contracts. Repository protocols
// return `Sendable` snapshots. The App UI depends on these protocols, not
// on concrete DB/provider types.
//
// These protocols are defined in the Persistence module so the App depends
// on them rather than on concrete DB types. The concrete implementations
// (NoteRepository, BlockRepository, etc.) live alongside and conform to
// these protocols.

// MARK: - Note repository protocol

/// Repository for `Note` entities. Returns `Sendable` snapshots — concrete
/// GRDB rows are not exported (plan §Module boundaries).
public protocol NoteRepository: Sendable {
    /// Creates a fresh note with the given initial state. The note starts
    /// active, with a new version lineage.
    func create(_ note: Note) async throws

    /// Fetches a note by id. Returns `nil` if not found.
    func fetch(id: UUID) async throws -> Note?

    /// Fetches all notes matching the given lifecycle state, sorted by the
    /// given key. Used by the menu-bar library (active notes by default,
    /// trashed notes for the Trash view).
    func fetchAll(lifecycle: NoteLifecycleState, sort: NoteSortKey) async throws -> [Note]

    /// Updates a note. Bumps version lineage (sets `parentVersionId` to the
    /// prior `versionId`, generates a new `versionId`, updates `modifiedAt`).
    func update(_ note: Note, modifyingDeviceId: UUID) async throws

    /// Transitions a note to trashed (sets `lifecycleState = .trashed`,
    /// `trashedAt = now`). The note is recoverable for 30 days (FR-014).
    func trash(id: UUID, deviceId: UUID) async throws

    /// Restores a trashed note to active (clears `trashedAt`).
    func restore(id: UUID, deviceId: UUID) async throws

    /// Permanently deletes a note's readable content. Retains a tombstone
    /// for sync-safety (constitution VIII; data-model.md §Tombstone).
    func permanentlyDelete(id: UUID, deviceId: UUID) async throws

    /// Updates the manual sort key for a note (drag reorder). The caller is
    /// responsible for normalizing sort keys via `ManualSortKeys.normalize`
    /// when gaps become too small.
    func updateSortKey(id: UUID, sortKey: Int, deviceId: UUID) async throws

    /// Empty Trash (FR-014b, clarified 2026-08-07): transitions EVERY trashed
    /// note to permanentlyDeleted in a single transaction (no intermediate
    /// observable state), following the permanent-deletion path (readable
    /// local content removed when safe; tombstones retained for sync per
    /// FR-174). The caller MUST confirm with the user first (the confirmation
    /// states immediate permanent deletion + loss of the 30-day guarantee).
    func emptyTrash(deviceId: UUID) async throws -> [UUID]

    /// FR-090b (clarified 2026-08-07): computes the note's structured content
    /// byte count (canonical envelope of note + blocks, before asset
    /// payloads) and throws `StickyError.persistence(.invalidPayload)` when
    /// it exceeds `ScaleLimits.maxNoteContentBytes` (5 MB). Call BEFORE
    /// committing a content change so the last valid saved state is
    /// preserved (refused, not clobbered).
    func validateNoteContentSize(noteId: UUID) async throws
}

/// Sort keys for fetching notes (FR-015).
public enum NoteSortKey: String, Sendable {
    case modified       // modifiedAt DESC (default)
    case created        // createdAt DESC
    case title          // title ASC
    case manual         // manualSortKey ASC
}

// MARK: - Block repository protocol

public protocol BlockRepository: Sendable {
    /// Fetches all blocks for a note, ordered by `sortKey`.
    func fetchBlocks(noteId: UUID) async throws -> [Block]

    /// Inserts a new block at the given sort key. The caller assigns the
    /// sort key (use `ManualSortKeys.insert(between:and:)`).
    func insert(_ block: Block) async throws

    /// Updates a block's payload (and bumps version lineage).
    func update(_ block: Block, modifyingDeviceId: UUID) async throws

    /// Deletes a block. Cascades to TodoItem, ScreenshotAssociation,
    /// FileReference, FileLocator per data-model.md §Constraints.
    func delete(id: UUID) async throws

    /// Reorders a block to a new sort key. The caller is responsible for
    /// normalizing sort keys when gaps become too small.
    func reorder(blockId: UUID, newSortKey: Int, deviceId: UUID) async throws
}

// MARK: - Todo repository protocol

public protocol TodoRepository: Sendable {
    /// Fetches all todos for a note, ordered by `sortKey`.
    func fetchTodos(noteId: UUID) async throws -> [TodoItem]

    /// Fetches the todo for a given block id.
    func fetchTodo(blockId: UUID) async throws -> TodoItem?

    /// Inserts a new todo. Validates hierarchy: parent must be in the same
    /// note; no cycles; depth ≤ maxDepth (data-model.md §TodoItem).
    func insert(_ todo: TodoItem) async throws

    /// Updates a todo's completion state. Identity is stable across text
    /// changes (FR-071).
    func setComplete(todoId: UUID, isComplete: Bool, deviceId: UUID) async throws

    /// Reorders a todo within its note. Reparenting (indent/outdent) is a
    /// separate operation.
    func reorder(todoId: UUID, newSortKey: Int, deviceId: UUID) async throws

    /// Reparents a todo (indent/outdent). Validates no cycles, parent in
    /// same note, depth ≤ maxDepth.
    func reparent(todoId: UUID, newParentId: UUID?, deviceId: UUID) async throws

    /// Deletes a todo. Children are reparented to grandparent (data-model.md
    /// §TodoItem validation).
    func delete(id: UUID) async throws
}

// MARK: - Asset repository protocol

public protocol AssetRepository: Sendable {
    /// Fetches an asset by id.
    func fetch(id: UUID) async throws -> Asset?

    /// Fetches an asset by content hash + kind + contentType (dedup lookup).
    func fetchByContentHash(_ hash: String, kind: AssetKind, contentType: String) async throws -> Asset?

    /// Inserts a new asset. The `storagePath` must point at a file that has
    /// already been written atomically and verified (AssetStore T087).
    func insert(_ asset: Asset) async throws

    /// Marks an asset as synced (remote confirmed) or sets a sync-failure
    /// state (partial-asset sync failure).
    func setSyncState(assetId: UUID, isSynced: Bool, failureState: AssetSyncFailureState) async throws

    /// Deletes an asset row. The AssetStore is responsible for deleting the
    /// underlying file ONLY after reference-count check (data-model.md
    /// §Asset lifecycle).
    func delete(id: UUID) async throws
}
