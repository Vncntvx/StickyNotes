import Testing
import Foundation
import AppKit
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Formatting commit tests (004 修复 2026-08-14, Phase 1)
//
// Attribute-only formatting edits never fire `textDidChange` — the
// Coordinator's `applyMarks` must commit the canonical document itself,
// otherwise a ⌘B-then-close loses the mark (autosave never sees it).
// Covered: all five marks commit through one pipeline; the no-selection
// (typing) path creates no content and commits nothing; a mark survives
// the host flush (the window-close path).

@MainActor
@Suite struct FormattingCommitTests {

    /// Captures the canonical documents the editor committed.
    private final class CommitRecorder {
        var documents: [RichTextDocument] = []
    }

    private func makeEditor(
        text: String = "hello world"
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NSTextView, recorder: CommitRecorder) {
        let recorder = CommitRecorder()
        let view = RichTextView(
            document: .plain(text),
            editorTypography: .system(textSize: 13),
            onCommit: { recorder.documents.append($0) },
            undoManager: UndoManager()
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = text
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: text.count, length: 0)
        return (view, coordinator, textView, recorder)
    }

    private func marks(in document: RichTextDocument, scalarRange: Range<Int>) -> Set<RichTextMark> {
        var found: Set<RichTextMark> = []
        for paragraph in document.paragraphs {
            for run in paragraph.runs where run.endScalar > scalarRange.lowerBound && run.startScalar < scalarRange.upperBound {
                found.formUnion(run.marks)
            }
        }
        return found
    }

    @Test
    func selectionBoldCommitsCanonicalWithoutFurtherTyping() {
        let (_, coordinator, textView, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 5)
        let applied = coordinator.applyMarks([.bold], to: textView)
        #expect(applied)
        guard let document = recorder.documents.last else {
            Issue.record("no canonical commit after ⌘B")
            return
        }
        #expect(marks(in: document, scalarRange: 0..<5).contains(.bold),
                "the selection's bold mark must be in the committed canonical document")
        #expect(document.text == "hello world", "formatting must not alter the text")
    }

    @Test
    func italicUnderlineStrikethroughInlineCodeAllCommit() {
        for mark in [RichTextMark.italic, .underline, .strikethrough, .inlineCode] {
            let (_, coordinator, textView, recorder) = makeEditor()
            textView.selectedRange = NSRange(location: 0, length: 5)
            _ = coordinator.applyMarks([mark], to: textView)
            guard let document = recorder.documents.last else {
                Issue.record("no canonical commit for \(mark)")
                return
            }
            #expect(marks(in: document, scalarRange: 0..<5).contains(mark),
                    "\(mark) must commit through the same semantic pipeline")
        }
    }

    @Test
    func typingAttributesOnlyChangeCreatesNoContentAndNoCommit() {
        let (_, coordinator, textView, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 0)
        let applied = coordinator.applyMarks([.bold], to: textView)
        #expect(applied)
        #expect(recorder.documents.isEmpty,
                "the no-selection path must not commit (no content exists yet)")
        let typing = textView.typingAttributes
        #expect((typing[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                "bold lands in typingAttributes for subsequent input")
    }

    @Test
    func boldThenImmediateClosePersistsMark() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard var block = host.blocks.first, case .richText = block.payload else {
            Issue.record("blank note must start with a rich-text block")
            return
        }
        let doc = RichTextDocument.plain("hello world")
        block.payload = .richText(doc)
        host.updateBlocks([block])
        await host.flush()
        // Wire the editor to the host the way RichTextBlockView does.
        let editorView = RichTextView(
            document: doc,
            editorTypography: .system(textSize: 13),
            onCommit: { updated in
                var newBlock = block
                newBlock.payload = .richText(updated)
                host.updateBlocks([newBlock])
            },
            undoManager: host.undoManager
        )
        let coordinator = editorView.makeCoordinator()
        coordinator.parent = editorView
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = doc.text
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.bold], to: textView)
        // Immediate close: flush the pending autosave draft.
        await host.flush()
        let fetched = try await env.persistence.noteRepository!.fetchBlocks(noteId: noteId)
        guard case .richText(let persisted) = fetched.first?.payload else {
            Issue.record("expected a rich-text block")
            return
        }
        #expect(marks(in: persisted, scalarRange: 0..<5).contains(.bold),
                "⌘B followed by an immediate close must persist the mark")
    }

    // MARK: - Clear formatting (2026-08-14: the format bar's eraser button)

    @Test
    func emptyMarksClearSelectionFormatting() {
        let (_, coordinator, textView, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.bold, .italic], to: textView)
        #expect(marks(in: recorder.documents.last!, scalarRange: 0..<5) == [.bold, .italic])

        // Empty marks = clear formatting: everything off, document committed.
        _ = coordinator.applyMarks([], to: textView)
        let cleared = recorder.documents.last!
        #expect(marks(in: cleared, scalarRange: 0..<5).isEmpty,
                "empty marks must clear all semantic marks on the selection")
    }

    @Test
    func emptyMarksClearTypingAttributes() {
        let (_, coordinator, textView, _) = makeEditor()
        // No selection: the typing path accumulates marks for the next input.
        textView.selectedRange = NSRange(location: textView.string.count, length: 0)
        _ = coordinator.applyMarks([.bold], to: textView)
        let before = RichTextMarkApplier.semanticMarks(from: textView.typingAttributes, excludesDisplayStyling: true)
        #expect(before.contains(.bold), "typing path must accumulate the mark")

        _ = coordinator.applyMarks([], to: textView)
        let after = RichTextMarkApplier.semanticMarks(from: textView.typingAttributes, excludesDisplayStyling: true)
        #expect(after.isEmpty, "empty marks must clear the pending typing marks")
    }

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
        )
    }
}
