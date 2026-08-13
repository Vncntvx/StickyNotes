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
    let onFocusRequestHandled: () -> Void
    /// 004 修复 (P1-6): focus transitions — mirrors RichTextView's
    /// `(focused, hasMarkedText)` contract so the FR-050a empty-block
    /// exit applies to code blocks too (FR-063 IME guard included).
    let onFocusChange: (Bool, Bool) -> Void

    public init(
        text: String,
        onCommit: @escaping (String) -> Void,
        selectionBridge: EditorSelectionBridge? = nil,
        blockId: UUID? = nil,
        undoManager: UndoManager? = nil,
        requestFocus: Bool = false,
        onFocusRequestHandled: @escaping () -> Void = {},
        onFocusChange: @escaping (Bool, Bool) -> Void = { _, _ in }
    ) {
        self.text = text
        self.onCommit = onCommit
        self.selectionBridge = selectionBridge
        self.blockId = blockId
        self.undoManager = undoManager
        self.requestFocus = requestFocus
        self.onFocusRequestHandled = onFocusRequestHandled
        self.onFocusChange = onFocusChange
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
        if textView.string != text {
            context.coordinator.push(text: text, to: textView)
        }
        if requestFocus {
            context.coordinator.requestFocusIfNeeded(textView)
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        private var isPushing = false
        private weak var liveTextView: NSTextView?
        private var didHandleFocusRequest = false
        private var focusAttempts = 0
        private weak var observedWindow: NSWindow?
        private var keyStateObservers: [any NSObjectProtocol] = []

        init(_ parent: CodeTextView) {
            self.parent = parent
        }

        deinit {
            MainActor.assumeIsolated {
                keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            }
        }

        /// Routes undo to the window-level shared UndoManager (unified
        /// editing context).
        public func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoManager
        }

        func attach(_ textView: NSTextView) {
            liveTextView = textView
            observeKeyState(of: textView.window)
            publishSelection(from: textView)
        }

        func push(text: String, to textView: NSTextView) {
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
                textView.setSelectedRange(NSRange(location: 0, length: 0))
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
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                    handler()
                } else {
                    self?.requestFocusIfNeeded(textView)
                }
            }
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
final class CodeEditorTextView: NSTextView {

    override var intrinsicContentSize: NSSize {
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        let used = layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? 0
        let contentHeight = used + textContainerInset.height * 2
        // One monospaced line + insets — content-sized text never pays more
        // than its lines; empty text keeps this as its click target.
        let lineFont = font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let lineHeight = lineFont.ascender - lineFont.descender + lineFont.leading
        let singleLineFloor = ceil(lineHeight) + textContainerInset.height * 2
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(contentHeight, singleLineFloor)
        )
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
