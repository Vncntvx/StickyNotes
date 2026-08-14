import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Typography / IME safety tests (004 修复 2026-08-14, Phase 1)
//
// FR-063 gap: `textDidChange` skips canonicalization during composition,
// but the model→view pushes (`updateNSView`/`apply`/`push`) had no
// marked-text guard — any SwiftUI update during composition could overwrite
// the marked text (the model string still holds the pre-composition
// version). Phase 1 covers the destructive-push guards for both editors
// and the coordinator-level formatting suppression.

@MainActor
@Suite struct TypographyIMESafetyTests {

    @Test
    func markedTextBlocksRichTextModelPush() {
        let view = RichTextView(
            document: .plain("世界"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = "世界"
        textView.delegate = coordinator
        // Fake an active IME composition: the live string now differs from
        // the model string (which still holds the pre-composition text).
        textView.setMarkedText(
            "你好",
            selectedRange: NSRange(location: 0, length: 2),
            replacementRange: NSRange(location: 0, length: 2)
        )
        #expect(textView.hasMarkedText(), "precondition: marked text active")
        coordinator.applyDocument(.plain("世界"), typography: view.editorTypography, to: textView)
        #expect(textView.string.contains("你好"),
                "a model push during composition must not overwrite the marked text")
        textView.unmarkText()
    }

    @Test
    func markedTextBlocksCodeModelPush() {
        let view = CodeTextView(text: "abc", onCommit: { _ in })
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = false
        textView.string = "abc"
        textView.delegate = coordinator
        textView.setMarkedText(
            "界",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 1, length: 0)
        )
        #expect(textView.hasMarkedText(), "precondition: marked text active")
        coordinator.push(text: "zzz", to: textView)
        #expect(textView.string.contains("界"),
                "a code model push during composition must not overwrite the marked text")
        textView.unmarkText()
    }

    @Test
    func formattingSuppressedDuringCompositionAtCoordinatorLevel() {
        let view = RichTextView(document: .plain("你好"), editorTypography: .system(textSize: 13), onCommit: { _ in })
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.string = "你好"
        textView.delegate = coordinator
        // Select first, THEN install marked text — setSelectedRange after
        // setMarkedText cancels the composition (input-context behavior).
        textView.setSelectedRange(NSRange(location: 0, length: 1))
        textView.setMarkedText(
            "あ",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 1, length: 1)
        )
        #expect(textView.hasMarkedText(), "precondition: marked text active")
        let applied = coordinator.applyMarks([.bold], to: textView)
        #expect(!applied, "no formatting during IME composition (FR-063)")
        textView.unmarkText()
    }

    // MARK: - Typography refresh deferral (Phase 3, 2026-08-14)

    /// A restyle during composition must NOT touch the storage — the
    /// pending value parks until the composition commits.
    @Test
    func typographyChangeDefersDuringComposition() {
        let view = RichTextView(
            document: .plain("hello world"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = "hello world"
        textView.delegate = coordinator
        coordinator.applyDocument(.plain("hello world"), typography: .system(textSize: 13), to: textView)

        textView.setMarkedText(
            "界",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 5, length: 0)
        )
        #expect(textView.hasMarkedText(), "precondition: marked text active")
        let updatedView = RichTextView(
            document: .plain("hello world"),
            editorTypography: EditorTypography(fontPreference: .systemDefault, textSpacing: .standard, textSize: 13),
            onCommit: { _ in }
        )
        coordinator.parent = updatedView
        coordinator.restyleTypographyInPlace(updatedView.editorTypography, document: .plain("hello world"), to: textView)
        let family = (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName
        #expect(family != "Helvetica Neue",
                "the storage font must not change while the composition is active")
        #expect(coordinator.pendingTypography != nil, "the refresh is parked, not dropped")
        textView.unmarkText()
    }

    /// Once the composition commits (textDidChange fires unmarked), the
    /// parked refresh applies exactly once. The parked value is seeded
    /// directly (the defer guard itself is covered by
    /// `typographyChangeDefersDuringComposition`) so the consumption path
    /// is deterministic.
    @Test
    func commitAppliesDeferredRestyle() {
        let view = RichTextView(
            document: .plain("hello world"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = "hello world"
        textView.delegate = coordinator
        coordinator.applyDocument(.plain("hello world"), typography: .system(textSize: 13), to: textView)

        let parked = EditorTypography(fontPreference: .systemDefault, textSpacing: .standard, textSize: 13)
        let parkedView = RichTextView(
            document: .plain("hello world"),
            editorTypography: parked,
            onCommit: { _ in }
        )
        coordinator.parent = parkedView
        coordinator.pendingTypography = parked
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        let family = (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName
        #expect(family == "Helvetica Neue", "the deferred restyle applies after the composition commits")
        #expect(coordinator.pendingTypography == nil, "the pending value is consumed")
    }

    /// Last-write-wins: several changes during one composition park ONLY
    /// the final value (no queueing — one O(n) restyle after the commit).
    @Test
    func pendingKeepsOnlyLatestValue() {
        let view = RichTextView(
            document: .plain("hello world"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in }
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = "hello world"
        textView.delegate = coordinator
        coordinator.applyDocument(.plain("hello world"), typography: .system(textSize: 13), to: textView)

        let first = EditorTypography(fontPreference: .systemDefault, textSpacing: .standard, textSize: 13)
        let second = EditorTypography(
            fontPreference: FontPreference(primaryFamily: "Avenir Next", fallbackFamily: "PingFang SC"),
            textSpacing: .standard,
            textSize: 13
        )
        coordinator.pendingTypography = first   // parked during composition
        coordinator.pendingTypography = second  // overwritten — last wins
        coordinator.parent = RichTextView(
            document: .plain("hello world"),
            editorTypography: second,
            onCommit: { _ in }
        )
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        let family = (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.familyName
        #expect(family == "Avenir Next", "only the LATEST parked value applies (last-write-wins)")
    }
}
