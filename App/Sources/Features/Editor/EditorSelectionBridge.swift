import SwiftUI
import AppKit
import Domain

// MARK: - EditorSelectionContext (004 US4/US5)
//
// Per-note insertion/focus context, published by the editor's selection
// bridge (T037) and consumed by the window-level Insert actions (T032) and
// the contextual format row (T039). Read-only projection — SwiftUI never
// writes back into the editor (plan §2.3: NSTextView is the authority).

@MainActor
public enum EditorSelectionContext {
    /// The latest insertion context per note (caret block/offset + focused
    /// special block). Empty when no note has published one.
    static var registry: [UUID: InsertionContext] = [:]

    /// The live selection bridges per note (menu-driven formatting — 004
    /// T040: Format commands act on the key window's editor).
    static var bridges: [UUID: EditorSelectionBridge] = [:]

    /// The current insertion context for a note (defaults to `.append`
    /// semantics — contracts §5 degradation).
    public static func current(for noteId: UUID) -> InsertionContext {
        registry[noteId] ?? InsertionContext()
    }

    /// The key note's bridge, or nil. Prefers the bridge whose editor is
    /// actually focused (004 修复: 格式命令作用于聚焦编辑器，而非任意
    /// key-window 主编辑器).
    public static func bridge(forKeyWindow noteIds: [UUID]) -> EditorSelectionBridge? {
        for noteId in noteIds {
            if let bridge = bridges[noteId], bridge.hasFocus,
               bridge.textView?.window?.isKeyWindow == true {
                return bridge
            }
        }
        for noteId in noteIds where bridges[noteId]?.textView?.window?.isKeyWindow == true {
            return bridges[noteId]
        }
        return noteIds.first.flatMap { bridges[$0] }
    }
}

// MARK: - EditorSelectionBridge (004 T037, FR-012/Q5)

/// @Observable projection of the editor's selection/focus state, driving
/// the contextual format row and the insertion-target resolution. The
/// editor's Coordinator publishes into it via `textDidChangeSelection` and
/// first-responder observation (RichTextView, T037).
@MainActor
@Observable
public final class EditorSelectionBridge {
    /// The note this bridge belongs to.
    public let noteId: UUID
    /// The live focused editor (set when an editor publishes focus; weak —
    /// never outlives the editor). NSTextView is the formatting authority.
    public weak var textView: NSTextView?
    /// The most recent editor that published `hasFocus == true` — the
    /// authority filter: stale publishes from non-focused editors are
    /// ignored (004 修复: 多编辑器共用一个 bridge).
    private weak var focusedTextView: NSTextView?
    /// Whether any text is selected in the focused editor.
    public private(set) var isTextSelected = false
    /// Whether the focused editor is the first responder (window focused,
    /// caret active).
    public private(set) var hasFocus = false
    /// Whether the focused editor accepts rich-text marks (plain-text code
    /// editors report false — ⌘B/⌘I no-op there).
    public private(set) var richTextEditable = true
    /// The caret position (scalar offset in the block).
    public private(set) var caretOffset: Int?
    /// The selected range (UTF-16 NSRange of the focused editor) — nil when
    /// collapsed.
    public private(set) var selectedRange: NSRange?
    /// The selection rectangle in window coordinates (contextual row
    /// anchoring).
    public private(set) var selectionRectInWindow: CGRect?
    /// The currently focused special block id (todo/code editor), if any.
    public private(set) var focusedSpecialBlockId: UUID?

    public init(noteId: UUID) {
        self.noteId = noteId
        self.textView = nil
        EditorSelectionContext.bridges[noteId] = self
    }

    /// Publishes a selection snapshot (called from the editor's
    /// `textDidChangeSelection` and focus callbacks). Updates the
    /// insertion-target registry alongside the UI state.
    ///
    /// Authority rule (004 修复): a publish with `hasFocus == true` makes
    /// `textView` the focused editor; publishes from any OTHER editor are
    /// ignored (stale focus-loss/selection events must not clobber the
    /// focused state). A `from: nil` publish (tests/legacy) is authoritative.
    public func publish(
        from textView: NSTextView? = nil,
        caretBlockId: UUID?,
        isTextSelected: Bool,
        hasFocus: Bool,
        richTextEditable: Bool = true,
        caretOffset: Int?,
        selectedRange: NSRange?,
        selectionRectInWindow: CGRect?,
        focusedSpecialBlockId: UUID?
    ) {
        if let textView {
            if hasFocus {
                focusedTextView = textView
                self.textView = textView
            } else if focusedTextView !== textView {
                // Stale publish from a non-focused editor — ignore.
                return
            }
        }
        self.isTextSelected = isTextSelected
        self.hasFocus = hasFocus
        self.richTextEditable = richTextEditable
        self.caretOffset = caretOffset
        self.selectedRange = selectedRange
        self.selectionRectInWindow = selectionRectInWindow
        self.focusedSpecialBlockId = focusedSpecialBlockId
        EditorSelectionContext.registry[noteId] = InsertionContext(
            caretBlockId: caretBlockId,
            caretOffset: caretOffset,
            focusedSpecialBlockId: focusedSpecialBlockId
        )
    }

    /// Attaches the live editor (RichTextView.Coordinator.attach).
    public func attach(textView: NSTextView, blockId: UUID?) {
        self.textView = textView
        EditorSelectionContext.registry[noteId] = InsertionContext(
            caretBlockId: blockId,
            caretOffset: caretOffset,
            focusedSpecialBlockId: focusedSpecialBlockId
        )
    }

    /// Applies marks to the focused editor (contextual format row — 004
    /// T038/FR-012). No selection → typingAttributes (subsequent input);
    /// IME composition suppresses application (FR-063); plain-text (code)
    /// editors are a no-op (004 修复).
    public func applyMarks(_ marks: Set<RichTextMark>) {
        guard richTextEditable else { return }
        guard let textView else { return }
        RichTextMarkApplier.applyMarks(marks, to: textView)
    }

    public func invalidate() {
        isTextSelected = false
        hasFocus = false
        richTextEditable = true
        caretOffset = nil
        selectedRange = nil
        selectionRectInWindow = nil
        focusedSpecialBlockId = nil
        textView = nil
        focusedTextView = nil
        EditorSelectionContext.bridges[noteId] = nil
        EditorSelectionContext.registry[noteId] = nil
    }
}
