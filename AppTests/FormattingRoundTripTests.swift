import Testing
import Foundation
import AppKit
import Domain
import EditorCore
@testable import StickyNotes

// MARK: - Formatting round-trip tests (004 T008, spec FR-012/FR-053)
//
// Per tasks.md T008: marks applied on an NSTextView (bold/italic/underline/
// strikethrough/inlineCode) must survive the canonical-document round trip;
// the no-selection path applies to typingAttributes (subsequent input);
// IME composition suppresses application (FR-063).

@MainActor
@Suite struct FormattingRoundTripTests {

    private func makeTextView(string: String = "hello world") -> NSTextView {
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = string
        textView.selectedRange = NSRange(location: string.count, length: 0)
        return textView
    }

    private func canonicalMarks(
        of textView: NSTextView,
        in range: NSRange
    ) -> Set<RichTextMark> {
        let doc = RichTextView.Coordinator.canonicalDocument(from: textView.attributedString())
        let scalarRange = range.location..<(range.location + range.length)
        var marks: Set<RichTextMark> = []
        for paragraph in doc.paragraphs {
            for run in paragraph.runs where run.endScalar > scalarRange.lowerBound && run.startScalar < scalarRange.upperBound {
                marks.formUnion(run.marks)
            }
        }
        return marks
    }

    @Test
    func boldRoundTripsThroughCanonicalDocument() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 0, length: 5)
        RichTextMarkApplier.applyMarks([.bold], to: textView)
        #expect(canonicalMarks(of: textView, in: NSRange(location: 0, length: 5)).contains(.bold),
                "bold survives the canonical round trip (FR-053)")
        // Toggle off: applying again removes the mark.
        RichTextMarkApplier.applyMarks([.bold], to: textView)
        #expect(!canonicalMarks(of: textView, in: NSRange(location: 0, length: 5)).contains(.bold),
                "re-applying toggles the mark off")
    }

    @Test
    func italicRoundTripsThroughCanonicalDocument() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 6, length: 5)
        RichTextMarkApplier.applyMarks([.italic], to: textView)
        #expect(canonicalMarks(of: textView, in: NSRange(location: 6, length: 5)).contains(.italic))
    }

    @Test
    func underlineRoundTripsThroughCanonicalDocument() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 0, length: 5)
        RichTextMarkApplier.applyMarks([.underline], to: textView)
        #expect(canonicalMarks(of: textView, in: NSRange(location: 0, length: 5)).contains(.underline))
    }

    @Test
    func strikethroughRoundTripsThroughCanonicalDocument() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 0, length: 5)
        RichTextMarkApplier.applyMarks([.strikethrough], to: textView)
        #expect(canonicalMarks(of: textView, in: NSRange(location: 0, length: 5)).contains(.strikethrough))
    }

    @Test
    func inlineCodeRoundTripsThroughCanonicalDocument() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 0, length: 5)
        RichTextMarkApplier.applyMarks([.inlineCode], to: textView)
        #expect(canonicalMarks(of: textView, in: NSRange(location: 0, length: 5)).contains(.inlineCode),
                "monospaced font maps to the inlineCode mark (FR-053)")
    }

    @Test
    func noSelectionAppliesToTypingAttributes() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 0, length: 0)
        RichTextMarkApplier.applyMarks([.bold, .underline], to: textView)
        let typing = textView.typingAttributes
        #expect((typing[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                "bold lands in typingAttributes (applies to subsequent input)")
        #expect(typing[.underlineStyle] != nil, "underline lands in typingAttributes")

        // Typed text inherits the marks (NSTextView applies typingAttributes
        // to inserted text) and round-trips.
        let typed = NSAttributedString(string: "x", attributes: textView.typingAttributes)
        textView.textStorage?.append(typed)
        let end = textView.string.count
        #expect(canonicalMarks(of: textView, in: NSRange(location: end - 1, length: 1)).contains(.bold))
        #expect(canonicalMarks(of: textView, in: NSRange(location: end - 1, length: 1)).contains(.underline))
    }

    @Test
    func inlineCodeNoSelectionUsesMonospacedTypingFont() {
        let textView = makeTextView()
        textView.selectedRange = NSRange(location: 0, length: 0)
        RichTextMarkApplier.applyMarks([.inlineCode], to: textView)
        let font = textView.typingAttributes[.font] as? NSFont
        let family = font?.familyName ?? ""
        #expect(family.localizedCaseInsensitiveContains("mono") || family.localizedCaseInsensitiveContains("courier"),
                "typing font is monospaced for inlineCode")
    }

    @Test
    func markedTextSuppressesApplication() {
        let textView = makeTextView(string: "你好")
        textView.selectedRange = NSRange(location: 1, length: 1)
        // Fake an active IME composition: setMarkedText installs marked text.
        textView.setMarkedText("あ", selectedRange: NSRange(location: 0, length: 1), replacementRange: textView.selectedRange)
        #expect(textView.hasMarkedText(), "precondition: marked text active")
        RichTextMarkApplier.applyMarks([.bold], to: textView)
        #expect(!canonicalMarks(of: textView, in: NSRange(location: 0, length: 1)).contains(.bold),
                "no format application during IME composition (FR-063)")
        textView.unmarkText()
    }
}
