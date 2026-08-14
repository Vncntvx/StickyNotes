import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Todo first-line metric calibration (PR1 Step 0/1, 2026-08-14)
//
// The todo checkbox aligns to the FIRST LINE's typographic center:
//
//   checkbox center == actual first-line baseline
//                      - (nominalAlignmentFont.ascender + nominalAlignmentFont.descender) / 2
//
// Baseline candidates (TextKit 1):
//   C3a: fragment.minY + layoutManager.location(forGlyphAt: 0).y
//        (location is relative to the line-fragment origin)
//   C3b: fragment.maxY - layoutManager.typesetter.baselineOffset(in:glyphIndex:)
//        (NSTypesetter.baselineOffset = distance from the line-fragment BOTTOM
//         to the baseline — the semantic reference, Apple-documented)
//
// This suite calibrates C3a against C3b, pins the metric formula, and asserts
// the invariant properties: preset-invariance, width-invariance, nominal-font
// independence from first-glyph formatting, and the zero-width guard.
// NO maxAscender-based "ground truth" — the typesetter API is the reference.

@MainActor
@Suite struct TodoFirstLineMetricTests {

    nonisolated private static let texts = [
        "single line todo",
        "这是 todo 内容",
        "hello 世界 mixed",
        "✅ 完成 emoji",
        "line one\nline two\nline three",
    ]

    nonisolated private static let presets: [TextSpacingPreset] = [.compact, .standard, .relaxed]

    // MARK: - Harness

    /// A content-sized NotePaperTextView with the canonical font plan
    /// (full-range base font + per-coverage-segment fonts — the
    /// presentationFontPlan shape) and the preset's paragraph style.
    private func makeEditor(
        text: String,
        spacing: TextSpacingPreset = .standard,
        preference: FontPreference? = nil,
        textSize: CGFloat = 13,
        width: CGFloat = 400
    ) -> (textView: NotePaperTextView, resolver: NoteFontResolver, alignmentFont: NSFont) {
        let resolver = NoteFontResolver(preference: preference)
        let textView = NotePaperTextView()
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 300)
        textView.font = resolver.font(size: textSize, for: text)
        textView.string = text

        let storage = textView.textStorage!
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.font, value: resolver.font(size: textSize, for: text), range: full)
        var utf16Cursor = 0
        for segment in resolver.segmentedFonts(text: text, size: textSize) {
            let length = (segment.segment as NSString).length
            guard length > 0 else { continue }
            storage.addAttribute(.font, value: segment.font, range: NSRange(location: utf16Cursor, length: length))
            utf16Cursor += length
        }
        let typography = EditorTypography(fontPreference: preference, textSpacing: spacing, textSize: textSize)
        if let lineSpacing = typography.lineSpacing {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            storage.addAttribute(.paragraphStyle, value: style, range: full)
        }
        let alignmentFont = resolver.nominalBodyFont(size: textSize)
        return (textView, resolver, alignmentFont)
    }

    private func baselineC3a(_ layoutManager: NSLayoutManager) -> CGFloat {
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        return fragment.minY + layoutManager.location(forGlyphAt: 0).y
    }

    private func baselineC3b(_ layoutManager: NSLayoutManager) -> CGFloat {
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        return fragment.maxY - layoutManager.typesetter.baselineOffset(in: layoutManager, glyphIndex: 0)
    }

    /// The metric formula, evaluated against a given baseline candidate.
    private func formulaCenter(
        _ textView: NotePaperTextView,
        alignmentFont: NSFont,
        baseline: (NSLayoutManager) -> CGFloat
    ) -> CGFloat {
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        return baseline(layoutManager) + textView.textContainerInset.height
            - (alignmentFont.ascender + alignmentFont.descender) / 2
    }

    // MARK: - Step 0: baseline API calibration

    @Test(arguments: Self.texts, Self.presets)
    func c3aMatchesC3bBaseline(text: String, spacing: TextSpacingPreset) {
        let (textView, _, _) = makeEditor(text: text, spacing: spacing)
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let a = baselineC3a(layoutManager)
        let b = baselineC3b(layoutManager)
        #expect(abs(a - b) < 0.5,
                "C3a (\(a)) must agree with the C3b semantic reference (\(b)) for \"\(text)\" @ \(spacing)")
    }

    @Test(arguments: Self.texts)
    func baselineIsWithinFragmentBounds(text: String) {
        let (textView, _, _) = makeEditor(text: text)
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let b = baselineC3b(layoutManager)
        #expect(b >= fragment.minY && b <= fragment.maxY,
                "baseline must sit inside the first line fragment for \"\(text)\"")
    }

    // MARK: - Step 1: metric formula

    @Test(arguments: Self.texts, Self.presets)
    func centerFormulaMatchesC3bReference(text: String, spacing: TextSpacingPreset) {
        let (textView, _, alignmentFont) = makeEditor(text: text, spacing: spacing)
        let actual = textView.firstLineTypographicCenterFromTop(alignmentFont: alignmentFont)
        let expected = formulaCenter(textView, alignmentFont: alignmentFont, baseline: baselineC3b)
        #expect(abs(actual - expected) < 0.5,
                "metric must equal baseline - nominal offset for \"\(text)\" @ \(spacing) (got \(actual) vs \(expected))")
    }

    @Test(arguments: Self.texts)
    func centerIsPresetInvariant(text: String) {
        let nominal = NoteFontResolver(preference: nil).nominalBodyFont(size: 13)
        let compact = makeEditor(text: text, spacing: .compact)
        let standard = makeEditor(text: text, spacing: .standard)
        let relaxed = makeEditor(text: text, spacing: .relaxed)
        let cCompact = compact.textView.firstLineTypographicCenterFromTop(alignmentFont: nominal)
        let cStandard = standard.textView.firstLineTypographicCenterFromTop(alignmentFont: nominal)
        let cRelaxed = relaxed.textView.firstLineTypographicCenterFromTop(alignmentFont: nominal)
        #expect(abs(cStandard - cCompact) < 0.5 && abs(cStandard - cRelaxed) < 0.5,
                "the preset must not move the first-line center (\(cStandard) / \(cCompact) / \(cRelaxed))")
    }

    @Test
    func centerIsWidthInvariant() {
        let text = String(repeating: "这是需要软换行的长文本内容 wrapping text ", count: 4)
        let narrow = makeEditor(text: text, width: 200)
        let wide = makeEditor(text: text, width: 400)
        let nominal = NoteFontResolver(preference: nil).nominalBodyFont(size: 13)
        let narrowCenter = narrow.textView.firstLineTypographicCenterFromTop(alignmentFont: nominal)
        let wideCenter = wide.textView.firstLineTypographicCenterFromTop(alignmentFont: nominal)
        #expect(abs(narrowCenter - wideCenter) < 0.5,
                "wrapping width must not move the first-line center (\(narrowCenter) vs \(wideCenter))")
    }

    /// B semantics: the offset term is the NOMINAL body font's, never the
    /// glyph-0 declared font's. Reformating the first character (bold)
    /// must keep the formula; only a REAL baseline shift may move it.
    @Test(arguments: ["hello 世界", "✅ 完成", "line one\nline two"])
    func centerKeepsNominalOffsetWhenGlyphZeroIsReformatted(text: String) {
        let (textView, _, alignmentFont) = makeEditor(text: text)
        let layoutManager = textView.layoutManager!
        layoutManager.ensureLayout(for: textView.textContainer!)
        let before = textView.firstLineTypographicCenterFromTop(alignmentFont: alignmentFont)

        let storage = textView.textStorage!
        let baseFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? alignmentFont
        let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        storage.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 1))
        layoutManager.ensureLayout(for: textView.textContainer!)

        let after = textView.firstLineTypographicCenterFromTop(alignmentFont: alignmentFont)
        let expected = formulaCenter(textView, alignmentFont: alignmentFont, baseline: baselineC3b)
        #expect(abs(after - expected) < 0.5,
                "the metric must keep the NOMINAL offset when glyph 0 is reformatted (got \(after) vs \(expected))")
        // The formula holds before AND after; only a real baseline shift may move it.
        _ = before
    }

    @Test
    func emptyTextFallsBackToSeedFormula() {
        let resolver = NoteFontResolver(preference: nil)
        let font = resolver.nominalBodyFont(size: 13)
        let textView = NotePaperTextView()
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        let center = textView.firstLineTypographicCenterFromTop(alignmentFont: font)
        let expected = (font.ascender - font.descender) / 2
        #expect(abs(center - expected) < 0.001,
                "the empty fallback must equal the seed formula (\(center) vs \(expected))")
    }

    @Test
    func zeroWidthReturnsSeedFallbackNotFragmentGeometry() {
        let (textView, _, alignmentFont) = makeEditor(text: "hello 世界\nsecond line", width: 0)
        let center = textView.firstLineTypographicCenterFromTop(alignmentFont: alignmentFont)
        let expected = (alignmentFont.ascender - alignmentFont.descender) / 2
        #expect(abs(center - expected) < 0.001,
                "zero-width containers must not publish authoritative geometry (\(center) vs \(expected))")
    }
}
