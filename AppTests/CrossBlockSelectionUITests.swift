import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Cross-block selection UI tests (2026-08-14)
//
// ⌘A 整篇全选与跨块选区的交互层：
// - 富文本块（正文/todo）⌘A → 所有非空块全文选中 + bridge 进入跨块模式
//   （Q8-B：code 块内 ⌘A 仍是块内全选——CodeEditorTextView 不拦截）；
// - 跨块模式下的新选区/编辑退出模式并折叠其他块的残留高亮；
// - 跨块格式（格式条/⌘B）应用到每个选中块；
// - 跨块模式下输入字符 = 替换跨块选区（聚焦块收字符、其他块删空）；
// - 跨块模式下 Backspace = 走 host 的跨块删除（deleteSpanningSelection）。

@MainActor
@Suite struct CrossBlockSelectionUITests {

    private struct Editor {
        let coordinator: RichTextView.Coordinator
        let textView: NotePaperTextView
        let blockId: UUID
    }

    /// NSTextView's input-client path (`insertText(_:replacementRange:)`)
    /// requires a window — the typing-replacement test hosts its editors in
    /// probe windows.
    private func makeHostedEditor(
        text: String,
        bridge: EditorSelectionBridge,
        blockId: UUID
    ) -> (Editor, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let editor = makeEditor(text: text, bridge: bridge, blockId: blockId)
        window.contentView = editor.textView
        window.makeKeyAndOrderFront(nil)
        return (editor, window)
    }

    private func makeEditor(
        text: String,
        bridge: EditorSelectionBridge,
        blockId: UUID,
        onSelectAllInNote: @escaping () -> Void = {},
        onDeleteSpanningSelection: @escaping () -> Void = {}
    ) -> Editor {
        let editor = RichTextView(
            document: .plain(text),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in },
            onSelectAllInNote: onSelectAllInNote,
            onDeleteSpanningSelection: onDeleteSpanningSelection
        )
        let coordinator = RichTextView.Coordinator(editor)
        let textView = NotePaperTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        textView.isRichText = true
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.delegate = coordinator
        textView.blockKeyHandler = coordinator
        coordinator.attach(textView, bridge: bridge, blockId: blockId)
        EditorRegistry.register(textView, for: blockId)
        return Editor(coordinator: coordinator, textView: textView, blockId: blockId)
    }

    private func makeBlocks(_ texts: [String]) -> [Block] {
        texts.enumerated().map { index, text in
            Block(
                noteId: UUID(),
                kind: .richText,
                sortKey: index * 1024,
                payload: .richText(.plain(text)),
                lastModifiedDeviceId: UUID()
            )
        }
    }

    // MARK: - ⌘A note-wide selection

    @Test
    func selectAllSelectsEveryNonEmptyBlockAndPublishesMode() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks(["Hello", "world"])
        let a = makeEditor(text: "Hello", bridge: bridge, blockId: blocks[0].id)
        let b = makeEditor(text: "world", bridge: bridge, blockId: blocks[1].id)
        bridge.attach(textView: a.textView, blockId: blocks[0].id)

        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)

        #expect(a.textView.selectedRange() == NSRange(location: 0, length: 5),
                "the focused block selects its whole text")
        #expect(b.textView.selectedRange() == NSRange(location: 0, length: 5),
                "every block selects its whole text (⌘A = the whole note)")
        #expect(bridge.crossBlockSelection?.selections.count == 2)
        #expect(bridge.isTextSelected)
        #expect(bridge.hasFocus)
    }

    @Test
    func selectAllOnEmptyNoteStaysEmpty() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks([""])
        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)
        #expect(bridge.crossBlockSelection == nil || bridge.crossBlockSelection?.selections.isEmpty == true,
                "nothing to select on an empty note")
    }

    // MARK: - Cross-block mode lifecycle

    @Test
    func newSelectionExitsCrossBlockModeAndCollapsesOthers() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks(["Hello", "world"])
        let a = makeEditor(text: "Hello", bridge: bridge, blockId: blocks[0].id)
        let b = makeEditor(text: "world", bridge: bridge, blockId: blocks[1].id)
        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)
        #expect(bridge.crossBlockSelection != nil)

        // The focused editor's selection changes (typing/clicking) — the
        // mode exits and the OTHER editors' lingering highlights collapse.
        b.textView.setSelectedRange(NSRange(location: 2, length: 0))
        bridge.publish(
            from: b.textView,
            caretBlockId: blocks[1].id,
            isTextSelected: false,
            hasFocus: true,
            caretOffset: 2,
            selectedRange: NSRange(location: 2, length: 0),
            selectionRectInWindow: nil,
            focusedSpecialBlockId: nil,
            isSelectionChange: true
        )

        #expect(bridge.crossBlockSelection == nil, "a new selection exits the cross-block mode")
        #expect(a.textView.selectedRange().length == 0,
                "the other editors' lingering highlights collapse")
    }

    // MARK: - Cross-block formatting

    @Test
    func applyMarksAppliesToEverySelectedBlock() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks(["Hello", "world"])
        let a = makeEditor(text: "Hello", bridge: bridge, blockId: blocks[0].id)
        let b = makeEditor(text: "world", bridge: bridge, blockId: blocks[1].id)
        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)

        bridge.applyMarks([.bold])

        func bold(at offset: Int, in view: NSTextView) -> Bool {
            let font = view.attributedString().attribute(.font, at: offset, effectiveRange: nil) as? NSFont
            return font?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }
        #expect(bold(at: 0, in: a.textView), "the format lands on the first block")
        #expect(bold(at: 0, in: b.textView), "the format lands on every selected block")
    }

    // MARK: - Typing replaces the cross-block selection

    @Test
    func typingReplacementWipesOtherBlocksAndReplacesFocused() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks(["Hello", "world"])
        let (a, windowA) = makeHostedEditor(text: "Hello", bridge: bridge, blockId: blocks[0].id)
        let (b, windowB) = makeHostedEditor(text: "world", bridge: bridge, blockId: blocks[1].id)
        defer {
            windowA.close()
            windowB.close()
        }
        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)
        #expect(a.textView.selectedRange() == NSRange(location: 0, length: 5),
                "precondition: full selection (got \(a.textView.selectedRange()))")

        let consumed = a.coordinator.handleTypingReplacement(character: "x")

        #expect(consumed, "a printable character consumes the cross-block selection")
        #expect(a.textView.string == "x", "the focused block receives the character (got '\(a.textView.string)')")
        #expect(b.textView.string.isEmpty, "the other blocks' selected text is wiped (got '\(b.textView.string)')")
    }

    @Test
    func typingReplacementSkipsControlCharacters() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks(["Hello", "world"])
        let a = makeEditor(text: "Hello", bridge: bridge, blockId: blocks[0].id)
        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)

        #expect(!a.coordinator.handleTypingReplacement(character: "\u{7f}"),
                "control characters (e.g. Delete's raw event) are not replacements")
        #expect(!a.coordinator.handleTypingReplacement(character: nil))
    }

    // MARK: - Backspace routes to spanning deletion

    @Test
    func deleteBackwardInCrossBlockModeRoutesToSpanningDeletion() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let blocks = makeBlocks(["Hello", "world"])
        var deleted = false
        let a = makeEditor(
            text: "Hello", bridge: bridge, blockId: blocks[0].id,
            onDeleteSpanningSelection: { deleted = true }
        )
        bridge.selectAll(blocks: blocks, focusedBlockId: blocks[0].id)

        a.textView.doCommand(by: #selector(NSResponder.deleteBackward(_:)))

        #expect(deleted, "Backspace while in the cross-block mode deletes the whole selection")
        #expect(a.textView.selectedRange().length == 5,
                "the view selection is untouched — the host performs the deletion")
    }
}
