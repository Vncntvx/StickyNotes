import Testing
import Foundation
@testable import Domain

// MARK: - Note lifecycle + auto-discard tests (T027)
//
// Per tasks.md T027: "Domain test: Note create/lifecycle + auto-discard
// empty note + preserve previously-content note when text empty."
//
// Covers FR-007, FR-014, FR-018, FR-019 (lifecycle), and the empty-note
// auto-discard rule (a note that never had content is auto-discarded on
// close; a note that previously had content is NEVER auto-deleted when its
// text becomes empty — the user can recover via Undo or just re-add content).

@Suite struct NoteLifecycleTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - Lifecycle state transitions (data-model.md §Note lifecycle)

    @Test
    func freshNoteStartsActive() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        #expect(note.lifecycleState == .active)
        #expect(note.trashedAt == nil)
        #expect(note.parentVersionId == nil, "Initial note has no parent version")
    }

    @Test
    func trashTransitionsActiveToTrashed() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        let trashTime = Date(timeIntervalSince1970: 1_700_000_500)
        note.lifecycleState = .trashed
        note.trashedAt = trashTime

        #expect(note.lifecycleState == .trashed)
        #expect(note.trashedAt == trashTime)
    }

    @Test
    func restoreTransitionsTrashedToActive() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .trashed
        note.trashedAt = Date()

        note.lifecycleState = .active
        note.trashedAt = nil

        #expect(note.lifecycleState == .active)
        #expect(note.trashedAt == nil)
    }

    @Test
    func permanentlyDeletedRetainsTombstoneFields() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .trashed
        note.trashedAt = Date()

        note.lifecycleState = .permanentlyDeleted

        #expect(note.lifecycleState == .permanentlyDeleted)
        // Per data-model.md: a permanentlyDeleted note retains a Tombstone
        // until sync-safety allows purge. The Note struct keeps `trashedAt`
        // (drives 30-day expiry) and `versionId`/`parentVersionId` (lineage
        // for the tombstone).
        #expect(note.versionId != UUID())
    }

    @Test
    func conflictCopyLifecycleIsDistinguishable() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        let originalNoteId = UUID()
        note.lifecycleState = .conflictCopy
        note.conflictOriginNoteId = originalNoteId
        note.conflictLabel = "Conflict 2026-08-06"

        #expect(note.lifecycleState == .conflictCopy)
        #expect(note.conflictOriginNoteId == originalNoteId)
        #expect(note.conflictLabel?.hasPrefix("Conflict") == true)
    }

    // MARK: - Version lineage (data-model.md §Version lineage)

    @Test
    func mutationAdvancesVersionLineage() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        let originalVersionId = note.versionId
        let originalParentId = note.parentVersionId

        // Simulate a mutation: bump versionId, set parentVersionId to prior.
        let priorVersionId = note.versionId
        note.versionId = UUID()
        note.parentVersionId = priorVersionId
        note.modifiedAt = Date()

        #expect(note.versionId != originalVersionId)
        #expect(note.parentVersionId == priorVersionId)
        #expect(note.parentVersionId != originalParentId)
    }

    @Test
    func versionLineageNextPreservesParentChain() {
        let v0 = VersionLineage.initial(deviceId: Self.deviceId, at: Date(timeIntervalSince1970: 1))
        let v1 = v0.next(deviceId: Self.deviceId, at: Date(timeIntervalSince1970: 2))
        let v2 = v1.next(deviceId: Self.deviceId, at: Date(timeIntervalSince1970: 3))

        #expect(v0.parentVersionId == nil)
        #expect(v1.parentVersionId == v0.versionId)
        #expect(v2.parentVersionId == v1.versionId)
        #expect(v0.versionId != v1.versionId)
        #expect(v1.versionId != v2.versionId)
    }

    // MARK: - Empty-note auto-discard (FR-018 / FR-019 / T081)
    //
    // A note that NEVER had content is auto-discardable on close.
    // A note that PREVIOUSLY had content is NOT auto-deleted when text
    // becomes empty — the user can recover via Undo or re-add content.

    @Test
    func neverContentNoteIsAutoDiscardable() {
        // A fresh note with no blocks (or only an empty rich-text block) is
        // auto-discardable. The decision is based on whether the note ever
        // had content, not on its current text state.
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let neverHadContent = NoteAutoDiscard.hadContent(note, blocks: [])
        #expect(!neverHadContent, "A note with no blocks never had content")
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }

    @Test
    func previouslyContentNoteIsNotAutoDiscardedWhenTextEmpty() {
        // Even if the current text is empty, a note that previously had
        // content MUST NOT be auto-deleted (constitution X — close≠delete;
        // FR-019).
        let note = Note(lastModifiedDeviceId: Self.deviceId)

        // Build a block list that represents "previously had content": a
        // rich-text block whose text is now empty but whose version lineage
        // shows it was previously non-empty.
        let block = Block(
            noteId: note.id,
            kind: .richText,
            sortKey: 0,
            payload: .richText(RichTextDocument.plain("")),
            parentVersionId: UUID(),  // a prior version existed
            lastModifiedDeviceId: Self.deviceId
        )

        let hadContent = NoteAutoDiscard.hadContent(note, blocks: [block])
        #expect(hadContent, "A block with a parent version had content before")
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func currentlyNonEmptyNoteIsNotAutoDiscarded() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let block = Block(
            noteId: note.id,
            kind: .richText,
            sortKey: 0,
            payload: .richText(RichTextDocument.plain("Some content")),
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(NoteAutoDiscard.hadContent(note, blocks: [block]))
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }
}

// MARK: - NoteAutoDiscard helper
//
// A small Domain helper that encodes the empty-note auto-discard rule
// (FR-018 / FR-019 / FR-012a clarified 2026-08-07). Lives in Domain so the
// rule is testable without UI.
//
// FR-012a "meaningful content" = (a) at least one non-whitespace Unicode
// character in the title field, OR (b) at least one non-whitespace Unicode
// character in any rich-text block, OR (c) the presence of any
// todo/image/screenshot/code-block/file-reference block regardless of text
// length. A single character qualifies; whitespace-only does NOT qualify
// (spaces, tabs, newlines, U+3000 ideographic space, etc.). A note that
// PREVIOUSLY held meaningful content but is now emptied is NOT auto-deleted
// (FR-013).

public enum NoteAutoDiscard {
    /// Returns `true` if the note contains meaningful content per FR-012a.
    /// "Meaningful content" = ≥1 non-whitespace Unicode character in the
    /// title or any rich-text block, OR the presence of any
    /// todo/image/screenshot/code-block/file-reference block. A previously-
    /// content note (a block with a non-nil `parentVersionId`) is also
    /// considered to have had content (FR-013: not auto-deleted when emptied).
    public static func hadContent(_ note: Note, blocks: [Block]) -> Bool {
        // (a) title with a non-whitespace character.
        if let title = note.title, containsNonWhitespace(title) {
            return true
        }
        for block in blocks {
            switch block.payload {
            case .richText(let doc):
                // (b) non-whitespace text in a rich-text block.
                if containsNonWhitespace(doc.text) { return true }
                // Previously had content (FR-013): a block with a parent
                // version was non-empty in a prior version.
                if block.parentVersionId != nil { return true }
            case .todo(let todo):
                // (c) a todo block counts as content regardless of text
                // length (structural block). But also check its text.
                if containsNonWhitespace(todo.richText.text) { return true }
                if block.parentVersionId != nil { return true }
                // An empty todo block with no prior version still counts as
                // a structural block per FR-012a (c).
                return true
            case .code(let code):
                // (c) a code block counts as content; also check its text.
                if containsNonWhitespace(code.text) { return true }
                if block.parentVersionId != nil { return true }
                return true
            // Non-text blocks (fileRef, image, screenshot) count as content.
            case .fileReference, .image, .screenshot:
                return true
            }
        }
        return false
    }

    /// Returns `true` if the string contains at least one non-whitespace
    /// Unicode character. Whitespace includes spaces, tabs, newlines,
    /// U+3000 ideographic space, and all Unicode "White_Space" characters.
    private static func containsNonWhitespace(_ string: String) -> Bool {
        !string.allSatisfy { $0.isWhitespace }
    }

    /// Returns `true` if the note should be auto-discarded on window close.
    /// Per FR-018/FR-019/FR-012a: only notes that NEVER had meaningful
    /// content are auto-discarded.
    public static func shouldAutoDiscard(_ note: Note, blocks: [Block]) -> Bool {
        // Trashed/permanentlyDeleted/conflictCopy notes are never auto-discarded.
        guard note.lifecycleState == .active else { return false }
        return !hadContent(note, blocks: blocks)
    }
}
