import Foundation
import Observation
import Domain
import EditorCore
import Persistence

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

    let environment: AppEnvironment
    private let autosave: AutoSaveDraftManager
    private var tickTask: Task<Void, Never>?
    /// The most recent edit task. `flush()` awaits it BEFORE flushing so a
    /// debounced edit scheduled from the main actor cannot race the flush
    /// (the edit is always recorded before the flush hop to the actor).
    private var pendingEditTask: Task<Void, Never>?
    private var hasEverHadMeaningfulContent = false

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
    }

    /// Records a block-model change. Text edits debounce (500 ms, FR-141a);
    /// structural changes (todo toggles, block insert/delete/reorder) save
    /// immediately.
    public func updateBlocks(_ newBlocks: [Block], isStructural: Bool = false) {
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

    /// Flushes any pending debounced write now (focus loss, window close,
    /// quit). No-op when nothing is pending. Awaits the last recorded edit
    /// first so a just-scheduled debounced edit cannot be missed.
    public func flush() async {
        await pendingEditTask?.value
        await autosave.flushNow()
    }

    /// Flushes pending edits and applies the FR-012a auto-discard decision.
    /// Returns `true` when the note MAY be removed (it never contained
    /// meaningful content and still does not); the caller performs the
    /// removal through the repository.
    public func close() async -> Bool {
        await autosave.flushNow()
        tickTask?.cancel()
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
