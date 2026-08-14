import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Formatting undo tests (004 修复 2026-08-14, Phase 1)
//
// Formatting goes through the window-level shared UndoManager as SEMANTIC
// mark segments (never raw presentation attributes — a font change between
// ⌘B and ⌘Z must survive the undo). Verified here: bold/italic undo+redo;
// the undo boundary against native typing (⌘B then typing — the first undo
// removes only the typed character); consecutive formatting commands
// reverse one at a time; canonical model and storage stay consistent.

@MainActor
@Suite struct FormattingUndoTests {

    private final class CommitRecorder {
        var documents: [RichTextDocument] = []
    }

    private func makeEditor(
        text: String = "hello world"
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NSTextView, undoManager: UndoManager, recorder: CommitRecorder) {
        let recorder = CommitRecorder()
        let undoManager = UndoManager()
        let view = RichTextView(
            document: .plain(text),
            editorTypography: .system(textSize: 13),
            onCommit: { recorder.documents.append($0) },
            undoManager: undoManager
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = text
        textView.delegate = coordinator
        textView.selectedRange = NSRange(location: text.count, length: 0)
        return (view, coordinator, textView, undoManager, recorder)
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
    func boldUndoRedoRoundTrips() throws {
        let (_, coordinator, textView, undoManager, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.bold], to: textView)
        #expect(marks(in: try #require(recorder.documents.last), scalarRange: 0..<5).contains(.bold))
        undoManager.undo()
        #expect(!marks(in: try #require(recorder.documents.last), scalarRange: 0..<5).contains(.bold),
                "undo removes the bold mark")
        undoManager.redo()
        #expect(marks(in: try #require(recorder.documents.last), scalarRange: 0..<5).contains(.bold),
                "redo restores the bold mark")
    }

    @Test
    func boldThenTypingUndoUndoesTypingFirst() throws {
        let (_, coordinator, textView, undoManager, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.bold], to: textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText("x", replacementRange: textView.selectedRange())
        #expect(textView.string == "hello worldx", "typing landed")
        undoManager.undo()
        #expect(textView.string == "hello world", "the FIRST undo removes only the typed character")
        #expect(marks(in: try #require(recorder.documents.last), scalarRange: 0..<5).contains(.bold),
                "bold survives the typing undo")
        undoManager.undo()
        #expect(!marks(in: try #require(recorder.documents.last), scalarRange: 0..<5).contains(.bold),
                "the SECOND undo removes the bold mark")
    }

    @Test
    func boldThenItalicUndoReversesOneAtATime() throws {
        let (_, coordinator, textView, undoManager, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.bold], to: textView)
        _ = coordinator.applyMarks([.italic], to: textView)
        #expect(marks(in: try #require(recorder.documents.last), scalarRange: 0..<5) == [.bold, .italic])
        undoManager.undo()
        #expect(marks(in: try #require(recorder.documents.last), scalarRange: 0..<5) == [.bold],
                "undo removes ONLY the italic")
        undoManager.undo()
        #expect(marks(in: try #require(recorder.documents.last), scalarRange: 0..<5).isEmpty,
                "the next undo removes the bold")
    }

    @Test
    func undoLeavesStorageAndCanonicalConsistent() throws {
        let (_, coordinator, textView, undoManager, recorder) = makeEditor()
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.bold, .underline], to: textView)
        undoManager.undo()
        let canonical = RichTextView.Coordinator.canonicalDocument(from: textView.attributedString())
        #expect(canonical.text == recorder.documents.last?.text,
                "storage and model hold the same text after undo")
        #expect(marks(in: canonical, scalarRange: 0..<5).isEmpty,
                "storage presentation matches the unformatted canonical after undo")
    }
}
