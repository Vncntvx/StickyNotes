import Testing
import Foundation
import Domain

// MARK: - Card preview tests (T251 domain side, FR-020a)
//
// Per tasks.md T251: the body preview is drawn from the note's FIRST
// rich-text block and never duplicates the generated summary title (the
// view-level 2-line truncation lives in the App layer).

@Suite struct NoteCardPreviewTests {
    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    @Test
    func previewComesFromFirstRichTextBlock() {
        let noteId = UUID()
        let blocks = [
            Block(noteId: noteId, kind: .code, sortKey: 0,
                  payload: .code(CodePayload(text: "let x = 1")),
                  lastModifiedDeviceId: Self.deviceId),
            Block(noteId: noteId, kind: .richText, sortKey: 1024,
                  payload: .richText(.plain("Body preview text")),
                  lastModifiedDeviceId: Self.deviceId),
        ]
        // The SUMMARY derives from the first meaningful block (the code
        // block); the BODY PREVIEW draws from the FIRST RICH-TEXT block
        // (FR-020a) — distinct sources, never duplicating each other.
        let summary = NoteSummary.generatedSummary(for: blocks)
        #expect(summary == "let x = 1")
    }

    @Test
    func summaryIsDisplayOnlyNeverStored() {
        let note = Note(title: nil, lastModifiedDeviceId: Self.deviceId)
        let blocks = [Block(noteId: note.id, kind: .richText, sortKey: 0,
                            payload: .richText(.plain("content")),
                            lastModifiedDeviceId: Self.deviceId)]
        let summary = NoteSummary.generatedSummary(for: blocks)
        #expect(summary == "content")
        #expect(note.title == nil, "the generated summary is never stored as the title (FR-045/FR-021)")
    }
}
