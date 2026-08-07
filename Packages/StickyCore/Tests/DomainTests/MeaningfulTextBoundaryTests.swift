import Testing
import Foundation
import Domain

// MARK: - Meaningful-text boundary tests (T212, FR-012a clarified 2026-08-07)
//
// Per tasks.md T212: a note is auto-removable on close ONLY when it has never
// contained meaningful content, where "meaningful content" = (a) at least one
// non-whitespace Unicode character in the title field, OR (b) at least one
// non-whitespace Unicode character in any rich-text block, OR (c) the presence
// of any todo/image/screenshot/code-block/file-reference block regardless of
// text length. Whitespace-only does NOT qualify (spaces, tabs, newlines,
// U+3000 ideographic space, etc.).

@Suite struct MeaningfulTextBoundaryTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000002")!

    // MARK: - Whitespace-only → auto-removable

    @Test
    func whitespaceOnlyTitleAndBodyIsAutoRemovable() {
        let note = Note(title: "   \t\n  ", lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain("  \t\n ")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func ideographicSpaceOnlyIsAutoRemovable() {
        // U+3000 ideographic space is whitespace and does NOT qualify.
        let note = Note(title: "　", lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain("　")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func emptyTitleAndEmptyBodyIsAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }

    // MARK: - Single non-whitespace character → NOT auto-removable

    @Test
    func singleLatinLetterInBodyIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain("a")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func singleCJKCharacterIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain("字")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func singleEmojiIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain("📝")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func singlePunctuationCharacterIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain("!")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func singleNonWhitespaceCharacterInTitleIsNotAutoRemovable() {
        let note = Note(title: "x", lastModifiedDeviceId: Self.deviceId)
        // Even with an empty body, a non-whitespace title character qualifies.
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }

    // MARK: - Structural blocks count as content regardless of text length

    @Test
    func emptyTodoBlockIsNotAutoRemovable() {
        // An empty todo block counts as content (structural block per
        // FR-012a (c)) — even with empty text and no prior version.
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .todo, sortKey: 0,
                          payload: .todo(TodoPayload(todoId: UUID(), richText: .plain(""))),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func emptyCodeBlockIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .code, sortKey: 0,
                          payload: .code(CodePayload(text: "")),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func fileRefBlockIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .fileRef, sortKey: 0,
                          payload: .fileReference(FileReferencePayload(
                            displayName: "f.pdf", contentType: "com.adobe.pdf",
                            originDeviceId: Self.deviceId, addedAt: Date())),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func imageBlockIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .image, sortKey: 0,
                          payload: .image(EmbeddedImagePayload(originalAssetId: UUID(), thumbnailAssetId: UUID())),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    @Test
    func screenshotBlockIsNotAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(noteId: note.id, kind: .screenshot, sortKey: 0,
                          payload: .screenshot(ScreenshotPayload(
                            originalAssetId: UUID(), thumbnailAssetId: UUID(), capturedAt: Date())),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    // MARK: - Previously-content note NOT auto-deleted when emptied (FR-013)

    @Test
    func previouslyContentRichTextNoteEmptiedIsNotAutoDeleted() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let block = Block(
            noteId: note.id, kind: .richText, sortKey: 0,
            payload: .richText(RichTextDocument.plain("")),
            parentVersionId: UUID(),  // had a prior version → had content
            lastModifiedDeviceId: Self.deviceId
        )
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }

    // MARK: - Non-active lifecycle states are never auto-discarded

    @Test
    func trashedNoteIsNeverAutoDiscarded() {
        var note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .trashed
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }

    @Test
    func conflictCopyIsNeverAutoDiscarded() {
        var note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        note.lifecycleState = .conflictCopy
        #expect(!NoteAutoDiscard.shouldAutoDiscard(note, blocks: []))
    }

    // MARK: - Unicode whitespace awareness

    @Test
    func variousUnicodeWhitespaceOnlyIsAutoRemovable() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        // A mix of Unicode whitespace characters: space, tab, newline,
        // U+3000 ideographic space, U+2009 thin space. (U+200B zero-width
        // SPACE is technically NOT whitespace in Swift's Character.isWhitespace,
        // so it's excluded — it would count as a non-whitespace character.)
        let whitespace = " \t\n　 "
        let block = Block(noteId: note.id, kind: .richText, sortKey: 0,
                          payload: .richText(RichTextDocument.plain(whitespace)),
                          lastModifiedDeviceId: Self.deviceId)
        #expect(NoteAutoDiscard.shouldAutoDiscard(note, blocks: [block]))
    }
}
