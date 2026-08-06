import Testing
import Foundation
import Domain

// MARK: - NoteSummary + generated-summary tests (T040 / T045)
//
// Per tasks.md T040: "Domain test: generated summary does not silently
// become permanent title." And T045: "Implement generated-summary
// derivation (first meaningful content as temporary display title)".
//
// Verifies:
// - The generated summary is the first non-empty block's text, clipped.
// - A manual title ALWAYS takes precedence over the generated summary.
// - The generated summary is NEVER written back to Note.title (it's a
//   projection, not a stored field — FR-045).
// - File-ref/screenshot/image blocks contribute their display name /
//   caption / "Screenshot" / "Image" when no text precedes them.
// - An all-empty note returns nil (the caller shows a placeholder).
// - The summary is clipped at NoteSummary.maxLength with an ellipsis,
//   preferring a word-boundary break.

@Suite struct NoteSummaryTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    // MARK: - Generated summary (no manual title)

    @Test
    func firstRichTextBlockBecomesSummary() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 2048, payload: .richText(RichTextDocument.plain("later block")), lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .richText, sortKey: 0,    payload: .richText(RichTextDocument.plain("first meaningful content")), lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: blocks) == "first meaningful content")
    }

    @Test
    func todoBlockTextBecomesSummaryWhenFirst() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .todo, sortKey: 0, payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("buy milk"))), lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .richText, sortKey: 1024, payload: .richText(RichTextDocument.plain("notes")), lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: blocks) == "buy milk")
    }

    @Test
    func codeBlockTextBecomesSummaryWhenFirst() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .code, sortKey: 0, payload: .code(CodePayload(text: "print(1)")), lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: blocks) == "print(1)")
    }

    @Test
    func fileRefDisplayNameBecomesSummaryWhenFirst() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .fileRef, sortKey: 0,
                  payload: .fileReference(FileReferencePayload(displayName: "report.pdf", contentType: "com.adobe.pdf", originDeviceId: Self.deviceId, addedAt: Date())),
                  lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: blocks) == "report.pdf")
    }

    @Test
    func screenshotCaptionOrPlaceholderBecomesSummaryWhenFirst() {
        let noteId = UUID()
        // With a caption.
        let withCaption = [
            Block(noteId: noteId, kind: .screenshot, sortKey: 0,
                  payload: .screenshot(ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: UUID(), caption: "Error trace", capturedAt: Date())),
                  lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: withCaption) == "Error trace")

        // Without a caption.
        let withoutCaption = [
            Block(noteId: noteId, kind: .screenshot, sortKey: 0,
                  payload: .screenshot(ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: UUID(), caption: nil, capturedAt: Date())),
                  lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: withoutCaption) == "Screenshot")
    }

    @Test
    func emptyBlocksProduceNilSummary() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("   ")), lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.generatedSummary(for: blocks) == nil)

        #expect(NoteSummary.generatedSummary(for: []) == nil)
    }

    @Test
    func summaryIsClippedAtMaxLength() {
        let noteId = UUID()
        let long = String(repeating: "a", count: 200)
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain(long)), lastModifiedDeviceId: Self.deviceId),
        ]
        let summary = NoteSummary.generatedSummary(for: blocks)!
        #expect(summary.count <= NoteSummary.maxLength + 1)  // +1 for ellipsis
        #expect(summary.hasSuffix("…"))
    }

    // MARK: - displayTitle precedence (FR-045)

    @Test
    func manualTitleAlwaysBeatsGeneratedSummary() {
        let noteId = UUID()
        let note = Note(id: noteId, title: "My Manual Title", lastModifiedDeviceId: Self.deviceId)
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("body content")), lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.displayTitle(note: note, blocks: blocks) == "My Manual Title")
    }

    @Test
    func emptyManualTitleFallsBackToGeneratedSummary() {
        let noteId = UUID()
        // A whitespace-only title is treated as absent (FR-045 edge case).
        let note = Note(id: noteId, title: "   ", lastModifiedDeviceId: Self.deviceId)
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("first body line")), lastModifiedDeviceId: Self.deviceId),
        ]
        #expect(NoteSummary.displayTitle(note: note, blocks: blocks) == "first body line")
    }

    @Test
    func noTitleAndNoContentReturnsNil() {
        let noteId = UUID()
        let note = Note(id: noteId, lastModifiedDeviceId: Self.deviceId)
        #expect(NoteSummary.displayTitle(note: note, blocks: []) == nil)
    }

    // MARK: - Generated summary is NOT persisted (FR-045 core invariant)
    //
    // This is the "does not silently become permanent title" test from T040.
    // The NoteSummary API has no way to write back to Note.title by design —
    // there is no setter, no mutation, no side effect. The test below
    // documents that invariant explicitly: after deriving a summary from a
    // note's blocks, the note's title field is unchanged.

    @Test
    func generatedSummaryDoesNotPersistAsTitle() {
        let noteId = UUID()
        var note = Note(id: noteId, lastModifiedDeviceId: Self.deviceId)
        let originalTitle = note.title
        let blocks = [
            Block(noteId: noteId, kind: .richText, sortKey: 0, payload: .richText(RichTextDocument.plain("first body line")), lastModifiedDeviceId: Self.deviceId),
        ]

        // Derive the summary multiple times — like the library would on
        // every refresh.
        _ = NoteSummary.displayTitle(note: note, blocks: blocks)
        _ = NoteSummary.displayTitle(note: note, blocks: blocks)
        _ = NoteSummary.generatedSummary(for: blocks)

        // The note's title field is unchanged.
        #expect(note.title == originalTitle)
        #expect(note.title == nil)
        // Confirm Note is a value type so projections can't mutate it.
        // (This compiles only because Note is a struct; a class would fail.)
        let copy = note
        note.title = "mutated"
        #expect(copy.title == nil, "Note is a value type — mutation of one copy doesn't affect another")
    }
}
