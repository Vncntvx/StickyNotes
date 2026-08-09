import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import EditorCore
import Persistence
@testable import StickyNotes

// MARK: - Editor layout regression (2026-08-09 manual acceptance)
//
// Manual acceptance found the initial caret of a note window near the BOTTOM
// of the window (screenshot image-8591e6b5.png: text baseline at ~72% of the
// ~598 pt restored-frame window, no scroll indicator) even though the editor
// slot is a fixed 300 pt top-aligned slot inside a ScrollView
// (RichTextBlockView). Static analysis says the text must sit at the top;
// these tests lay the view out headlessly to measure the NSTextView's real
// frame and catch any stretch to the viewport.

@MainActor
@Suite struct EditorLayoutTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000030")!

    private func makeHosting(text: String, height: CGFloat) -> NSHostingView<RichTextBlockView> {
        let doc = RichTextDocument(text: text, paragraphs: [])
        let block = Block(
            noteId: UUID(),
            kind: .richText,
            sortKey: 0,
            payload: .richText(doc),
            lastModifiedDeviceId: Self.deviceId
        )
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: Self.deviceId),
            blocks: [block],
            onBlocksChanged: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: height)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return hosting
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    @Test
    func editorSlotLayoutInsideRealWindowPipeline() throws {
        // 真实窗口管线：NSHostingView attach 到 NSWindow 后 layout。
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: Note(lastModifiedDeviceId: Self.deviceId),
            blocks: [Block(
                noteId: UUID(),
                kind: .richText,
                sortKey: 0,
                payload: .richText(RichTextDocument(text: "这是初始输入位置", paragraphs: [])),
                lastModifiedDeviceId: Self.deviceId
            )],
            onBlocksChanged: { _ in }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 598),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.displayIfNeeded()

        let textView = try #require(findTextView(in: hosting))
        var scrollInfo = ""
        if let scroll = firstScrollView(in: hosting) {
            scrollInfo = "scrollView.contentSize=\(scroll.contentSize) docView.frame=\(scroll.documentView?.frame ?? .zero)"
        }
        print("DEBUG [EditorLayoutTests] windowPipeline textView.frame=\(textView.frame) hosting.frame=\(hosting.frame) hosting.fittingSize=\(hosting.fittingSize) \(scrollInfo)")
        let minY = textView.frame.minY
        let maxY = textView.frame.maxY
        #expect(minY < 200, "editor must sit near the top, got minY=\(minY)")
        #expect(maxY < hosting.frame.height - 100, "editor must end above the bottom, got maxY=\(maxY)")
        window.close()
    }

    @Test
    func editorSlotStaysAtTopInsideLargeWindow() throws {
        // 模拟用户恢复的大窗口（截图4 约 598 pt 高）。
        let hosting = makeHosting(text: "这是初始输入位置", height: 598)
        let textView = try #require(findTextView(in: hosting))
        var scrollInfo = ""
        if let scroll = firstScrollView(in: hosting) {
            scrollInfo = "scrollView.contentSize=\(scroll.contentSize) docView.frame=\(scroll.documentView?.frame ?? .zero)"
        }
        print("DEBUG [EditorLayoutTests] textView.frame=\(textView.frame) hosting.frame=\(hosting.frame) hosting.fittingSize=\(hosting.fittingSize) \(scrollInfo)")
        // 编辑器槽是顶部对齐的固定区域（minHeight 300）。
        #expect(textView.frame.height <= 400,
                "editor must not stretch to the viewport, got height=\(textView.frame.height)")
        #expect(textView.frame.minY < 200,
                "editor must sit near the top, got minY=\(textView.frame.minY) height=\(textView.frame.height)")
        #expect(textView.frame.maxY < hosting.frame.height - 100,
                "editor must end well above the bottom edge, got maxY=\(textView.frame.maxY)")
    }

    @Test
    func editorSlotUnchangedAfterWindowResize() throws {
        // 恢复帧发生在窗口创建之后：先按默认 480 布局，再拉伸到 598。
        let hosting = makeHosting(text: "这是初始输入位置", height: 480)
        _ = try #require(findTextView(in: hosting))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 598)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let textView = try #require(findTextView(in: hosting))
        #expect(textView.frame.height <= 400,
                "resize must not stretch the editor, got height=\(textView.frame.height)")
        #expect(textView.frame.minY < 200,
                "resize must keep the editor at the top, got minY=\(textView.frame.minY)")
    }
}
