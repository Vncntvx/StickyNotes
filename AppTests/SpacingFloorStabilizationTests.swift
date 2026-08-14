import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Spacing floor stabilization tests (Plan B, 2026-08-14)
//
// USER BUG (debug rounds 1–3, FR-043/043a): with the global Text Spacing at
// Compact/Relaxed, applying ⌘B/⌘I makes the formatted region's line rhythm
// collapse (~16pt → ~13pt at 13pt) even though `.paragraphStyle.lineSpacing`
// never changes. Root cause: the SYSTEM CJK cascade swaps optical faces when
// semantic traits change — Bold CJK resolves to PingFang UIDisplaySC (narrower
// advances, smaller natural line height) instead of the UITextSC face used by
// regular text. `.paragraphStyle` is byte-identical; the FONT metrics move.
//
// Plan B (user decision 2026-08-14): keep the system cascade; write a
// `minimumLineHeight` FLOOR derived from the regular body font's TextKit
// default line height (`NSLayoutManager.defaultLineHeight(for:)` — NOT a
// magic-number table) on the system-default path (`fontPreference == nil`)
// only. The floor is max-semantics: it can only RAISE collapsed fallback
// lines back to the regular rhythm; it never moves regular text (the regular
// natural height IS the floor) and never clamps larger fallbacks (emoji) —
// no `maximumLineHeight` by design. Explicit custom-font typography is
// untouched by design.
//
// Invariant under test: formatting changes marks; typography changes
// presentation — and on the system path the PRESENTATION line rhythm is
// invariant under semantic trait changes.

@MainActor
@Suite struct SpacingFloorStabilizationTests {

    private final class CommitRecorder {
        var documents: [RichTextDocument] = []
    }

    /// The user's real CJK-heavy text (≥5 wrapped lines at 13pt/400pt).
    private static let cjkText = "这是正文的第一句。连续句子，连续句子，连续句子，连续句子。下面开始插入 todo:"

    private static let editorWidth: CGFloat = 400

    // MARK: - Harness

    private func makeEditor(
        text: String = cjkText,
        spacing: TextSpacingPreset = .standard,
        textSize: CGFloat = 13,
        fontPreference: FontPreference? = nil
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NSTextView, recorder: CommitRecorder) {
        let recorder = CommitRecorder()
        let view = RichTextView(
            document: .plain(text),
            editorTypography: EditorTypography(fontPreference: fontPreference, textSpacing: spacing, textSize: textSize),
            onCommit: { recorder.documents.append($0) },
            undoManager: UndoManager()
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = text
        textView.frame = NSRect(x: 0, y: 0, width: Self.editorWidth, height: 600)
        textView.delegate = coordinator
        coordinator.applyDocument(.plain(text), typography: view.editorTypography, to: textView)
        return (view, coordinator, textView, recorder)
    }

    /// The laid-out line fragment heights — the visual "行距" proxy. A
    /// rhythm collapse shows up here even if the raw lineSpacing attribute
    /// survives (the fallback face's metrics shift).
    private func lineFragmentHeights(_ textView: NSTextView) -> [CGFloat] {
        lineFragmentRects(textView).map(\.height)
    }

    /// The line-height VALUE SET, quantized to 0.5pt. Wrapping is allowed
    /// to shift (Bold legitimately changes glyph widths — reflow is by
    /// design), so the invariant is the SET of fragment heights, not the
    /// per-line mapping: TextKit appends `lineSpacing` after every line
    /// EXCEPT the last of a paragraph, so a multi-line paragraph's values
    /// are `[natural+spacing, …, natural]`.
    private func lineHeightSet(_ heights: [CGFloat]) -> Set<CGFloat> {
        Set(heights.map { ($0 * 2).rounded() / 2 })
    }

    private func lineFragmentRects(_ textView: NSTextView) -> [NSRect] {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return [] }
        lm.ensureLayout(for: tc)
        var rects: [NSRect] = []
        var glyphIndex = 0
        while glyphIndex < lm.numberOfGlyphs {
            var effectiveRange = NSRange(location: 0, length: 0)
            let rect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            rects.append(rect)
            glyphIndex = NSMaxRange(effectiveRange)
        }
        return rects
    }

    /// The floor the production path MUST use on the system-default path —
    /// the regular body font's TextKit default line height (no magic table).
    private func expectedFloor(textSize: CGFloat) -> CGFloat {
        let regular = NoteFontResolver(preference: nil).font(size: textSize, for: "")
        return NSLayoutManager().defaultLineHeight(for: regular)
    }

    private func floorStyle(in textView: NSTextView, at index: Int = 0) -> NSParagraphStyle? {
        textView.textStorage?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
    }

    // MARK: - Rhythm stability under marks (RED before Plan B)

    @Test
    func wordAndParagraphBoldKeepLineHeightsAt9_13_24pt() {
        for size in [CGFloat(9), 13, 24] {
            let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed, textSize: size)
            let regularHeights = lineFragmentHeights(textView)
            guard !regularHeights.isEmpty else {
                Issue.record("\(size)pt: the CJK text must lay out into fragments")
                return
            }
            let regularSet = lineHeightSet(regularHeights)
            // Word-level ⌘B: the bolded word's line must keep the rhythm.
            let wordRange = (Self.cjkText as NSString).range(of: "正文")
            textView.setSelectedRange(wordRange)
            _ = coordinator.applyMarks([.bold], to: textView)
            let afterWord = lineFragmentHeights(textView)
            #expect(lineHeightSet(afterWord) == regularSet,
                    "\(size)pt: word-level ⌘B must preserve the regular line-height set (regular \(regularHeights), got \(afterWord))")

            // Whole-paragraph ⌘B (fresh editor — no toggle overlap).
            let (_, paragraphCoordinator, paragraphView, _) = makeEditor(spacing: .relaxed, textSize: size)
            paragraphView.setSelectedRange(NSRange(location: 0, length: (Self.cjkText as NSString).length))
            _ = paragraphCoordinator.applyMarks([.bold], to: paragraphView)
            let afterParagraph = lineFragmentHeights(paragraphView)
            #expect(lineHeightSet(afterParagraph) == regularSet,
                    "\(size)pt: whole-paragraph ⌘B must preserve the regular line-height set (regular \(regularHeights), got \(afterParagraph))")
        }
    }

    @Test
    func italicKeepsLineHeights() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        let regularHeights = lineFragmentHeights(textView)
        guard !regularHeights.isEmpty else {
            Issue.record("the CJK text must lay out into fragments")
            return
        }
        let regularSet = lineHeightSet(regularHeights)
        let wordRange = (Self.cjkText as NSString).range(of: "正文")
        textView.setSelectedRange(wordRange)
        _ = coordinator.applyMarks([.italic], to: textView)
        let afterWord = lineFragmentHeights(textView)
        #expect(lineHeightSet(afterWord) == regularSet,
                "word-level ⌘I must preserve the regular line-height set (regular \(regularHeights), got \(afterWord))")
    }

    // MARK: - Floor composition (RED before Plan B)

    @Test
    func standardPresetWritesFloorOnlyStyleOnSystemPath() {
        let (_, _, textView, _) = makeEditor(spacing: .standard, textSize: 13)
        let floor = expectedFloor(textSize: 13)
        let style = floorStyle(in: textView)
        #expect(style != nil, "the system path writes a floor-only paragraph style (CJK cascade stabilization)")
        #expect(style?.lineSpacing == 0, "standard adds no inter-line delta")
        #expect(style?.minimumLineHeight == floor,
                "the floor is the regular body font's default line height (got \(String(describing: style?.minimumLineHeight)), expected \(floor))")
        let typing = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(typing?.minimumLineHeight == floor, "typing attributes carry the same floor")
        #expect(typing?.lineSpacing == 0, "typing attributes add no inter-line delta")
    }

    @Test
    func typingAttributesCarryTheFloor() {
        let floor = expectedFloor(textSize: 13)
        let (_, _, standardView, _) = makeEditor(spacing: .standard, textSize: 13)
        let standardStyle = standardView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(standardStyle?.minimumLineHeight == floor,
                "standard typing attributes carry the floor (got \(String(describing: standardStyle?.minimumLineHeight)))")
        #expect(standardStyle?.lineSpacing == 0, "standard typing attributes add no delta")

        let (_, _, relaxedView, _) = makeEditor(spacing: .relaxed, textSize: 13)
        let relaxedStyle = relaxedView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(relaxedStyle?.lineSpacing == 4.0 && relaxedStyle?.minimumLineHeight == floor,
                "relaxed typing attributes carry delta + floor (got lineSpacing \(String(describing: relaxedStyle?.lineSpacing)), minHeight \(String(describing: relaxedStyle?.minimumLineHeight)))")
    }

    @Test
    func floorTracksTextSizeFromRegularMetrics() {
        for size in [CGFloat(9), 13, 24] {
            let (_, _, textView, _) = makeEditor(spacing: .standard, textSize: size)
            let floor = expectedFloor(textSize: size)
            let style = floorStyle(in: textView)
            #expect(style?.minimumLineHeight == floor,
                    "\(size)pt: the floor must equal the regular body font's default line height (got \(String(describing: style?.minimumLineHeight)), expected \(floor))")
        }
    }

    // MARK: - Guard rails (must hold with AND without the floor)

    @Test
    func systemRegularTextIsVisuallyUnchangedByFloor() {
        // The floor is max-semantics and equal to the regular natural height
        // — regular text (no marks) must be geometrically identical with and
        // without the floor, wrapping included.
        let (_, _, textView, _) = makeEditor(spacing: .standard, textSize: 13)
        let floored = lineFragmentHeights(textView)

        let control = NSTextView()
        control.isRichText = true
        control.string = Self.cjkText
        control.font = NSFont.systemFont(ofSize: 13)
        control.frame = NSRect(x: 0, y: 0, width: Self.editorWidth, height: 600)
        let controlHeights = lineFragmentHeights(control)

        #expect(floored.count == controlHeights.count,
                "the floor must not change regular-text wrapping (floored \(floored.count) lines vs control \(controlHeights.count))")
        #expect(zip(floored, controlHeights).allSatisfy { abs($0 - $1) < 0.5 },
                "regular-text line geometry must be identical with and without the floor (floored \(floored) vs control \(controlHeights))")
    }

    @Test
    func customFontPathWritesNoFloor() {
        // Explicit custom preference: the floor is system-default-only by
        // design (the custom cascade resolves its own metrics).
        let (_, _, standardView, _) = makeEditor(spacing: .standard, fontPreference: .systemDefault)
        #expect(floorStyle(in: standardView) == nil,
                "custom-font standard writes NO paragraph style")

        let (_, _, relaxedView, _) = makeEditor(spacing: .relaxed, fontPreference: .systemDefault)
        let style = floorStyle(in: relaxedView)
        #expect(style?.lineSpacing == 4.0, "custom-font relaxed keeps the line-spacing delta")
        #expect(style?.minimumLineHeight == 0, "custom-font path never applies the floor")
    }

    @Test
    func emojiAndFallbackLinesNeverClampOrOverlap() {
        let emojiText = "你好 👋 世界，hello 🌟 world，混合 mixed 内容"
        let (_, _, textView, _) = makeEditor(text: emojiText, spacing: .standard, textSize: 13)
        let floor = expectedFloor(textSize: 13)
        let rects = lineFragmentRects(textView)
        #expect(!rects.isEmpty, "the emoji text must lay out into fragments")
        for (index, rect) in rects.enumerated() {
            #expect(rect.height >= floor - 0.5,
                    "line \(index) must never clamp below the floor (height \(rect.height), floor \(floor))")
            if index > 0 {
                #expect(rect.minY >= rects[index - 1].maxY - 0.5,
                        "lines must never overlap (line \(index) minY \(rect.minY) < previous maxY \(rects[index - 1].maxY))")
            }
        }
    }

    @Test
    func floorDoesNotCommitOrChangeCanonicalDocument() {
        let (_, coordinator, textView, recorder) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        _ = coordinator.applyMarks([.bold], to: textView)
        guard let committed = recorder.documents.last else {
            Issue.record("⌘B must commit a canonical document")
            return
        }
        #expect(committed.text == Self.cjkText, "the committed text is byte-identical")
        #expect(committed.paragraphs.allSatisfy { $0.style == .body },
                "the floor never enters the canonical paragraph model")

        // The floored storage canonicalizes identically to a raw storage
        // with the same marks but no paragraph style at all.
        let control = NSTextView()
        control.isRichText = true
        control.string = Self.cjkText
        control.frame = NSRect(x: 0, y: 0, width: Self.editorWidth, height: 600)
        let fullRange = NSRange(location: 0, length: (Self.cjkText as NSString).length)
        control.textStorage?.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: fullRange)
        control.textStorage?.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 0, length: 4))
        let flooredCanonical = RichTextView.Coordinator.canonicalDocument(from: textView.attributedString())
        let controlCanonical = RichTextView.Coordinator.canonicalDocument(from: control.attributedString())
        #expect(flooredCanonical == controlCanonical,
                "the paragraph-style floor must canonicalize identically to no style")
    }
}
