import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - IME composition safety tests (T071)
//
// Per tasks.md T071: "EditorCore test: no corruption of Chinese IME marked
// text / mixed Chinese-English / emoji / partial syntax."
//
// Constitution V + plan §Markdown transformation: the transformer MUST NOT
// fire while an IME has active marked text. Converting mid-composition
// would corrupt Chinese/CJK input. The `hasIMEComposition` flag is the
// guard; the App layer sets it from the TextEditor/NSTextView marked-range
// state.

@Suite struct IMECompositionTests {

    @Test
    func noLineTransformWhileIMECompositionActive() {
        // A heading prefix typed during an active IME composition must not
        // convert until the composition is confirmed.
        let t = MarkdownTransformer.decideLineLevel(line: "# 标题", insideCodeBlock: false, hasIMEComposition: true)
        #expect(t == .none, "no transform while IME composition is active")
    }

    @Test
    func noInlineTransformWhileIMECompositionActive() {
        let t = MarkdownTransformer.decideInline(text: "**粗体**", cursorScalarOffset: 8, insideCodeBlock: false, hasIMEComposition: true)
        #expect(t == .none)
    }

    @Test
    func transformFiresAfterIMECompositionConfirmed() {
        // Once the IME composition is confirmed (hasIMEComposition = false),
        // the same line converts normally.
        let t = MarkdownTransformer.decideLineLevel(line: "# 标题", insideCodeBlock: false, hasIMEComposition: false)
        #expect(t == .lineLevel(.heading1))
    }

    @Test
    func mixedChineseEnglishHeadingConvertsAfterConfirm() {
        // Mixed CJK + Latin content under a heading prefix.
        let (newLine, _) = MarkdownTransformer.applyLineLevel(.heading1, toLine: "# Mixed 中文 Title")
        #expect(newLine == "Mixed 中文 Title")
    }

    @Test
    func emojiInContentPreservedThroughLineTransform() {
        let (newLine, _) = MarkdownTransformer.applyLineLevel(.bullet, toLine: "- 🚀 launch")
        #expect(newLine == "🚀 launch")
    }

    @Test
    func partialSyntaxDoesNotTransform() {
        // Partial syntax (user is still typing) doesn't match a complete
        // opener. "-" alone (no space + content) is not a bullet.
        #expect(MarkdownTransformer.decideLineLevel(line: "-", insideCodeBlock: false, hasIMEComposition: false) == .none)
        // "#" alone is not a heading (no trailing space).
        #expect(MarkdownTransformer.decideLineLevel(line: "#", insideCodeBlock: false, hasIMEComposition: false) == .none)
    }
}
