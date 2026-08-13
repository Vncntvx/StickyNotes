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

    // MARK: - Width reflow (Goal A / Test Group A+B, 2026-08-13)
    //
    // The width-reflow regression: an NSTextView's intrinsic height must
    // follow its frame width — narrowing wraps the text into more lines
    // (taller intrinsic), widening releases them. The following block must
    // track the primary's bottom at every width. Prior to the fix the
    // height stayed glued to the first measured width.

    /// Hosts [primary rich-text (long, soft-wrap only), todo] with a width
    /// that the test resizes. The long body has NO hard newlines.
    private func makeWidthReflowHosting(bodyText: String) -> NSHostingView<RichTextBlockView> {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [
            Block(
                noteId: noteId, kind: .richText, sortKey: 0,
                payload: .richText(.plain(bodyText)),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: RichTextDocument.plain(""))),
                lastModifiedDeviceId: Self.deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: Self.deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return hosting
    }

    private func relayout(_ hosting: NSHostingView<RichTextBlockView>, width: CGFloat) {
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }

    /// The primary editor + the following todo editor's frames and the
    /// primary's intrinsic height at the hosting view's current width.
    private func measureReflow(
        _ hosting: NSHostingView<RichTextBlockView>,
        bodyText: String
    ) throws -> (primaryFrame: NSRect, todoFrame: NSRect, intrinsic: CGFloat) {
        let textViews = collectTextViews(in: hosting)
        let primary = try #require(
            textViews.first { $0.string == bodyText },
            "primary editor not realized"
        )
        let todoEditor = try #require(
            textViews.first { $0.string.isEmpty },
            "todo editor not realized"
        )
        return (
            frameInHosting(primary, hosting),
            frameInHosting(todoEditor, hosting),
            primary.intrinsicContentSize.height
        )
    }

    @Test
    func bodyReflowsAndPushesBlocksOnWidthChange() throws {
        let bodyText = String(
            repeating: "The quick brown fox jumps over the lazy dog. ", count: 8
        )
        let hosting = makeWidthReflowHosting(bodyText: bodyText)

        let wide = try measureReflow(hosting, bodyText: bodyText)
        relayout(hosting, width: 420)
        let medium = try measureReflow(hosting, bodyText: bodyText)
        relayout(hosting, width: 320)
        let narrow = try measureReflow(hosting, bodyText: bodyText)
        relayout(hosting, width: 900)
        let back = try measureReflow(hosting, bodyText: bodyText)

        // Width decreases → the soft-wrapped text pays more lines.
        #expect(medium.intrinsic > wide.intrinsic + 1,
                "420 must reflow taller than 900 (wide \(wide.intrinsic) → \(medium.intrinsic))")
        #expect(narrow.intrinsic > medium.intrinsic + 1,
                "320 must reflow taller than 420 (\(medium.intrinsic) → \(narrow.intrinsic))")
        // Width restored → the height releases back to the original value.
        #expect(back.intrinsic < narrow.intrinsic - 1,
                "back to 900 must release the narrow height (\(narrow.intrinsic) → \(back.intrinsic))")
        #expect(abs(back.intrinsic - wide.intrinsic) < 2,
                "the height at 900 must be stable across the round trip")

        // The SwiftUI-applied frame must match the fresh intrinsic at every
        // width — a stale cached measurement leaves the frame short.
        #expect(abs(wide.primaryFrame.height - wide.intrinsic) < 2,
                "frame must apply the intrinsic height at 900")
        #expect(abs(narrow.primaryFrame.height - narrow.intrinsic) < 2,
                "frame must apply the intrinsic height at 320")

        // The following block tracks the primary's bottom at every width
        // and never overlaps it.
        for (frame, todo, name) in [
            (wide.primaryFrame, wide.todoFrame, "900"),
            (medium.primaryFrame, medium.todoFrame, "420"),
            (narrow.primaryFrame, narrow.todoFrame, "320"),
        ] {
            #expect(todo.minY >= frame.maxY - 0.5,
                    "no overlap at \(name): todo.minY \(todo.minY) vs body.maxY \(frame.maxY)")
        }
        #expect(narrow.todoFrame.minY > medium.todoFrame.minY + 1,
                "the todo must move DOWN when the body reflows at 320")
        #expect(medium.todoFrame.minY > wide.todoFrame.minY + 1,
                "the todo must move DOWN when the body reflows at 420")
    }

    // MARK: - Document order (Goal 顺序 / Test Group C, 2026-08-13)
    //
    // The visual order must equal the sortKey order. Prior to the fix the
    // FIRST rich-text block was pinned above every other block regardless
    // of its sortKey.

    @Test
    func visualOrderMatchesSortKeyOrder() throws {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 100,
            depth: 0, lastModifiedDeviceId: Self.deviceId
        )
        let blocks = [
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 100,
                payload: .todo(TodoPayload(todoId: todoId, richText: RichTextDocument.plain(""))),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                noteId: noteId, kind: .richText, sortKey: 200,
                payload: .richText(.plain("middle paragraph")),
                lastModifiedDeviceId: Self.deviceId
            ),
            Block(
                noteId: noteId, kind: .code, sortKey: 300,
                payload: .code(CodePayload(text: "let order = 3", language: nil)),
                lastModifiedDeviceId: Self.deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: Self.deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        let todoEditor = try #require(
            textViews.first { $0.string.isEmpty },
            "todo editor not realized"
        )
        let richEditor = try #require(
            textViews.first { $0.string == "middle paragraph" },
            "rich-text editor not realized"
        )
        let codeEditor = try #require(
            textViews.first { $0 is CodeEditorTextView },
            "code editor not realized"
        )
        let todoFrame = frameInHosting(todoEditor, hosting)
        let richFrame = frameInHosting(richEditor, hosting)
        let codeFrame = frameInHosting(codeEditor, hosting)

        #expect(richFrame.minY > todoFrame.minY,
                "sortKey 200 (richText) must render BELOW sortKey 100 (todo): rich \(richFrame.minY) vs todo \(todoFrame.minY)")
        #expect(codeFrame.minY > richFrame.minY,
                "sortKey 300 (code) must render below sortKey 200 (richText): code \(codeFrame.minY) vs rich \(richFrame.minY)")
    }

    // MARK: - Insertion control stability (Test Group G, 004 修复
    // 2026-08-14, P0)
    //
    // The insertion control must never participate in the vertical flow:
    // its visibility flips via opacity only, so a marker below it keeps
    // its layout origin.

    private struct FrameProbe: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    @Test
    func insertionControlVisibilityNeverShiftsLayout() throws {
        final class Toggle: ObservableObject {
            @Published var visible = false
        }
        struct Harness: View {
            @ObservedObject var toggle: Toggle
            var body: some View {
                VStack(spacing: 0) {
                    BlockInsertionControl(
                        isCursorLineHovered: $toggle.visible,
                        isTextSelected: .constant(false),
                        isIMEComposing: .constant(false)
                    )
                    FrameProbe().frame(width: 100, height: 40)
                }
            }
        }
        let toggle = Toggle()
        let hosting = NSHostingView(rootView: Harness(toggle: toggle))
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        func probeFrame() throws -> NSRect {
            var probe: NSView?
            func find(_ view: NSView) {
                if view !== hosting, view.frame.width == 100, view.frame.height == 40 {
                    probe = view
                }
                for sub in view.subviews { find(sub) }
            }
            find(hosting)
            guard let probe else {
                struct Failed: Error {}
                throw Failed()
            }
            return probe.convert(probe.bounds, to: hosting)
        }

        let hidden = try probeFrame()
        toggle.visible = true
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let shown = try probeFrame()
        toggle.visible = false
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let hiddenAgain = try probeFrame()

        #expect(shown.minY == hidden.minY,
                "showing the control must not move the content below it (\(hidden.minY) → \(shown.minY))")
        #expect(hiddenAgain.minY == hidden.minY,
                "hiding the control must not move the content below it (\(hidden.minY) → \(hiddenAgain.minY))")
    }
}
