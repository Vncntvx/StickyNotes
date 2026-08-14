import Testing
import Foundation
import AppKit
import Domain
import EditorCore
@testable import StickyNotes

// MARK: - Block key-command routing tests (2026-08-14)
//
// 删除键的块级路由（doCommand(by:) 拦截）：
// - 空块（todo/code/正文）内任意位置 Backspace 或 Delete → 删除该块
//   （Q2-A 决策；IME 组合期间不拦截，FR-063）；
// - 非空块：仅块首 Backspace → 合并到上一块（Q4-A）；块首 Delete 是
//   普通前向删除，不触发块操作；块中间 Backspace 是普通删除；
// - code 编辑器（CodeTextView.Coordinator）同规则。

@MainActor
@Suite struct BlockKeyCommandRoutingTests {

    private func makeRichTextView(
        document: RichTextDocument,
        onDeleteEmptyBlock: @escaping () -> Void = {},
        onMergeIntoPrevious: @escaping () -> Void = {}
    ) -> (RichTextView.Coordinator, NotePaperTextView) {
        let editor = RichTextView(
            document: document,
            editorTypography: .system(textSize: 13),
            onCommit: { _ in },
            onDeleteEmptyBlock: onDeleteEmptyBlock,
            onMergeIntoPrevious: onMergeIntoPrevious
        )
        let coordinator = RichTextView.Coordinator(editor)
        let textView = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        textView.isRichText = true
        textView.string = document.text
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.delegate = coordinator
        textView.blockKeyHandler = coordinator
        coordinator.attach(textView, bridge: nil, blockId: nil)
        return (coordinator, textView)
    }

    private func makeCodeTextView(
        text: String,
        onDeleteEmptyBlock: @escaping () -> Void = {}
    ) -> (CodeTextView.Coordinator, CodeEditorTextView) {
        let editor = CodeTextView(
            text: text,
            onCommit: { _ in },
            onDeleteEmptyBlock: onDeleteEmptyBlock
        )
        let coordinator = CodeTextView.Coordinator(editor)
        let textView = CodeEditorTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 120))
        textView.isRichText = false
        textView.string = text
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = coordinator
        textView.blockKeyHandler = coordinator
        coordinator.attach(textView)
        return (coordinator, textView)
    }

    // MARK: - Empty block: delete removes the block

    @Test
    func emptyBlockBackspaceDeletesTheBlock() {
        var deleted = false
        let (_, textView) = makeRichTextView(document: .empty, onDeleteEmptyBlock: { deleted = true })
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(deleted, "Backspace in an empty block deletes the block (Q2-A)")
    }

    @Test
    func emptyBlockForwardDeleteDeletesTheBlock() {
        var deleted = false
        let (_, textView) = makeRichTextView(document: .empty, onDeleteEmptyBlock: { deleted = true })
        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        #expect(deleted, "Delete in an empty block deletes the block (Q2-A)")
    }

    @Test
    func emptyCodeBlockBackspaceDeletesTheBlock() {
        var deleted = false
        let (_, textView) = makeCodeTextView(text: "", onDeleteEmptyBlock: { deleted = true })
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(deleted, "code blocks follow the same empty-delete rule")
    }

    // MARK: - Non-empty block: only first-character Backspace merges

    @Test
    func nonEmptyBlockFirstCharacterBackspaceMergesIntoPrevious() {
        var merged = false
        var deleted = false
        let (_, textView) = makeRichTextView(
            document: .plain("body"),
            onDeleteEmptyBlock: { deleted = true },
            onMergeIntoPrevious: { merged = true }
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(merged, "caret at the block start merges into the previous block (Q4-A)")
        #expect(!deleted, "a non-empty block is never deleted by Backspace")
    }

    @Test
    func nonEmptyBlockMidTextBackspaceIsPlainDeletion() {
        var merged = false
        var deleted = false
        let (_, textView) = makeRichTextView(
            document: .plain("body"),
            onDeleteEmptyBlock: { deleted = true },
            onMergeIntoPrevious: { merged = true }
        )
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(!merged && !deleted,
                "mid-text Backspace stays a plain character deletion")
    }

    @Test
    func nonEmptyBlockFirstCharacterForwardDeleteIsPlainDeletion() {
        var merged = false
        var deleted = false
        let (_, textView) = makeRichTextView(
            document: .plain("body"),
            onDeleteEmptyBlock: { deleted = true },
            onMergeIntoPrevious: { merged = true }
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteForward(_:)))
        #expect(!merged && !deleted,
                "Delete at the block start stays a plain forward deletion (only Backspace merges)")
    }

    @Test
    func selectedTextBackspaceStaysPlainDeletion() {
        var merged = false
        let (_, textView) = makeRichTextView(
            document: .plain("body"),
            onMergeIntoPrevious: { merged = true }
        )
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(!merged, "a selection is deleted as text, never merged")
    }

    // MARK: - IME composition suppresses block commands (FR-063)

    @Test
    func imeCompositionSuppressesEmptyBlockDeletion() {
        var deleted = false
        let (_, textView) = makeRichTextView(document: .empty, onDeleteEmptyBlock: { deleted = true })
        textView.setMarkedText("拼", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(!deleted, "block deletion must not fire while the IME is composing (FR-063)")
    }

    @Test
    func imeCompositionSuppressesFirstCharacterMerge() {
        var merged = false
        let (_, textView) = makeRichTextView(
            document: .plain("body"),
            onMergeIntoPrevious: { merged = true }
        )
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setMarkedText("拼", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(!merged, "the merge must not fire while the IME is composing (FR-063)")
    }

    // MARK: - R2.2 cross-block copy (Phase 2, FR-054)

    /// Builds a rich-text view wired to a bridge with an ACTIVE cross-block
    /// selection, capturing the copy callback.
    private func makeCrossBlockCopyFixture() -> (NotePaperTextView, EditorSelectionBridge, () -> CrossBlockSelection?) {
        var copied: CrossBlockSelection?
        let bridge = EditorSelectionBridge(noteId: UUID())
        let editor = RichTextView(
            document: .plain("keep"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in },
            onDeleteSpanningSelection: nil,
            onCopySpanningSelection: { copied = $0 }
        )
        let coordinator = RichTextView.Coordinator(editor)
        let textView = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        textView.isRichText = true
        textView.string = "keep"
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.delegate = coordinator
        textView.blockKeyHandler = coordinator
        coordinator.attach(textView, bridge: bridge, blockId: nil)
        return (textView, bridge, { copied })
    }

    @Test
    func commandCWithCrossBlockSelectionInvokesSpanningCopy() {
        let (textView, bridge, copied) = makeCrossBlockCopyFixture()
        let firstBlock = UUID()
        let secondBlock = UUID()
        // An active cross-block selection covering two blocks.
        bridge.publishCrossBlockSelection(
            CrossBlockSelection(selections: [
                (blockId: firstBlock, range: 0..<4),
                (blockId: secondBlock, range: 0..<2),
            ]),
            focusedBlockId: firstBlock
        )

        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8
        )!
        textView.keyDown(with: event)

        #expect(copied() != nil, "⌘C with a cross-block selection must invoke the spanning copy")
        #expect(copied()?.selections.count == 2, "the full spanning selection is copied")
    }

    @Test
    func commandCWithoutCrossBlockSelectionFallsThroughToSystemCopy() {
        let (textView, _, copied) = makeCrossBlockCopyFixture()
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8
        )!
        textView.keyDown(with: event)
        #expect(copied() == nil, "⌘C without a cross-block selection must NOT intercept (system copy)")
    }
}
