import Testing
import AppKit
@testable import StickyNotes

// MARK: - Code block layout tests (004 修复 2026-08-13, P0-2)
//
// The code editor is content-sized: a single line pays ONE line of height
// (+ insets), not the legacy two-line 44pt floor. The floor that remains is
// exactly one monospaced-13pt line — the empty block's click target.

@MainActor
@Suite struct CodeBlockLayoutTests {

    private let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    /// The font's line height (AppKit metrics: ascender − descender +
    /// leading — NSFont has no `defaultLineHeight`).
    private var lineHeight: CGFloat {
        font.ascender - font.descender + font.leading
    }

    /// One line of content: line height + the vertical text-container insets
    /// (CodeTextView sets width 0 / height 4).
    private var oneLineHeight: CGFloat {
        ceil(lineHeight) + 8
    }

    private func makeEditor(text: String) -> CodeEditorTextView {
        let textView = CodeEditorTextView()
        textView.isRichText = false
        textView.font = font
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 0)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        // A headless NSTextView keeps the container width synced to its
        // (zero) bounds; pin the width explicitly so multi-line content
        // actually lays out. In the app SwiftUI gives the view a real frame.
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text
        return textView
    }

    @Test
    func singleLineHeightTracksContent() {
        let editor = makeEditor(text: "let x = 1")
        let height = editor.intrinsicContentSize.height
        #expect(height < 44, "one line must not pay the legacy two-line floor (44pt), got \(height)")
        #expect(abs(height - oneLineHeight) < 2.5, "one line ≈ content + insets, got \(height)")
    }

    @Test
    func multipleLinesGrowWithContent() {
        let editor = makeEditor(text: "line1\nline2\nline3")
        let height = editor.intrinsicContentSize.height
        let expected = ceil(3 * lineHeight) + 8
        #expect(abs(height - expected) < 3, "three lines ≈ 3×line height + insets, got \(height)")
    }

    @Test
    func shrinkingBackToOneLineReleasesHeight() {
        let editor = makeEditor(text: "line1\nline2\nline3")
        editor.string = "line1"
        editor.invalidateIntrinsicContentSize()
        let height = editor.intrinsicContentSize.height
        #expect(height < 44, "back to one line releases the multi-line height, got \(height)")
        #expect(abs(height - oneLineHeight) < 2.5, "back to one line ≈ content + insets, got \(height)")
    }

    @Test
    func emptyBlockKeepsOneLineClickTarget() {
        let editor = makeEditor(text: "")
        let height = editor.intrinsicContentSize.height
        #expect(height >= oneLineHeight - 1, "the empty block keeps a one-line click target, got \(height)")
        #expect(height < 44, "the empty block no longer reserves two lines, got \(height)")
    }

    // MARK: - Width reflow (Goal A / Test Group A, 2026-08-13)

    /// App-equivalent setup: NO explicit containerSize — the frame drives
    /// the text container (SwiftUI gives the editor a real frame; the app
    /// never pins a container width). Narrowing the frame must reflow the
    /// text and grow the intrinsic height.
    @Test
    func widthChangeReflowsIntrinsicHeight() {
        let editor = CodeEditorTextView()
        editor.isRichText = false
        editor.font = font
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.textContainer?.lineFragmentPadding = 0
        editor.string = String(
            repeating: "let value = 1 + 2 + 3 + 4 + 5 + 6 + 7 ", count: 4
        )
        editor.frame = NSRect(x: 0, y: 0, width: 480, height: 200)
        let wide = editor.intrinsicContentSize.height

        editor.setFrameSize(NSSize(width: 240, height: 200))
        let narrow = editor.intrinsicContentSize.height

        editor.setFrameSize(NSSize(width: 480, height: 200))
        let back = editor.intrinsicContentSize.height

        #expect(narrow > wide + 1,
                "narrowing 480→240 must reflow into more lines: \(wide) → \(narrow)")
        #expect(abs(back - wide) < 2,
                "restoring the width must release the height: \(narrow) → \(back)")
    }
}
