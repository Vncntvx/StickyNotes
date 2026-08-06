import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Markdown inline transform tests (T069)
//
// Per tasks.md T069: "EditorCore test: inline transforms (bold/italic/
// strike/inline-code) trigger after valid closing delimiter."

@Suite struct MarkdownInlineTransformTests {

    private func decide(_ text: String, cursor: Int? = nil) -> MarkdownTransform {
        let scalars = Array(text.unicodeScalars)
        let c = cursor ?? scalars.count
        return MarkdownTransformer.decideInline(text: text, cursorScalarOffset: c, insideCodeBlock: false, hasIMEComposition: false)
    }

    @Test
    func boldTriggersOnClosingDoubleAsterisk() {
        // "**bold**" — cursor at end.
        let t = decide("**bold**")
        if case .inline(let mark, _) = t {
            #expect(mark == .bold)
        } else {
            Issue.record("expected bold transform, got \(t)")
        }
    }

    @Test
    func boldTriggersOnClosingDoubleUnderscore() {
        let t = decide("__bold__")
        if case .inline(let mark, _) = t {
            #expect(mark == .bold)
        } else {
            Issue.record("expected bold transform, got \(t)")
        }
    }

    @Test
    func italicTriggersOnClosingSingleAsterisk() {
        // "an *em*" — the closing * is at scalar offset 6 (0-based:
        // a=0,n=1,space=2,*=3,e=4,m=5,*=6). The editor fires decideInline
        // right after the user types the closing *, so cursor = 7 (past it).
        let t = MarkdownTransformer.decideInline(text: "an *em*", cursorScalarOffset: 7, insideCodeBlock: false, hasIMEComposition: false)
        if case .inline(let mark, _) = t {
            #expect(mark == .italic)
        } else {
            Issue.record("expected italic transform, got \(t)")
        }
    }

    @Test
    func strikethroughTriggersOnClosingTildes() {
        let t = decide("~~struck~~")
        if case .inline(let mark, _) = t {
            #expect(mark == .strikethrough)
        } else {
            Issue.record("expected strikethrough transform, got \(t)")
        }
    }

    @Test
    func inlineCodeTriggersOnClosingBacktick() {
        let t = decide("`code`")
        if case .inline(let mark, _) = t {
            #expect(mark == .inlineCode)
        } else {
            Issue.record("expected inlineCode transform, got \(t)")
        }
    }

    @Test
    func unmatchedClosingDelimiterDoesNotTransform() {
        // "hello*" — no opening *, so no transform.
        #expect(decide("hello*") == .none)
        // "hello**" — no balanced opening.
        #expect(decide("hello**") == .none)
        // "hello`" — no opening backtick.
        #expect(decide("hello`") == .none)
    }

    @Test
    func emptyEnclosedTextDoesNotTransform() {
        // "****" — empty bold. Not a transform.
        #expect(decide("****") == .none)
        // "``" — empty inline code.
        #expect(decide("``") == .none)
    }

    @Test
    func noInlineTransformInsideCodeBlock() {
        let t = MarkdownTransformer.decideInline(text: "`code`", cursorScalarOffset: 7, insideCodeBlock: true, hasIMEComposition: false)
        #expect(t == .none, "no inline transforms inside a code block (except closing fence)")
    }

    @Test
    func applyInlineRemovesDelimitersAndKeepsEnclosedText() {
        // "**bold**" → "bold", cursor at end of "bold" (offset 4).
        let t = decide("**bold**")
        guard case .inline(let mark, let range) = t else {
            Issue.record("expected inline transform")
            return
        }
        #expect(mark == .bold)
        let (newText, cursor) = MarkdownTransformer.applyInline(mark, range: range, to: "**bold**")
        #expect(newText == "bold")
        #expect(cursor == 4)
    }

    @Test
    func applyStrikethroughRemovesTildes() {
        let t = decide("~~x~~")
        guard case .inline(let mark, let range) = t else {
            Issue.record("expected strikethrough")
            return
        }
        let (newText, _) = MarkdownTransformer.applyInline(mark, range: range, to: "~~x~~")
        #expect(newText == "x")
    }
}
