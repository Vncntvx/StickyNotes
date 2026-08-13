import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Block grid layout tests (004 修复 2026-08-13, P1-3/P1-4)
//
// ONE owner per spacing axis: the block list's stack spacing owns the
// inter-block rhythm (no per-block vertical padding), and blocks align to
// the paper's body-text left edge (the container adds no horizontal inset
// of its own — the paper inset feeds every block).

@MainActor
@Suite struct BlockGridLayoutTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000031")!

    // MARK: single-source metrics

    @Test
    func containerOwnsNoPadding() {
        #expect(BlockLayoutMetrics.horizontalInset == 0,
                "blocks align to the body-text edge — the container adds no horizontal inset")
        #expect(BlockLayoutMetrics.blockVerticalPadding == 0,
                "the block list owns the inter-block rhythm — no per-block vertical padding")
        #expect(BlockLayoutMetrics.interBlockSpacing == 10,
                "the list's stack spacing is the single inter-block source")
    }

    // MARK: laid-out geometry (headless NSHostingView)

    /// Hosts [primary rich-text "hello", code block] at 420×600 and lays
    /// the tree out — same pipeline as EditorLayoutTests.
    private func makeHosting() -> NSHostingView<RichTextBlockView> {
        let noteId = UUID()
        let blocks = [
            Block(
                noteId: noteId, kind: .richText, sortKey: 0,
                payload: .richText(RichTextDocument(text: "hello", paragraphs: [])),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                noteId: noteId, kind: .code, sortKey: 1024,
                payload: .code(CodePayload(text: "let x = 1", language: nil)),
                lastModifiedDeviceId: Self.deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: Self.deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return hosting
    }

    private func collectTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for sub in view.subviews { found += collectTextViews(in: sub) }
        return found
    }

    private func frameInHosting(_ view: NSView, _ hosting: NSView) -> NSRect {
        view.convert(view.bounds, to: hosting)
    }

    @Test
    func codeBlockAlignsToBodyTextEdge() throws {
        let hosting = makeHosting()
        let textViews = collectTextViews(in: hosting)
        let codeEditor = try #require(textViews.first { $0 is CodeEditorTextView },
                                      "code editor not realized")
        let primary = try #require(textViews.first { !($0 is CodeEditorTextView) },
                                   "primary editor not realized")

        let primaryFrame = frameInHosting(primary, hosting)
        let codeFrame = frameInHosting(codeEditor, hosting)

        // The code editor's leading edge = the body-text edge + the card's
        // OWN (interior) padding only — before the fix the container added
        // another 14pt on top.
        let delta = codeFrame.minX - primaryFrame.minX
        #expect(abs(delta - 8) < 2,
                "code sits at the body edge + card-internal padding only, got Δ\(delta)")

        // Vertical: primary bottom → code card top = the paper stack's
        // spacing only (the card adds its 8pt interior padding above the
        // editor; no per-block vertical container padding on top).
        let cardTop = codeFrame.minY - 8
        let gap = cardTop - primaryFrame.maxY
        #expect(abs(gap - 8) < 2.5,
                "primary→code gap = the stack spacing only, got \(gap)")
    }
}
