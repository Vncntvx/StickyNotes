import Testing
import Foundation
import AppKit
import Domain
@testable import StickyNotes

// MARK: - Cross-block drag selection tests (2026-08-14)
//
// 拖选跨块（Q1-A）：鼠标从一块拖出边界进入相邻块时，两块同时形成选区
// （当前块钉住 [起点, 块尾] / [0, 起点]，目标块随拖入点更新），bridge 进入
// 跨块模式；拖回本块恢复单块默认拖选。方向向下/向上双向支持。

@MainActor
@Suite struct CrossBlockDragSelectionTests {

    private struct HostedPair {
        let window: NSWindow
        let bridge: EditorSelectionBridge
        let upper: (coordinator: RichTextView.Coordinator, textView: NotePaperTextView, blockId: UUID)
        let lower: (coordinator: RichTextView.Coordinator, textView: NotePaperTextView, blockId: UUID)
    }

    private func makeHostedPair(upperText: String, lowerText: String) -> HostedPair {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let bridge = EditorSelectionBridge(noteId: UUID())

        func makeEditor(text: String, frame: NSRect, blockId: UUID)
            -> (RichTextView.Coordinator, NotePaperTextView) {
            let editor = RichTextView(
                document: .plain(text),
                editorTypography: .system(textSize: 13),
                onCommit: { _ in }
            )
            let coordinator = RichTextView.Coordinator(editor)
            let textView = NotePaperTextView(frame: frame)
            textView.isRichText = true
            textView.string = text
            textView.font = NSFont.systemFont(ofSize: 13)
            textView.delegate = coordinator
            textView.blockKeyHandler = coordinator
            coordinator.attach(textView, bridge: bridge, blockId: blockId)
            EditorRegistry.register(textView, for: blockId)
            window.contentView?.addSubview(textView)
            return (coordinator, textView)
        }

        let upperId = UUID()
        let lowerId = UUID()
        let upper = makeEditor(text: upperText, frame: NSRect(x: 10, y: 260, width: 380, height: 200), blockId: upperId)
        let lower = makeEditor(text: lowerText, frame: NSRect(x: 10, y: 40, width: 380, height: 200), blockId: lowerId)
        window.makeKeyAndOrderFront(nil)
        // Force a real layout pass — characterIndexForInsertion degrades to
        // the text end when the storage was never laid out.
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        for view in [upper.1, lower.1] {
            if let layoutManager = view.layoutManager, let container = view.textContainer {
                layoutManager.ensureLayout(for: container)
            }
        }
        return HostedPair(window: window, bridge: bridge, upper: (upper.0, upper.1, upperId), lower: (lower.0, lower.1, lowerId))
    }

    private func dragEvent(in window: NSWindow, to point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    @Test
    func draggingFromUpperIntoLowerSelectsBothBlocks() {
        let pair = makeHostedPair(upperText: "Hello upper", lowerText: "lower world")
        defer { pair.window.close() }
        // The drag anchor: caret at offset 3 in the upper block.
        pair.upper.textView.setSelectedRange(NSRange(location: 3, length: 0))

        // Drag to a point on the LOWER block's first text line (window
        // coordinates: lower frame is (10, 40); its text line sits ~12-28pt
        // above the frame's BOTTOM edge in unflipped terms — the text view
        // is flipped, so the line is at window y ≈ 220).
        let event = dragEvent(in: pair.window, to: NSPoint(x: 50, y: 220))
        pair.upper.textView.mouseDragged(with: event)

        // The upper block pins [anchor, end]; the lower selects [0, drop].
        let upperLength = (pair.upper.textView.string as NSString).length
        #expect(pair.upper.textView.selectedRange() == NSRange(location: 3, length: upperLength - 3),
                "the source block pins its selection to the end")
        #expect(pair.lower.textView.selectedRange().location == 0,
                "the target block selects from its start")
        #expect(pair.lower.textView.selectedRange().length > 0,
                "the target block selects up to the drop point")
        #expect(pair.bridge.crossBlockSelection?.selections.count == 2,
                "the drag enters the cross-block mode")
    }

    @Test
    func draggingFromLowerIntoUpperSelectsBothBlocks() {
        let pair = makeHostedPair(upperText: "Hello upper", lowerText: "lower world")
        defer { pair.window.close() }
        // The drag anchor: caret at offset 2 in the LOWER block.
        pair.lower.textView.setSelectedRange(NSRange(location: 2, length: 0))

        // A point on the UPPER block's first text line (upper frame is
        // (10, 260); flipped line at window y ≈ 440).
        let event = dragEvent(in: pair.window, to: NSPoint(x: 70, y: 440))
        pair.lower.textView.mouseDragged(with: event)

        #expect(pair.lower.textView.selectedRange() == NSRange(location: 0, length: 2),
                "dragging upward pins the source block to [0, anchor]")
        let upperLength = (pair.upper.textView.string as NSString).length
        let upperSelection = pair.upper.textView.selectedRange()
        #expect(upperSelection.length == upperLength - upperSelection.location,
                "the target block selects from the drop point to its end")
        #expect(pair.bridge.crossBlockSelection?.selections.count == 2,
                "the drag enters the cross-block mode")
    }

    @Test
    func draggingBackIntoSourceBlockStaysSingleBlock() {
        let pair = makeHostedPair(upperText: "Hello upper", lowerText: "lower world")
        defer { pair.window.close() }
        pair.upper.textView.setSelectedRange(NSRange(location: 2, length: 0))

        // Drag to a point INSIDE the upper block (no crossing) — the
        // default drag continues.
        let event = dragEvent(in: pair.window, to: NSPoint(x: 130, y: 360))
        pair.upper.textView.mouseDragged(with: event)

        #expect(pair.bridge.crossBlockSelection == nil,
                "no boundary crossing → no cross-block mode")
        #expect(pair.lower.textView.selectedRange().length == 0,
                "the other block is untouched")
    }
}
