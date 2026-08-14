import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Typing presentation normalization (PR2 Steps 4-5, 2026-08-14)
//
// Live typing inherits the caret's font family; the canonical plan
// re-segments by script + marks. Without normalization, every content push
// (caretSplit insertion, undo, reopen) visibly re-renders the typed text
// (Bug 2 — proven structural by StructuralInsertionGateTests). These tests
// pin the chosen capture path (NSTextStorageDelegate.didProcessEditing with
// the storage's OWN editedRange — never reconstructed from changeInLength)
// and the canonical equivalence invariant:
//
//   typed presentation == applyDocument presentation == restyle presentation
//
// Core matrix uses an EXPLICIT custom Latin/CJK preference; nil preference
// is the control group (identical by construction).

@MainActor
@Suite struct TypingPresentationNormalizationTests {

    nonisolated private static let mixedTexts = [
        "你好abc",
        "abc你好",
        "你a你a",
        "a你a你",
        "hello 世界 mixed",
    ]

    // MARK: - Harness

    private func makeEditor(
        text: String,
        preference: FontPreference?,
        textSize: CGFloat = 13
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NotePaperTextView) {
        let typography = EditorTypography(fontPreference: preference, textSpacing: .standard, textSize: textSize)
        let view = RichTextView(
            document: .plain(text),
            editorTypography: typography,
            onCommit: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NotePaperTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        coordinator.applyDocument(.plain(text), typography: typography, to: textView)
        return (view, coordinator, textView)
    }

    /// Types text character by character with the caret font inherited —
    /// the real app's typing path (renderTypingAttributes keeps the caret
    /// family; the inserted characters are declared in it).
    private func type(_ text: String, into textView: NSTextView, caretFont: NSFont) {
        textView.typingAttributes[.font] = caretFont
        for scalar in text.unicodeScalars {
            let char = String(scalar)
            let range = textView.selectedRange()
            textView.insertText(char, replacementRange: range)
        }
    }

    private func caretToEnd(_ textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
    }

    private func actualFamilies(_ textView: NSTextView) -> [String] {
        var families: [String] = []
        textView.textStorage?.enumerateAttributes(
            in: NSRange(location: 0, length: textView.textStorage?.length ?? 0), options: []
        ) { attrs, _, _ in
            let font = attrs[.font] as? NSFont
            families.append(font?.familyName ?? "-")
        }
        return families
    }

    private func expectedFamilies(text: String, preference: FontPreference?, textSize: CGFloat) -> [String] {
        let resolver = NoteFontResolver(preference: preference)
        return resolver.segmentedFonts(text: text, size: textSize).map { $0.font.familyName ?? "-" }
    }

    private func lineFragmentHeights(_ textView: NSTextView) -> [CGFloat] {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return [] }
        lm.ensureLayout(for: tc)
        var heights: [CGFloat] = []
        var glyphIndex = 0
        while glyphIndex < lm.numberOfGlyphs {
            var effectiveRange = NSRange(location: 0, length: 0)
            heights.append(lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange).height)
            glyphIndex = NSMaxRange(effectiveRange)
        }
        return heights
    }

    // MARK: - Step 4: capture semantics

    @Test
    func captureUsesStorageEditedRangeAndUnionsPendingEdits() {
        let (_, coordinator, textView) = makeEditor(text: "", preference: nil)
        let storage = textView.textStorage!
        // Two character edits before any consumption — the pending range
        // UNIONS (never last-write-wins, never shrinks).
        coordinator.textStorage(
            storage, didProcessEditing: [.editedCharacters],
            range: NSRange(location: 0, length: 1), changeInLength: 1
        )
        coordinator.textStorage(
            storage, didProcessEditing: [.editedCharacters],
            range: NSRange(location: 1, length: 1), changeInLength: 1
        )
        #expect(coordinator.pendingCharacterEditRange == NSRange(location: 0, length: 2),
                "pending character edits must union (got \(String(describing: coordinator.pendingCharacterEditRange)))")
        // Attribute-only edits (e.g. our own normalization) must not feed
        // the pending range.
        coordinator.textStorage(
            storage, didProcessEditing: [.editedAttributes],
            range: NSRange(location: 5, length: 3), changeInLength: 0
        )
        #expect(coordinator.pendingCharacterEditRange == NSRange(location: 0, length: 2),
                "attribute-only edits must not touch the pending character range")
    }

    @Test
    func deletionLeavesCanonicalState() {
        let (_, _, textView) = makeEditor(text: "你好abc", preference: .systemDefault)
        caretToEnd(textView)
        // Delete the last character across the CJK→Latin boundary.
        let deleted = NSRange(location: (textView.string as NSString).length - 1, length: 1)
        textView.insertText("", replacementRange: deleted)
        let expected = expectedFamilies(text: "你好ab", preference: .systemDefault, textSize: 13)
        #expect(actualFamilies(textView) == expected,
                "a deletion must leave canonical fonts (got \(actualFamilies(textView)) vs \(expected))")
    }

    @Test
    func pastedRangeNormalizesCanonically() {
        let (_, _, textView) = makeEditor(text: "前缀", preference: .systemDefault)
        caretToEnd(textView)
        textView.insertText("hello world", replacementRange: textView.selectedRange())
        let expected = expectedFamilies(text: "前缀hello world", preference: .systemDefault, textSize: 13)
        #expect(actualFamilies(textView) == expected,
                "a paste must normalize to the canonical plan (got \(actualFamilies(textView)) vs \(expected))")
    }

    // MARK: - Step 5: canonical equivalence (custom preference core)

    @Test(arguments: Self.mixedTexts)
    func typingNormalizesToCanonicalPlan(text: String) {
        let (_, _, textView) = makeEditor(text: "", preference: .systemDefault)
        caretToEnd(textView)
        let caretFont = NoteFontResolver(preference: .systemDefault).font(size: 13, for: "")
        type(text, into: textView, caretFont: caretFont)
        let expected = expectedFamilies(text: text, preference: .systemDefault, textSize: 13)
        #expect(actualFamilies(textView) == expected,
                "typed \"\(text)\" must land on the canonical segmented plan (got \(actualFamilies(textView)) vs \(expected))")
    }

    @Test(arguments: Self.mixedTexts)
    func typingMatchesCanonicalLineMetrics(text: String) {
        // Wrap the text so line metrics are actually exercised.
        let wrapped = String(repeating: text + " ", count: 4)
        let (_, _, typedEditor) = makeEditor(text: "", preference: .systemDefault)
        caretToEnd(typedEditor)
        let caretFont = NoteFontResolver(preference: .systemDefault).font(size: 13, for: "")
        type(wrapped, into: typedEditor, caretFont: caretFont)

        // The canonical reference: a document WITH per-segment runs (the
        // shape the model holds after typing + normalization) — NOT
        // `.plain` (whose empty runs render the full-text family rule).
        let resolver = NoteFontResolver(preference: .systemDefault)
        let refAttributed = NSMutableAttributedString(string: wrapped)
        var cursor = 0
        for segment in resolver.segmentedFonts(text: wrapped, size: 13) {
            let length = (segment.segment as NSString).length
            guard length > 0 else { continue }
            refAttributed.addAttribute(.font, value: segment.font, range: NSRange(location: cursor, length: length))
            cursor += length
        }
        let refDocument = RichTextView.Coordinator.canonicalDocument(from: refAttributed)
        let typography = EditorTypography(fontPreference: .systemDefault, textSpacing: .standard, textSize: 13)
        let refView = RichTextView(document: refDocument, editorTypography: typography, onCommit: { _ in })
        let refCoordinator = refView.makeCoordinator()
        refCoordinator.parent = refView
        let canonicalEditor = NotePaperTextView()
        canonicalEditor.isRichText = true
        canonicalEditor.allowsUndo = false
        canonicalEditor.textContainerInset = NSSize(width: 0, height: 0)
        canonicalEditor.textContainer?.lineFragmentPadding = 0
        canonicalEditor.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        canonicalEditor.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        canonicalEditor.delegate = refCoordinator
        canonicalEditor.textStorage?.delegate = refCoordinator
        refCoordinator.applyDocument(refDocument, typography: typography, to: canonicalEditor)

        #expect(lineFragmentHeights(typedEditor) == lineFragmentHeights(canonicalEditor),
                "typed wrapping text must lay out exactly like the canonical render (typed \(lineFragmentHeights(typedEditor)) vs canonical \(lineFragmentHeights(canonicalEditor)))")
    }

    // MARK: - Control group: nil preference (identical by construction)

    @Test(arguments: Self.mixedTexts)
    func typingAtDefaultFontStaysCanonical(text: String) {
        let (_, _, textView) = makeEditor(text: "", preference: nil)
        caretToEnd(textView)
        let caretFont = NoteFontResolver(preference: nil).font(size: 13, for: "")
        type(text, into: textView, caretFont: caretFont)
        let expected = expectedFamilies(text: text, preference: nil, textSize: 13)
        #expect(actualFamilies(textView) == expected,
                "default-font typing must stay canonical (got \(actualFamilies(textView)) vs \(expected))")
    }
}
