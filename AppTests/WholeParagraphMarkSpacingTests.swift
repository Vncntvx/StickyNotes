import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Whole-paragraph mark spacing regression (user report 2026-08-14)
//
// Reported: applying ⌘B / ⌘I to a WHOLE paragraph of body text suddenly
// TIGHTENS the paragraph's text spacing; undo restores it; the paragraph
// sits misaligned until the note is resized.
//
// Root cause A (the "紧缩"): RichTextMarkApplier.storageFamilySegments
// reconstructed fonts BY FAMILY NAME (NSFont(name: familyName)) — system /
// CJK UI variant names resolve to a DIFFERENT font (verified: ".PingFang
// UI SC" → Times New Roman, line height 16→13pt). FIXED: the actual font
// object is preserved and traits are added/removed on it.
//
// Root cause B (the "错位 until resize"): attribute-only edits never fire
// didChangeText → the intrinsic content size stays stale → SwiftUI keeps
// the old frame until a width change re-measures it. FIXED: applyMarks /
// restoreFormattingSegments invalidate the intrinsic explicitly.
//
// Undo/redo coverage lives in the FULL-PIPELINE shape
// (SpacingFormattingBugReproTests.wrappingTextBoldKeepsLineMetricsAndSpacing
// — ⌘B+undo+redo on CJK wrapping text with identical line fragments): a
// bare windowless editor exhibits an AppKit CJK font-substitution artifact
// on attribute-edit replays that the production shape does not.

@MainActor
@Suite struct WholeParagraphMarkSpacingTests {

    private let deviceId = UUID(uuidString: "e4000000-0000-4000-8000-000000000004")!

    nonisolated private static let paragraphs = [
        "这是正文第一行 hello world 混排内容\n第二行正文内容",
        "纯中文段落 第二行 第三行",
        "Pure English paragraph with several words\nSecond line here",
    ]

    // MARK: - Harness

    private func makeEditor(
        text: String,
        preference: FontPreference?
    ) -> (coordinator: RichTextView.Coordinator, textView: NotePaperTextView) {
        let typography = EditorTypography(fontPreference: preference, textSpacing: .relaxed, textSize: 13)
        let view = RichTextView(
            document: .plain(text),
            editorTypography: typography,
            onCommit: { _ in },
            undoManager: UndoManager()
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NotePaperTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        // Content-sized (no 320pt paper floor) so the intrinsic reflects
        // the laid-out text — the "错位" symptom depends on that.
        textView.minimumHeight = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.size = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.delegate = coordinator
        textView.textStorage?.delegate = coordinator
        coordinator.applyDocument(.plain(text), typography: typography, to: textView)
        return (coordinator, textView)
    }

    private struct Metrics: CustomStringConvertible, Equatable {
        let paragraphLineSpacing: CGFloat?
        let fontSignatures: [String]
        let fragmentHeights: [CGFloat]
        let intrinsicHeight: CGFloat

        var description: String {
            "paraSpacing=\(String(describing: paragraphLineSpacing)) fonts=\(fontSignatures) fragHeights=\(fragmentHeights) intrinsic=\(intrinsicHeight)"
        }
    }

    private func metrics(of editor: NSTextView) -> Metrics {
        let storage = editor.textStorage!
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        var signatures: [String] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                signatures.append("\(font.familyName ?? "-")/\(font.pointSize)/\(font.fontDescriptor.symbolicTraits.contains(.bold) ? "B" : "")\(font.fontDescriptor.symbolicTraits.contains(.italic) ? "I" : "")")
            }
        }
        let lm = editor.layoutManager!
        lm.ensureLayout(for: editor.textContainer!)
        var heights: [CGFloat] = []
        var glyphIndex = 0
        while glyphIndex < lm.numberOfGlyphs {
            var eff = NSRange(location: 0, length: 0)
            heights.append(lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &eff).height)
            glyphIndex = NSMaxRange(eff)
        }
        return Metrics(
            paragraphLineSpacing: style?.lineSpacing,
            fontSignatures: signatures,
            fragmentHeights: heights,
            intrinsicHeight: editor.intrinsicContentSize.height
        )
    }

    /// "family@size" per run — traits stripped, so bold/italic toggles do
    /// not disturb the comparison.
    private func familiesOnly(_ signatures: [String]) -> [String] {
        signatures.map { sig in
            let parts = sig.split(separator: "/", omittingEmptySubsequences: false)
            let family = parts.count > 0 ? String(parts[0]) : "-"
            let size = parts.count > 1 ? String(parts[1]) : "-"
            return "\(family)@\(size)"
        }
    }

    /// The user-visible invariant: the laid-out line metrics must never
    /// COMPRESS (a face change may legitimately grow a line — e.g.
    /// Helvetica Neue Bold is ~1pt taller — but shrinking is the reported
    /// "紧缩" bug), and no run may land on a foreign fallback family.
    private func assertNoSpacingCompression(
        before: Metrics,
        after: Metrics,
        label: String
    ) {
        let shrink = zip(before.fragmentHeights, after.fragmentHeights).map { $0 - $1 }.max() ?? 0
        #expect(shrink < 1.0,
                "\(label) must not compress the line metrics (before \(before.fragmentHeights) vs after \(after.fragmentHeights), maxShrink\(shrink))")
        #expect(!after.fontSignatures.contains { $0.contains("Times New Roman") },
                "\(label) must never land on a foreign fallback family (got \(after.fontSignatures))")
        #expect(after.paragraphLineSpacing == before.paragraphLineSpacing,
                "\(label) must keep the paragraph spacing (before \(String(describing: before.paragraphLineSpacing)) vs after \(String(describing: after.paragraphLineSpacing)))")
    }

    // MARK: - System font (the user's Default-font scenario)

    @Test(arguments: Self.paragraphs)
    func wholeParagraphBoldAtSystemFontKeepsLineMetrics(text: String) throws {
        let (coordinator, textView) = makeEditor(text: text, preference: nil)
        let before = metrics(of: textView)

        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        #expect(coordinator.applyMarks([.bold], to: textView), "precondition: the mark must apply")
        let after = metrics(of: textView)

        assertNoSpacingCompression(before: before, after: after, label: "system-font ⌘B")
        #expect(after.fontSignatures.allSatisfy { $0.contains("/B") },
                "bold must actually be applied (got \(after.fontSignatures))")
    }

    // MARK: - Named families (strict family preservation)

    @Test(arguments: Self.paragraphs)
    func wholeParagraphBoldKeepsNamedFamilies(text: String) throws {
        let (coordinator, textView) = makeEditor(text: text, preference: .systemDefault)
        let before = metrics(of: textView)

        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        #expect(coordinator.applyMarks([.bold], to: textView), "precondition: the mark must apply")
        let after = metrics(of: textView)

        #expect(familiesOnly(after.fontSignatures) == familiesOnly(before.fontSignatures),
                "⌘B must keep the declared families and sizes for named families (before \(before.fontSignatures) vs after \(after.fontSignatures))")
        assertNoSpacingCompression(before: before, after: after, label: "named-family ⌘B")
        #expect(after.fontSignatures.allSatisfy { $0.contains("/B") },
                "bold must actually be applied (got \(after.fontSignatures))")
    }

    // MARK: - Intrinsic tracks the layout (the "错位 until resize" symptom)

    @Test(arguments: Self.paragraphs)
    func wholeParagraphBoldTracksIntrinsic(text: String) throws {
        let (coordinator, textView) = makeEditor(text: text, preference: nil)
        textView.setSelectedRange(NSRange(location: 0, length: (text as NSString).length))
        #expect(coordinator.applyMarks([.bold], to: textView))
        let intrinsic = textView.intrinsicContentSize.height
        let expected = textView.layoutManager?.usedRect(for: textView.textContainer ?? NSTextContainer()).height ?? 0
        #expect(abs(intrinsic - expected) < 1.5,
                "the intrinsic must track the current layout after ⌘B (got \(intrinsic) vs usedRect \(expected))")
    }
}
