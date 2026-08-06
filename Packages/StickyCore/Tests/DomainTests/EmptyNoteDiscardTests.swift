import Testing
import Foundation
import Domain

// MARK: - Empty-note auto-discard tests (T077)
//
// Per tasks.md T077: "Domain test: never-contained-content note auto-
// discardable on close; previously-content note NOT auto-deleted when text
// empty."
//
// NoteAutoDiscard lives in NoteLifecycleTests.swift (added during T027).
// This file adds focused tests for the FR-018/FR-019 invariants and the
// edge cases (todo block emptied, code block emptied, file-ref always
// counts as content).

@Suite struct EmptyNoteDiscardTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    @Test
    func neverContentNoteIsAutoDiscardable() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
        // Also: a single empty rich-text block with no parent version.
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("")), lastModifiedDeviceId: Self.deviceId)
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func previouslyContentRichTextNoteIsNotAutoDiscardedWhenEmpty() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let block = Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(RichTextDocument.plain("")),
            parentVersionId: UUID(),  // had a prior version → had content
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func previouslyContentTodoNoteIsNotAutoDiscardedWhenEmpty() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let block = Block(
            noteId: note.id, kind: .todo, sortKey: 0,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain(""))),
            parentVersionId: UUID(),
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func previouslyContentCodeNoteIsNotAutoDiscardedWhenEmpty() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let block = Block(
            noteId: note.id, kind: .code, sortKey: 0,
            payload: .code(CodePayload(text: "")),
            parentVersionId: UUID(),
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func fileRefBlockCountsAsContent() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let block = Block(
            noteId: note.id, kind: .fileRef, sortKey: 0,
            payload: .fileReference(FileReferencePayload(displayName: "x.pdf", contentType: "com.adobe.pdf", originDeviceId: Self.deviceId, addedAt: Date())),
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func imageAndScreenshotBlocksCountAsContent() {
        let note = Note(lastModifiedDeviceId: Self.deviceId)
        let image = Block(
            noteId: note.id, kind: .image, sortKey: 0,
            payload: .image(EmbeddedImagePayload(originalAssetId: UUID(), thumbnailAssetId: UUID())),
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [image]))

        let screenshot = Block(
            noteId: note.id, kind: .screenshot, sortKey: 0,
            payload: .screenshot(ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: UUID(), capturedAt: Date())),
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [screenshot]))
    }

    @Test
    func trashedNoteIsNeverAutoDiscarded() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .trashed
        // Even with no blocks, a trashed note is never auto-discarded (the
        // user explicitly trashed it; it goes through the 30-day Trash flow).
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }

    @Test
    func permanentlyDeletedAndConflictCopyNotesAreNeverAutoDiscarded() {
        var note = Note(lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .permanentlyDeleted
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
        note.lifecycleState = .conflictCopy
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }
}
