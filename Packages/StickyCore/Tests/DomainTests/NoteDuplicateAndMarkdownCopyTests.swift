import Testing
import Foundation
import Domain

// MARK: - Note duplicate + copy-as-Markdown tests (T247, FR-031)
//
// Per tasks.md T247: "Domain/EditorCore test: note duplicate + copy-as-
// Markdown per FR-031 — duplicating a note yields a new note UUID with
// byte-identical blocks, appearance (color, transparency, text size,
// Always-on-Top), and asset references; copy-as-Markdown serializes blocks
// (rich text with supported marks, todos with nesting/state, code blocks
// with preserved text, file-reference display names, screenshot/image
// captions) into Markdown text with no loss of round-trippable text content".

@Suite struct NoteDuplicateAndMarkdownCopyTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func sampleNoteAndBlocks() -> (Note, [Block]) {
        let note = Note(
            title: "Recipe",
            colorKey: .green,
            transparency: 0.8,
            textSize: 14,
            alwaysOnTop: true,
            lastModifiedDeviceId: Self.deviceId
        )
        let doc = RichTextDocument(
            text: "Mix flour **and** eggs",
            paragraphs: [RichTextParagraph(
                startScalar: 0,
                endScalar: 20,
                style: .body,
                runs: [RichTextRun(startScalar: 10, endScalar: 15, marks: [.bold])]
            )]
        )
        let todoDoc = RichTextDocument.plain("Preheat oven")
        let blocks = [
            Block(id: UUID(uuidString: "b0000000-0000-4000-8000-00000000000a")!, noteId: note.id,
                  kind: .richText, sortKey: 0, payload: .richText(doc),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: UUID(uuidString: "b0000000-0000-4000-8000-00000000000b")!, noteId: note.id,
                  kind: .todo, sortKey: 1024,
                  payload: .todo(TodoPayload(todoId: UUID(uuidString: "c0000000-0000-4000-8000-00000000000a")!, richText: todoDoc)),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: UUID(uuidString: "b0000000-0000-4000-8000-00000000000c")!, noteId: note.id,
                  kind: .code, sortKey: 2048,
                  payload: .code(CodePayload(text: "func f() {\n\treturn 1\n}", language: "swift")),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: UUID(uuidString: "b0000000-0000-4000-8000-00000000000d")!, noteId: note.id,
                  kind: .fileRef, sortKey: 3072,
                  payload: .fileReference(FileReferencePayload(
                      displayName: "notes.md", contentType: "net.daringfireball.markdown",
                      approximateSize: 2048, originDeviceId: Self.deviceId,
                      addedAt: Date(timeIntervalSince1970: 1_700_000_000))),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: UUID(uuidString: "b0000000-0000-4000-8000-00000000000e")!, noteId: note.id,
                  kind: .screenshot, sortKey: 4096,
                  payload: .screenshot(ScreenshotPayload(
                      originalAssetId: UUID(uuidString: "a0000000-0000-4000-8000-00000000000a")!,
                      thumbnailAssetId: UUID(uuidString: "a0000000-0000-4000-8000-00000000000b")!,
                      caption: "step 1", capturedAt: Date(timeIntervalSince1970: 1_700_000_100))),
                  lastModifiedDeviceId: Self.deviceId),
            Block(id: UUID(uuidString: "b0000000-0000-4000-8000-00000000000f")!, noteId: note.id,
                  kind: .image, sortKey: 5120,
                  payload: .image(EmbeddedImagePayload(
                      originalAssetId: UUID(uuidString: "a0000000-0000-4000-8000-00000000000c")!,
                      thumbnailAssetId: UUID(uuidString: "a0000000-0000-4000-8000-00000000000d")!,
                      caption: "logo")),
                  lastModifiedDeviceId: Self.deviceId),
        ]
        return (note, blocks)
    }

    // MARK: - Duplicate note (FR-031)

    @Test
    func duplicateYieldsNewUUIDWithIdenticalContent() {
        let (note, blocks) = sampleNoteAndBlocks()
        let result = NoteDuplicator.duplicate(note, blocks: blocks, deviceId: Self.deviceId)

        #expect(result.note.id != note.id)
        #expect(result.note.title == note.title)
        #expect(result.note.colorKey == note.colorKey)
        #expect(result.note.customColor == note.customColor)
        #expect(result.note.transparency == note.transparency)
        #expect(result.note.textSize == note.textSize)
        #expect(result.note.alwaysOnTop == note.alwaysOnTop)
        #expect(result.note.lifecycleState == .active)
        #expect(result.note.coverScreenshotBlockId == nil, "cover references old block ids")

        #expect(result.blocks.count == blocks.count)
        for (index, original) in blocks.enumerated() {
            let duplicated = result.blocks[index]
            #expect(duplicated.id != original.id)
            #expect(duplicated.noteId == result.note.id)
            #expect(duplicated.kind == original.kind)
            #expect(duplicated.sortKey == original.sortKey)
            #expect(duplicated.payload == original.payload, "block payloads must be byte-identical")
        }
    }

    // MARK: - Copy as Markdown (FR-031)

    @Test
    func markdownSerializesAllBlockKindsWithoutTextLoss() {
        let (note, blocks) = sampleNoteAndBlocks()
        let markdown = NoteMarkdownSerializer.markdown(note: note, blocks: blocks)

        #expect(markdown.contains("# Recipe"), "title becomes a heading")
        #expect(markdown.contains("Mix flour"), "rich text present")
        #expect(markdown.contains("**and**"), "bold mark present")
        #expect(markdown.contains("- [ ] Preheat oven"), "todo with state")
        #expect(markdown.contains("```swift"), "code fence with language")
        #expect(markdown.contains("func f() {\n\treturn 1\n}"), "code text preserved exactly")
        #expect(markdown.contains("notes.md"), "file display name")
        #expect(markdown.contains("step 1"), "screenshot caption")
        #expect(markdown.contains("logo"), "image caption")
    }

    @Test
    func markdownPreservesTodoAndCodeOrdering() {
        let (note, blocks) = sampleNoteAndBlocks()
        let markdown = NoteMarkdownSerializer.markdown(note: note, blocks: blocks)
        let richIndex = markdown.range(of: "Mix flour")!.lowerBound
        let todoIndex = markdown.range(of: "Preheat oven")!.lowerBound
        let codeIndex = markdown.range(of: "func f()")!.lowerBound
        #expect(richIndex < todoIndex)
        #expect(todoIndex < codeIndex)
    }
}
