import Testing
import Foundation
import Domain
@testable import EditorCore

// MARK: - Markdown line-level transform tests (T068)
//
// Per tasks.md T068: "EditorCore test: line-level transforms (heading/
// bullet/todo/code-fence) trigger on space/confirm."

@Suite struct MarkdownLineTransformTests {

    @Test
    func headingOneTriggersOnSpace() {
        let t = MarkdownTransformer.decideLineLevel(line: "# Hello", insideCodeBlock: false, hasIMEComposition: false)
        #expect(t == .lineLevel(.heading1))
    }

    @Test
    func headingTwoAndThreeTrigger() {
        #expect(MarkdownTransformer.decideLineLevel(line: "## Sub", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.heading2))
        #expect(MarkdownTransformer.decideLineLevel(line: "### Deep", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.heading3))
    }

    @Test
    func headingWithoutTrailingSpaceDoesNotTrigger() {
        // "#Word" (no space) is not a heading per Markdown.
        let t = MarkdownTransformer.decideLineLevel(line: "#Word", insideCodeBlock: false, hasIMEComposition: false)
        #expect(t == .none)
    }

    @Test
    func bulletTriggersWithDashOrAsterisk() {
        #expect(MarkdownTransformer.decideLineLevel(line: "- item", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.bullet))
        #expect(MarkdownTransformer.decideLineLevel(line: "* item", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.bullet))
    }

    @Test
    func todoShortcutTriggers() {
        #expect(MarkdownTransformer.decideLineLevel(line: "- [ ] task", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.todo))
        #expect(MarkdownTransformer.decideLineLevel(line: "- [x] done", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.todo))
        #expect(MarkdownTransformer.decideLineLevel(line: "* [ ] task", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.todo))
    }

    @Test
    func codeFenceTriggersOnBackticks() {
        #expect(MarkdownTransformer.decideLineLevel(line: "```", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.codeFence))
        // With a language label.
        #expect(MarkdownTransformer.decideLineLevel(line: "```swift", insideCodeBlock: false, hasIMEComposition: false) == .lineLevel(.codeFence))
    }

    @Test
    func closingFenceTriggersInsideCodeBlock() {
        #expect(MarkdownTransformer.decideLineLevel(line: "```", insideCodeBlock: true, hasIMEComposition: false) == .lineLevel(.codeFence))
    }

    @Test
    func noTransformInsideCodeBlockExceptClosingFence() {
        // Inside a code block, "# Heading" is literal code, not a heading.
        #expect(MarkdownTransformer.decideLineLevel(line: "# not a heading", insideCodeBlock: true, hasIMEComposition: false) == .none)
        #expect(MarkdownTransformer.decideLineLevel(line: "- not a bullet", insideCodeBlock: true, hasIMEComposition: false) == .none)
    }

    @Test
    func applyLineLevelRemovesPrefix() {
        let (line, cursor) = MarkdownTransformer.applyLineLevel(.heading1, toLine: "# Hello")
        #expect(line == "Hello")
        #expect(cursor == 5)

        let (bullet, _) = MarkdownTransformer.applyLineLevel(.bullet, toLine: "- item")
        #expect(bullet == "item")

        let (todo, _) = MarkdownTransformer.applyLineLevel(.todo, toLine: "- [ ] buy milk")
        #expect(todo == "buy milk")

        let (fence, _) = MarkdownTransformer.applyLineLevel(.codeFence, toLine: "```swift")
        #expect(fence == "")
    }

    @Test
    func noTransformForOrdinaryText() {
        #expect(MarkdownTransformer.decideLineLevel(line: "just text", insideCodeBlock: false, hasIMEComposition: false) == .none)
    }
}
