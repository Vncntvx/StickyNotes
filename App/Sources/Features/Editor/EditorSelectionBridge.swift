import SwiftUI
import AppKit
import Domain
import EditorCore

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
    /// actually focused
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

// MARK: - EditorRegistry (2026-08-14)
//
// The live block-editor registry — the ONLY way cross-block operations
// (⌘A note-wide selection, cross-block formatting/deletion, typing
// replacement) locate the NSTextView backing a block id. Coordinators
// register on attach and unregister on deinit; the bridge's invalidate
// clears everything.

@MainActor
public enum EditorRegistry {
    private static var textViews: [UUID: NSTextView] = [:]

    public static func register(_ textView: NSTextView, for blockId: UUID) {
        textViews[blockId] = textView
    }

    public static func unregister(_ blockId: UUID) {
        textViews[blockId] = nil
    }

    public static func textView(for blockId: UUID) -> NSTextView? {
        textViews[blockId]
    }

    /// All registered (blockId, textView) pairs — cross-block collapse.
    static var all: [(blockId: UUID, textView: NSTextView)] {
        textViews.map { ($0.key, $0.value) }
    }

    static func clear() {
        textViews.removeAll()
    }
}

// MARK: - CrossBlockDragRouter (2026-08-14, Q1-A)
//
// 拖选跨块：鼠标从源块拖出边界进入目标块时，源块选区钉住
// （[anchor, 尾] 向下 / [0, anchor] 向上），目标块选区随拖入点更新
// （[0, drop] 向下 / [drop, 尾] 向上），中间块全选，bridge 进入跨块模式。
// 全程抑制"选区变化退出跨块模式"（每次 setSelectedRange 的
// didChangeSelection 会误触发折叠）。拖回本块返回 false（默认拖选恢复，
// 单块选区的 didChangeSelection 自然退出跨块模式）。

@MainActor
enum CrossBlockDragRouter {

    static func handleDrag(
        event: NSEvent,
        from source: NSTextView,
        sourceBlockId: UUID?,
        bridge: EditorSelectionBridge
    ) -> Bool {
        guard let window = source.window else {
            return false
        }
        let location = source.convert(event.locationInWindow, from: nil)
        guard !source.bounds.contains(location) else { return false }

        let candidates = EditorRegistry.all.filter { $0.textView.window === window }
        guard let target = candidates.first(where: {
            $0.textView !== source && $0.textView.bounds.contains(
                $0.textView.convert(event.locationInWindow, from: nil)
            )
        }) else {
            return false
        }

        // Window base coordinates are NOT flipped: a larger minY sits
        // HIGHER on screen — the target is below the source when its minY
        // is smaller.
        let draggingDown = target.textView.frame.minY <= source.frame.minY
        bridge.withCrossBlockSuppression {
            // 源块钉住。
            let anchor = source.selectedRange().location
            if draggingDown {
                let end = (source.string as NSString).length
                source.setSelectedRange(NSRange(location: anchor, length: end - anchor))
            } else {
                source.setSelectedRange(NSRange(location: 0, length: anchor))
            }
            // 目标块随拖入点。LayoutManager 的 glyph 查询（容器坐标，
            // 非翻转：y 从容器底部算）不依赖视图渲染状态，比
            // characterIndexForInsertion 可靠（后者在未渲染的测试宿主
            // 中退化返回文本尾）。
            let targetPoint = target.textView.convert(event.locationInWindow, from: nil)
            let container = target.textView.textContainer ?? NSTextContainer()
            let layoutManager = target.textView.layoutManager ?? NSLayoutManager()
            layoutManager.ensureLayout(for: container)
            let containerPoint = NSPoint(
                x: targetPoint.x,
                y: container.size.height - targetPoint.y
            )
            let glyph = layoutManager.glyphIndex(
                for: containerPoint,
                in: container,
                fractionOfDistanceThroughGlyph: nil
            )
            let glyphIndex = layoutManager.characterIndexForGlyph(at: glyph)
            if draggingDown {
                target.textView.setSelectedRange(NSRange(location: 0, length: glyphIndex))
            } else {
                let end = (target.textView.string as NSString).length
                target.textView.setSelectedRange(NSRange(location: glyphIndex, length: end - glyphIndex))
            }
            // 中间块全选。
            for entry in candidates where entry.textView !== source && entry.textView !== target.textView {
                let y = entry.textView.frame.minY
                let between = draggingDown
                    ? (y > source.frame.minY && y < target.textView.frame.minY)
                    : (y < source.frame.minY && y > target.textView.frame.minY)
                if between {
                    entry.textView.setSelectedRange(
                        NSRange(location: 0, length: (entry.textView.string as NSString).length)
                    )
                }
            }
            // 构造跨块选区（UTF-16 → scalar）并发布。
            var selections: [(blockId: UUID, range: Range<Int>)] = []
            for entry in candidates {
                let selected = entry.textView.selectedRange()
                guard selected.length > 0 else { continue }
                let lower = NoteWindowDerivations.scalarOffset(fromUTF16: selected.location, in: entry.textView.string)
                let upper = NoteWindowDerivations.scalarOffset(
                    fromUTF16: selected.location + selected.length, in: entry.textView.string
                )
                selections.append((blockId: entry.blockId, range: lower..<upper))
            }
            bridge.publishCrossBlockSelection(
                CrossBlockSelection(selections: selections),
                focusedBlockId: sourceBlockId
            )
        }
        return true
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
    /// The SEMANTIC marks on the current selection (2026-08-14: drives the
    /// format bar's active states — a toggle button highlights when its
    /// mark is already present). Empty while collapsed.
    public private(set) var selectedMarks: Set<RichTextMark> = []
    /// The selection rectangle in window coordinates (contextual row
    /// anchoring).
    public private(set) var selectionRectInWindow: CGRect?
    /// The currently focused special block id (todo/code editor), if any.
    public private(set) var focusedSpecialBlockId: UUID?
    /// 2026-08-14: the note-wide cross-block selection (⌘A / drag). Non-nil
    /// while the note is in cross-block mode — every editor shows its own
    /// segment highlighted and formatting/deletion act on ALL segments. Any
    /// real selection change (`publish(isSelectionChange: true)`) exits the
    /// mode and collapses the other editors' lingering highlights.
    public private(set) var crossBlockSelection: CrossBlockSelection?
    /// 2026-08-14: the typing-replacement path mutates every selected block
    /// in one pass — each `replaceCharacters` fires the editor's own
    /// didChangeSelection, which would otherwise exit the mode and collapse
    /// the not-yet-processed editors mid-pass. The pass runs under this
    /// suppression; the final publish (after the pass) exits the mode once.
    private var suppressesSelectionExit = false

    /// Runs `body` with the selection-change exit suppressed (the
    /// cross-block typing replacement).
    func withCrossBlockSuppression<T>(_ body: () -> T) -> T {
        suppressesSelectionExit = true
        defer { suppressesSelectionExit = false }
        return body()
    }

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
        selectedMarks: Set<RichTextMark> = [],
        selectionRectInWindow: CGRect?,
        focusedSpecialBlockId: UUID?,
        isSelectionChange: Bool = false
    ) {
        // 2026-08-14: a REAL selection change exits the cross-block mode
        // (⌘A note-wide selection / drag) and collapses the OTHER editors'
        // lingering highlights — the publishing editor keeps its own
        // (the user is operating it). Format-row interactions publish
        // without `isSelectionChange` and never disturb the mode.
        if isSelectionChange, crossBlockSelection != nil, !suppressesSelectionExit {
            crossBlockSelection = nil
            for (_, editor) in EditorRegistry.all where editor !== textView {
                let location = editor.selectedRange().location
                editor.setSelectedRange(NSRange(
                    location: location == NSNotFound ? 0 : location,
                    length: 0
                ))
            }
        }
        if let textView {
            if hasFocus {
                // 2026-08-14 (用户实测): focus moved to a DIFFERENT editor —
                // each NSTextView owns its own selection, so the previous
                // editor keeps painting its old range as the inactive gray
                // highlight. Collapse it (caret position preserved). The
                // new editor becomes authoritative FIRST — the previous
                // editor's synchronous republish (its didChangeSelection
                // fires from the setSelectedRange below) is then filtered
                // by the authority rule.
                if let previous = focusedTextView, previous !== textView {
                    let location = previous.selectedRange().location
                    previous.setSelectedRange(NSRange(
                        location: location == NSNotFound ? 0 : location,
                        length: 0
                    ))
                }
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
        self.selectedMarks = selectedMarks
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

    /// 2026-08-14: enters the cross-block mode for a note-wide selection.
    /// Every editor already shows its own segment (callers set the
    /// per-editor `selectedRange` first). The format row re-anchors via the
    /// focused editor's own republish (which does NOT carry
    /// `isSelectionChange` and therefore keeps the mode).
    public func publishCrossBlockSelection(
        _ selection: CrossBlockSelection,
        focusedBlockId: UUID?
    ) {
        crossBlockSelection = selection
        isTextSelected = !selection.selections.isEmpty
        hasFocus = true
        richTextEditable = true
        EditorSelectionContext.registry[noteId] = InsertionContext(
            caretBlockId: focusedBlockId,
            caretOffset: caretOffset,
            focusedSpecialBlockId: focusedSpecialBlockId
        )
    }

    /// 2026-08-14 (⌘A, Q8-B): selects the WHOLE note — every non-empty
    /// block's full text (trailing empty padding excluded), then enters the
    /// cross-block mode. The focused editor's rect is republished so the
    /// format row anchors to it.
    public func selectAll(blocks: [Block], focusedBlockId: UUID?) {
        let selection = NoteWindowDerivations.crossBlockSelectionCoveringAll(blocks: blocks)
        for entry in selection.selections {
            guard let editor = EditorRegistry.textView(for: entry.blockId) else { continue }
            let utf16 = NoteWindowDerivations.utf16Range(fromScalarRange: entry.range, in: editor.string)
            editor.setSelectedRange(utf16)
        }
        publishCrossBlockSelection(selection, focusedBlockId: focusedBlockId)
        if let focused = focusedBlockId.flatMap(EditorRegistry.textView(for:)),
           let coordinator = focused.delegate as? RichTextView.Coordinator {
            coordinator.republishSelection()
        }
    }

    /// Applies marks to the focused editor (contextual format row — 004
    /// T038/FR-012). No selection → typingAttributes (subsequent input);
    /// IME composition suppresses application (FR-063); plain-text (code)
    /// editors are a no-op (004 修复).
    /// 004 修复: routes through the editor's Coordinator so the semantic
    /// pipeline commits the canonical document and registers undo
    /// (attribute-only edits never fire textDidChange); bare NSTextViews
    /// (tests) fall back to the applier directly.
    /// 2026-08-14: in the cross-block mode the marks apply to EVERY
    /// selected block (each block's editor already holds its segment as
    /// its selection — no range rewrite, so the mode is not disturbed).
    public func applyMarks(_ marks: Set<RichTextMark>) {
        guard richTextEditable else { return }
        if let crossBlockSelection, !crossBlockSelection.selections.isEmpty {
            for entry in crossBlockSelection.selections {
                guard let editor = EditorRegistry.textView(for: entry.blockId) else { continue }
                guard let coordinator = editor.delegate as? RichTextView.Coordinator else { continue }
                coordinator.applyMarks(marks, to: editor)
            }
            return
        }
        guard let textView else { return }
        if let coordinator = textView.delegate as? RichTextView.Coordinator {
            coordinator.applyMarks(marks, to: textView)
        } else {
            RichTextMarkApplier.applyMarks(marks, to: textView)
        }
    }

    public func invalidate() {
        isTextSelected = false
        hasFocus = false
        richTextEditable = true
        caretOffset = nil
        selectedRange = nil
        selectionRectInWindow = nil
        focusedSpecialBlockId = nil
        crossBlockSelection = nil
        textView = nil
        focusedTextView = nil
        EditorSelectionContext.bridges[noteId] = nil
        EditorSelectionContext.registry[noteId] = nil
        EditorRegistry.clear()
    }
}
