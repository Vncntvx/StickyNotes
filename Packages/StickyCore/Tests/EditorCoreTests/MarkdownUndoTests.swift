import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Markdown single-Undo restoration tests (T070)
//
// Per tasks.md T070: "EditorCore test: single Undo restores exact Markdown
// syntax + formatting; unmatched delimiters ignored; no conversion inside
// code blocks except closing fence."

@Suite struct MarkdownUndoTests {

    @Test
    func undoSourceTextReturnsOriginalVerbatim() {
        // The transformer is stateless; the editor caches the pre-transform
        // text and passes it back through undoSourceText. The transformer
        // returns it verbatim so the editor can restore it on single-Undo.
        let original = "# Hello"
        let restored = MarkdownTransformer.undoSourceText(
            for: .lineLevel(.heading1),
            currentText: "Hello",
            originalText: original
        )
        #expect(restored == original, "single Undo must restore the exact source delimiters")
    }

    @Test
    func undoInlineRestoresExactDelimiters() {
        let original = "**bold**"
        let restored = MarkdownTransformer.undoSourceText(
            for: .inline(.bold, MarkdownInlineRange(startScalar: 0, endScalar: 4)),
            currentText: "bold",
            originalText: original
        )
        #expect(restored == original)
    }

    @Test
    func unmatchedDelimitersProduceNoTransform() {
        // Unmatched delimiters → .none → nothing to undo.
        #expect(MarkdownTransformer.decideInline(text: "hello*", cursorScalarOffset: 6, insideCodeBlock: false, hasIMEComposition: false) == .none)
        #expect(MarkdownTransformer.decideInline(text: "hello**", cursorScalarOffset: 7, insideCodeBlock: false, hasIMEComposition: false) == .none)
        #expect(MarkdownTransformer.decideInline(text: "hello`", cursorScalarOffset: 6, insideCodeBlock: false, hasIMEComposition: false) == .none)
    }

    @Test
    func noConversionInsideCodeBlockExceptClosingFence() {
        // Inside a code block, inline transforms are suppressed.
        #expect(MarkdownTransformer.decideInline(text: "**not bold**", cursorScalarOffset: 12, insideCodeBlock: true, hasIMEComposition: false) == .none)
        // Line-level transforms suppressed too, except the closing fence.
        #expect(MarkdownTransformer.decideLineLevel(line: "# not a heading", insideCodeBlock: true, hasIMEComposition: false) == .none)
        #expect(MarkdownTransformer.decideLineLevel(line: "```", insideCodeBlock: true, hasIMEComposition: false) == .lineLevel(.codeFence))
    }
}
