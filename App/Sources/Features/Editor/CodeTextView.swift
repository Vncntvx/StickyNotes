import SwiftUI
import AppKit
import Domain

// MARK: - CodeTextView (004 修复, 2026-08-13)
//
// The code block's editable surface: a plain-text monospaced NSTextView
// (isRichText = false) committing into `CodePayload.text`. It belongs to
// the SAME unified editing context as the rich-text editors:
// - shares the window-level UndoManager (⌘Z/⌘⇧Z span the whole note);
// - publishes focus into the note's EditorSelectionBridge with
//   `focusedSpecialBlockId` (insertion targets `.afterBlock` — FR-010);
// - supports insertion-focus requests (first responder + caret at start);
// - rich-text format commands (⌘B/⌘I) are a NO-OP here (`richTextEditable`
//   = false) — code is plain text by contract (FR-080).

public struct CodeTextView: NSViewRepresentable {
    let text: String
    let onCommit: (String) -> Void
    let selectionBridge: EditorSelectionBridge?
    let blockId: UUID?
    let undoManager: UndoManager?
    let requestFocus: Bool
    /// 004 修复 (2026-08-14, P0): caret position for a focus request —
    /// `.end` only ever targets rich-text blocks in practice (tail
    /// continuation); the parameter keeps the contract uniform.
    let caretAtEnd: Bool
    let onFocusRequestHandled: () -> Void
    /// 004 修复 (P1-6): focus transitions — mirrors RichTextView's
    /// `(focused, hasMarkedText)` contract so the FR-050a empty-block
    /// exit applies to code blocks too (FR-063 IME guard included).
    let onFocusChange: (Bool, Bool) -> Void
    /// 2026-08-14: 空块按键删除（Backspace/Delete）——视图层路由到 host
    /// 的 `deleteEmptyBlockOnKey`（含焦点下一块）。
    let onDeleteEmptyBlock: (() -> Void)?
    /// 2026-08-14: 非空块块首 Backspace 的"并入上一块"（Q4-A 决策）。
    let onMergeIntoPrevious: (() -> Void)?

    public init(
        text: String,
        onCommit: @escaping (String) -> Void,
        selectionBridge: EditorSelectionBridge? = nil,
        blockId: UUID? = nil,
        undoManager: UndoManager? = nil,
        requestFocus: Bool = false,
        caretAtEnd: Bool = false,
        onFocusRequestHandled: @escaping () -> Void = {},
        onFocusChange: @escaping (Bool, Bool) -> Void = { _, _ in },
        onDeleteEmptyBlock: (() -> Void)? = nil,
        onMergeIntoPrevious: (() -> Void)? = nil
    ) {
        self.text = text
        self.onCommit = onCommit
        self.selectionBridge = selectionBridge
        self.blockId = blockId
        self.undoManager = undoManager
        self.requestFocus = requestFocus
        self.caretAtEnd = caretAtEnd
        self.onFocusRequestHandled = onFocusRequestHandled
        self.onFocusChange = onFocusChange
        self.onDeleteEmptyBlock = onDeleteEmptyBlock
        self.onMergeIntoPrevious = onMergeIntoPrevious
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = CodeEditorTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)  // FR-080
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        // 2026-08-14: 块级按键（空块删除/块首合并）由 Coordinator 裁决。
        textView.blockKeyHandler = context.coordinator
        textView.autoresizingMask = [.width]
        context.coordinator.push(text: text, to: textView)
        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        // 004 修复: track the CURRENT struct — a stale `parent` (captured
        // by makeCoordinator) would commit against pre-insertion state and
        // read stale focus flags.
        context.coordinator.parent = self
        context.coordinator.attach(textView)
        // FR-063: while the IME is composing, the live string contains the
        // marked text but the model holds the pre-composition version — a
        // push here would destroy the composition.
        if !textView.hasMarkedText(), textView.string != text {
            context.coordinator.push(text: text, to: textView)
        }
        if requestFocus {
            context.coordinator.requestFocusIfNeeded(textView)
        } else if context.coordinator.didHandleFocusRequest {
            // 004 修复 (2026-08-14, P0): re-arm the one-shot flag when the
            // request clears — mirror of RichTextView.
            context.coordinator.didHandleFocusRequest = false
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate, BlockKeyCommandHandling {
        var parent: CodeTextView
        private var isPushing = false
        private weak var liveTextView: NSTextView?
        /// One-shot per request edge (re-armed by updateNSView when the
        /// request clears).
        var didHandleFocusRequest = false
        private var focusAttempts = 0
        private weak var observedWindow: NSWindow?
        private var keyStateObservers: [any NSObjectProtocol] = []

        init(_ parent: CodeTextView) {
            self.parent = parent
        }

        deinit {
            MainActor.assumeIsolated {
                keyStateObservers.forEach(NotificationCenter.default.removeObserver)
                if let blockId = parent.blockId { EditorRegistry.unregister(blockId) }
            }
        }

        /// Routes undo to the window-level shared UndoManager (unified
        /// editing context).
        public func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoManager
        }

        func attach(_ textView: NSTextView) {
            liveTextView = textView
            // 2026-08-14: 注册到跨块操作注册表（⌘A 整篇全选/跨块删除）。
            if let blockId = parent.blockId { EditorRegistry.register(textView, for: blockId) }
            observeKeyState(of: textView.window)
            publishSelection(from: textView)
        }

        func push(text: String, to textView: NSTextView) {
            // FR-063: never overwrite an active IME composition.
            guard !textView.hasMarkedText() else { return }
            isPushing = true
            defer { isPushing = false }
            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            textView.string = text
        }

        public func textDidChange(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            // FR-063: never persist partial IME composition.
            guard !textView.hasMarkedText() else { return }
            parent.onCommit(textView.string)
        }

        public func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true, false)
            if let textView = notification.object as? NSTextView {
                publishSelection(from: textView)
            }
        }

        public func textDidEndEditing(_ notification: Notification) {
            if let textView = notification.object as? NSTextView {
                // 004 修复 (P1-6): the FR-050a empty-block exit reads the
                // IME state at focus loss (FR-063).
                parent.onFocusChange(false, textView.hasMarkedText())
                publishSelection(from: textView)
                // 2026-08-14 (用户实测): same exclusive-selection rule as
                // RichTextView — collapse the lingering selection if focus
                // does not return within this event turn (the bridge covers
                // the focus-MOVE case; this covers non-editor destinations).
                DispatchQueue.main.async { [weak textView] in
                    guard let textView, textView.window?.firstResponder !== textView else { return }
                    let location = textView.selectedRange().location
                    textView.setSelectedRange(NSRange(
                        location: location == NSNotFound ? 0 : location,
                        length: 0
                    ))
                }
            }
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            guard !textView.hasMarkedText() else { return }
            publishSelection(from: textView)
        }

        private func publishSelection(from textView: NSTextView) {
            guard let bridge = parent.selectionBridge else { return }
            let range = textView.selectedRange()
            let hasFocus = (textView.window?.isKeyWindow ?? false) && (textView.window?.firstResponder === textView)
            let scalarOffset = NoteWindowDerivations.scalarOffset(fromUTF16: range.location, in: textView.string)
            bridge.publish(
                from: textView,
                caretBlockId: parent.blockId,
                isTextSelected: range.length > 0,
                hasFocus: hasFocus,
                richTextEditable: false,
                caretOffset: scalarOffset,
                selectedRange: range,
                selectionRectInWindow: nil,
                focusedSpecialBlockId: parent.blockId
            )
        }

        func requestFocusIfNeeded(_ textView: NSTextView) {
            guard parent.requestFocus, !didHandleFocusRequest else { return }
            if let window = textView.window {
                didHandleFocusRequest = true
                window.makeFirstResponder(textView)
                applyFocusCaret(to: textView)
                parent.onFocusRequestHandled()
                return
            }
            // The representable can update before the window attaches —
            // retry on the next runloop turn (bounded). The retry captures
            // the struct's closure + the view directly so it does not
            // depend on the coordinator surviving the async hop.
            focusAttempts += 1
            guard focusAttempts < 500 else { return }
            let handler = parent.onFocusRequestHandled
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let textView else { return }
                if let window = textView.window {
                    self?.didHandleFocusRequest = true
                    window.makeFirstResponder(textView)
                    self?.applyFocusCaret(to: textView)
                    handler()
                } else {
                    self?.requestFocusIfNeeded(textView)
                }
            }
        }

        /// The caret position for a focus request (see RichTextView).
        private func applyFocusCaret(to textView: NSTextView) {
            let location = parent.caretAtEnd ? (textView.string as NSString).length : 0
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        // MARK: - Block key commands (2026-08-14)

        /// Backspace：空块任意位置 → 删除块（Q2-A）；非空块块首（无选中）
        /// → 并入上一块（Q4-A）；其余保持默认文本删除。IME 组合期间不
        /// 拦截（FR-063）。
        func handleDeleteBackward() -> Bool {
            guard let textView = liveTextView, !textView.hasMarkedText() else { return false }
            if parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parent.onDeleteEmptyBlock?()
                return true
            }
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location == 0 else { return false }
            parent.onMergeIntoPrevious?()
            return true
        }

        /// Delete（fn+delete）：仅空块任意位置删除块（Q2-A）；非空块不
        /// 拦截（块首 Delete 是普通前向删除）。
        func handleDeleteForward() -> Bool {
            guard let textView = liveTextView, !textView.hasMarkedText() else { return false }
            guard parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            parent.onDeleteEmptyBlock?()
            return true
        }

        /// Q10-B: code 块尾 Return 保持换行（多行代码零障碍）；块间插入
        /// 走 `+` 按钮菜单。
        func handleInsertNewline(shift: Bool) -> Bool { false }

        /// 跨块替换仅富文本编辑器参与——code 块不拦截字符输入。
        func handleTypingReplacement(character: String?) -> Bool { false }

        /// 2026-08-14 (Q1-A): 拖选越过本块边界 → 跨块拖选（code 文本同样
        /// 参与跨块选区）。
        func handleCrossBlockDrag(event: NSEvent) -> Bool {
            guard let textView = liveTextView,
                  let bridge = parent.selectionBridge else { return false }
            return CrossBlockDragRouter.handleDrag(
                event: event,
                from: textView,
                sourceBlockId: parent.blockId,
                bridge: bridge
            )
        }

        private func observeKeyState(of window: NSWindow?) {
            guard window !== observedWindow else { return }
            keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            keyStateObservers.removeAll()
            observedWindow = window
            guard let window else { return }
            let center = NotificationCenter.default
            keyStateObservers.append(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.republishSelection() })
            keyStateObservers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.republishSelection() })
        }

        private func republishSelection() {
            guard let textView = liveTextView else { return }
            publishSelection(from: textView)
        }
    }
}

/// The code block's editor view: content-sized — one line pays one line of
/// height (+ insets), N lines pay N. The only floor is a single line: the
/// empty block's click target (004 修复 2026-08-13: the legacy fixed 44pt
/// two-line floor left single-line code floating in dead space).
final class CodeEditorTextView: IntrinsicSizingTextView {

    override var intrinsicContentSize: NSSize {
        let lineFont = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineHeight = lineFont.ascender - lineFont.descender + lineFont.leading
        let singleLineFloor = ceil(lineHeight) + textContainerInset.height * 2
        // 2026-08-14 fix (insertion gap): same zero-width guard as
        // NotePaperTextView — a freshly inserted code editor's first
        // measurement at container width 0 reports every glyph on its own
        // line (bogus tall), inflating the insertion gap until a width
        // change re-measures.
        if let container = textContainer, container.size.width <= 1.0 {
            return NSSize(width: NSView.noIntrinsicMetric, height: singleLineFloor)
        }
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        let used = layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? 0
        let contentHeight = used + textContainerInset.height * 2
        // One monospaced line + insets — content-sized text never pays more
        // than its lines; empty text keeps this as its click target.
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(contentHeight, singleLineFloor)
        )
    }
}
