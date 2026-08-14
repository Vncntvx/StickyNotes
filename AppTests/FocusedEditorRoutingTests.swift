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
// - 特殊块（todo/code）聚焦发布 focusedSpecialBlockId → 插入目标 .afterBlock；
// - 选区排他（2026-08-14 用户实测）：焦点移交给另一编辑器时清除旧编辑器的
//   view 选区（NSTextView 各自持有 selectedRange，失焦后 AppKit 把旧选区
//   画成灰色残留）；窗口失活（同编辑器 hasFocus=false）不清除（FR-012）；
//   焦点离开到非编辑器（标题/工具栏）时编辑器自行收拢选区。

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

    // MARK: - Exclusive selection (2026-08-14 用户实测)

    // 多编辑器便签中焦点移交必须清除旧编辑器的 view 选区：每个 NSTextView
    // 各自持有 selectedRange，失去焦点后 AppKit 把旧选区画成非强调灰色
    // 残留（"上一段仍保持被选中的样式"）。仅"焦点移交给另一编辑器"清除；
    // 窗口失活是同编辑器的 hasFocus=false，选区保留（FR-012）。

    @Test
    func focusMovedToAnotherEditorClearsPreviousViewSelection() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let a = makeEditor(text: "one two")
        let b = makeEditor(text: "three four")

        publish(bridge, from: a, focus: true, selection: NSRange(location: 0, length: 3))
        #expect(a.selectedRange().length == 3)

        publish(bridge, from: b, focus: true, selection: NSRange(location: 0, length: 5))
        #expect(b.selectedRange().length == 5, "the newly focused editor keeps its selection")
        #expect(a.selectedRange().length == 0,
                "focus moving to another editor must collapse the previous editor's lingering selection")
    }

    @Test
    func refocusingSameEditorKeepsSelection() {
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let a = makeEditor(text: "one two")

        publish(bridge, from: a, focus: true, selection: NSRange(location: 0, length: 3))
        publish(bridge, from: a, focus: true, selection: NSRange(location: 2, length: 4))
        #expect(a.selectedRange().length == 4,
                "the same editor republishing focus must keep its selection")
    }

    @Test
    func windowDeactivationKeepsViewSelection() {
        // FR-012: window deactivation is a hasFocus=false publish from the
        // SAME editor — not a focus MOVE — the view selection must survive
        // (the row reappears on reactivation).
        let bridge = EditorSelectionBridge(noteId: UUID())
        defer { bridge.invalidate() }
        let a = makeEditor(text: "one two")

        publish(bridge, from: a, focus: true, selection: NSRange(location: 0, length: 3))
        publish(bridge, from: a, focus: false, selected: true, selection: NSRange(location: 0, length: 3))
        #expect(a.selectedRange().length == 3, "deactivation must not collapse the view selection")
    }

    @Test
    func focusLeavingToNonEditorCollapsesViewSelection() async throws {
        // 点击标题/工具栏等非编辑器：编辑器失焦但没有任何新编辑器接管
        // （bridge 无从清除）——编辑器在失焦后的下一个 runloop turn 仍未
        // 恢复焦点时自行收拢选区（格式条按钮动作同步恢复焦点，不受影响）。
        let window = makeProbeWindow()
        defer { window.close() }
        let editor = RichTextView(
            document: .plain("one two"),
            editorTypography: .system(textSize: 13),
            onCommit: { _ in }
        )
        let coordinator = RichTextView.Coordinator(editor)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 200))
        textView.isRichText = true
        textView.string = "one two"
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.delegate = coordinator
        window.contentView?.addSubview(textView)

        window.makeKeyAndOrderFront(nil)
        #expect(window.makeFirstResponder(textView), "editor must accept first responder")
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        window.makeFirstResponder(nil)
        try await Task.sleep(for: .milliseconds(200))
        #expect(textView.selectedRange().length == 0,
                "focus leaving to a non-editor must collapse the lingering selection")
    }

    private func makeProbeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
