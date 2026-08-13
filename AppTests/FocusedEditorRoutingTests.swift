import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Focused-editor command routing (004 修复, 2026-08-13)
//
// 新 FR：⌘B/⌘I 等格式命令 MUST 作用于聚焦的编辑器（而非恒为主编辑器）：
// - 每便签一个 EditorSelectionBridge 跟踪最近聚焦的编辑器；
// - 非聚焦编辑器的过期发布不得覆盖聚焦状态；
// - 聚焦编辑器自身失焦 → hasFocus=false（选区保留，FR-012 行隐藏）；
// - 纯文本块（code）不接受富文本 marks（no-op）；
// - 特殊块（todo/code）聚焦发布 focusedSpecialBlockId → 插入目标 .afterBlock。

@MainActor
@Suite struct FocusedEditorRoutingTests {

    private func makeEditor(text: String, rich: Bool = true) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
        textView.isRichText = rich
        textView.allowsUndo = true
        textView.isEditable = true
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 13)
        return textView
    }

    /// Publishes a selection snapshot the way RichTextView/CodeTextView
    /// coordinators do (mirroring the editor-side selection on the view).
    private func publish(
        _ bridge: EditorSelectionBridge,
        from textView: NSTextView?,
        focus: Bool,
        selected: Bool = true,
        rich: Bool = true,
        specialId: UUID? = nil,
        selection: NSRange = NSRange(location: 0, length: 2)
    ) {
        textView?.setSelectedRange(selection)
        bridge.publish(
            from: textView,
            caretBlockId: nil,
            isTextSelected: selected,
            hasFocus: focus,
            richTextEditable: rich,
            caretOffset: 0,
            selectedRange: selected ? selection : nil,
            selectionRectInWindow: nil,
            focusedSpecialBlockId: specialId
        )
    }

    @Test
    func applyMarksTargetsFocusedEditorNotPrimary() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let primary = makeEditor(text: "hello")
        let secondary = makeEditor(text: "world")

        publish(bridge, from: primary, focus: true, selection: NSRange(location: 0, length: 5))
        publish(bridge, from: secondary, focus: true, selection: NSRange(location: 0, length: 5))
        #expect(bridge.textView === secondary, "the bridge must track the focused editor")

        bridge.applyMarks([.bold])
        let secondaryFont = secondary.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(secondaryFont?.fontDescriptor.symbolicTraits.contains(.bold) == true,
                "marks must land on the focused editor")
        let primaryFont = primary.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(primaryFont?.fontDescriptor.symbolicTraits.contains(.bold) == false,
                "marks must NOT land on the unfocused editor")
    }

    @Test
    func staleFocusLossFromBackgroundEditorIsIgnored() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let a = makeEditor(text: "one")
        let b = makeEditor(text: "two")

        publish(bridge, from: a, focus: true)
        publish(bridge, from: b, focus: false, selected: false)
        #expect(bridge.hasFocus, "a stale focus-loss publish must not clear the focused state")
        #expect(bridge.isTextSelected, "a stale publish must not clear the selection state")
        #expect(bridge.textView === a, "the focused editor stays authoritative")
    }

    @Test
    func focusedEditorLosingFocusHidesContextRow() {
        // FR-012: the focused editor itself resigning focus (window
        // deactivation) clears hasFocus while the selection persists.
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let a = makeEditor(text: "one")

        publish(bridge, from: a, focus: true)
        #expect(bridge.hasFocus)
        publish(bridge, from: a, focus: false, selected: true)
        #expect(!bridge.hasFocus, "the focused editor's own focus loss must clear hasFocus")
        #expect(bridge.isTextSelected, "selection persists — the row reappears on reactivation (FR-012)")
    }

    @Test
    func codeEditorDoesNotAcceptRichMarks() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let code = makeEditor(text: "let x", rich: false)

        publish(bridge, from: code, focus: true, rich: false, selection: NSRange(location: 0, length: 5))
        bridge.applyMarks([.bold])
        let font = code.attributedString().attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == false,
                "plain-text (code) editors must not accept rich-text marks")
    }

    @Test
    func specialBlockFocusResolvesToAfterBlockTarget() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let todoId = UUID()
        let editor = makeEditor(text: "todo text")

        publish(bridge, from: editor, focus: true, specialId: todoId)

        let context = EditorSelectionContext.current(for: bridge.noteId)
        #expect(context.focusedSpecialBlockId == todoId,
                "a special-block editor must publish its focusedSpecialBlockId")

        let blocks = [
            Block(
                noteId: bridge.noteId, kind: .richText, sortKey: 0,
                payload: .richText(.plain("head")), lastModifiedDeviceId: UUID()
            ),
            Block(
                id: todoId, noteId: bridge.noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("x"))),
                lastModifiedDeviceId: UUID()
            )
        ]
        #expect(NoteWindowDerivations.resolveInsertionTarget(blocks: blocks, context: context) == .afterBlock(blockId: todoId),
                "focus inside a special block must insert after it (FR-010)")
    }
}
