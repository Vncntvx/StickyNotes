import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Todo alignment determinism (PR1 Steps 2-3, 2026-08-14)
//
// Invariant (actual first-line baseline + nominal body optical offset):
//
//   |checkboxCenter - (todoTop + inset + realBaseline
//                      - (nominalAsc + nominalDesc) / 2)| <= 1pt
//
// in TODO-ROW-RELATIVE coordinates — never absolute view positions. The
// matrix covers line counts x presets x text shapes, plus the restyle
// toggle (the publish-after-mutation fix), rapid preset toggling (async
// @State churn), first-character reformatting (B semantics: the nominal
// offset never changes) and the insertion transition.

@MainActor
@Suite struct TodoAlignmentDeterminismTests {

    private let deviceId = UUID(uuidString: "e1000000-0000-4000-8000-000000000001")!

    nonisolated private static let texts = [
        "single line todo",
        "这是多行 todo 内容\n第二行内容\n第三行内容",
        "hello 世界 mixed\nnext line",
        "✅ 完成 emoji 首行\nsecond",
    ]

    // MARK: - Harness

    private func typography(_ preset: TextSpacingPreset) -> EditorTypography {
        EditorTypography(fontPreference: nil, textSpacing: preset, textSize: 13)
    }

    private struct RowHarness {
        let hosting: NSHostingView<AnyView>
        let noteId: UUID
        let todoBlockId: UUID
        let todoId: UUID
        let item: TodoItem
        let blocks: [Block]
        let typography: EditorTypography
    }

    /// Hosts [primary rich-text, todo] and returns the hosting view + the
    /// todo editor (content-sized; the primary carries a plain line).
    private func makeRow(
        todoText: String,
        typography: EditorTypography
    ) -> RowHarness {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let blocks = [
            Block(
                noteId: noteId, kind: .richText, sortKey: 0,
                payload: .richText(.plain("body")),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: .plain(todoText))),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let hosting = NSHostingView(rootView: AnyView(paper(blocks: blocks, typography: typography, item: item, noteId: noteId)))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return RowHarness(
            hosting: hosting, noteId: noteId, todoBlockId: todoBlockId, todoId: todoId,
            item: item, blocks: blocks, typography: typography
        )
    }

    private func paper(
        blocks: [Block],
        typography: EditorTypography,
        item: TodoItem?,
        noteId: UUID
    ) -> RichTextBlockView {
        RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            editorTypography: typography,
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
    }

    private func collectTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for sub in view.subviews { found += collectTextViews(in: sub) }
        return found
    }

    private func todoEditor(_ hosting: NSView, text: String) -> NSTextView {
        collectTextViews(in: hosting).first { $0.string == text }!
    }

    /// The current alignment deviation: checkbox center vs the formula
    /// target (actual baseline - nominal offset), in row-relative terms.
    private func deviation(
        hosting: NSView,
        todoEditor: NSTextView,
        typography: EditorTypography
    ) -> CGFloat {
        let layoutManager = todoEditor.layoutManager!
        layoutManager.ensureLayout(for: todoEditor.textContainer!)
        let todoFrame = todoEditor.convert(todoEditor.bounds, to: hosting)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let baseline = fragment.minY + layoutManager.location(forGlyphAt: 0).y
        let alignmentFont = NoteFontResolver(preference: typography.fontPreference)
            .nominalBodyFont(size: typography.textSize)
        let expected = todoFrame.minY
            + todoEditor.textContainerInset.height
            + baseline
            - (alignmentFont.ascender + alignmentFont.descender) / 2

        // The checkbox's visual center — the marker backing view closest to
        // the first-line target (the checkbox is the ONLY view aligned to
        // it; the insertion-control overlay can sit at the same leading
        // edge and is filtered by proximity).
        var candidates: [NSRect] = []
        func walk(_ v: NSView) {
            let f = v.convert(v.bounds, to: hosting)
            if v !== todoEditor, f.width > 4, f.width <= 30,
               f.maxX <= todoFrame.minX + 1,
               f.minY < todoFrame.maxY, f.maxY > todoFrame.minY {
                candidates.append(f)
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(hosting)
        guard let center = candidates.map({ $0.midY }).min(by: { lhs, rhs in
            abs(lhs - expected) < abs(rhs - expected)
        }) else {
            return .greatestFiniteMagnitude
        }
        return abs(center - expected)
    }

    /// Polls layout + the deferred async @State write until the row settles.
    private func pollConvergence(
        _ hosting: NSView,
        todoEditor: NSTextView,
        typography: EditorTypography,
        attempts: Int = 50
    ) async -> CGFloat {
        var last = CGFloat.greatestFiniteMagnitude
        for _ in 0..<attempts {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            last = deviation(hosting: hosting, todoEditor: todoEditor, typography: typography)
            if last < 1 { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return last
    }

    // MARK: - Matrix: line counts x presets x text shapes

    @Test(arguments: Self.texts, [TextSpacingPreset.compact, .standard, .relaxed])
    func checkboxAlignsToFirstLineCenter(text: String, preset: TextSpacingPreset) async {
        let row = makeRow(todoText: text, typography: typography(preset))
        let last = await pollConvergence(
            row.hosting, todoEditor: todoEditor(row.hosting, text: text), typography: row.typography
        )
        #expect(last < 1,
                "checkbox must align to the first-line typographic center for \"\(text)\" @ \(preset) (Δ\(last))")
    }

    // MARK: - Restyle toggle (publish-after-mutation fix)

    @Test
    func restyleToggleKeepsAlignment() async {
        let text = "切换后的排版保持对齐\n第二行"
        let row = makeRow(todoText: text, typography: typography(.standard))
        let editor = todoEditor(row.hosting, text: text)
        let before = await pollConvergence(row.hosting, todoEditor: editor, typography: row.typography)
        #expect(before < 1, "precondition: aligned at standard (Δ\(before))")

        // The production flow: the typography VALUE changes → the SAME view
        // re-renders in place with the new value (in-place restyle path —
        // same block identities, so the same NSTextView is updated).
        row.hosting.rootView = AnyView(paper(
            blocks: row.blocks, typography: typography(.relaxed), item: row.item, noteId: row.noteId
        ))
        let relaxedEditor = todoEditor(row.hosting, text: text)
        let after = await pollConvergence(row.hosting, todoEditor: relaxedEditor, typography: typography(.relaxed))
        #expect(after < 1,
                "a preset toggle must keep the checkbox aligned (Δ\(after))")

        row.hosting.rootView = AnyView(paper(
            blocks: row.blocks, typography: typography(.standard), item: row.item, noteId: row.noteId
        ))
        let backEditor = todoEditor(row.hosting, text: text)
        let back = await pollConvergence(row.hosting, todoEditor: backEditor, typography: typography(.standard))
        #expect(back < 1,
                "toggling back must also stay aligned (Δ\(back))")
    }

    // MARK: - Rapid preset toggling (async @State churn)

    @Test
    func rapidPresetTogglingConverges() async {
        let text = "快速切换后的最终对齐\n第二行"
        let row = makeRow(todoText: text, typography: typography(.standard))
        let sequence: [TextSpacingPreset] = [.standard, .relaxed, .compact, .standard]
        for preset in sequence {
            row.hosting.rootView = AnyView(paper(
                blocks: row.blocks, typography: typography(preset), item: row.item, noteId: row.noteId
            ))
            row.hosting.layoutSubtreeIfNeeded()
            row.hosting.displayIfNeeded()
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        let editor = todoEditor(row.hosting, text: text)
        let last = await pollConvergence(row.hosting, todoEditor: editor, typography: typography(.standard))
        #expect(last < 1,
                "rapid preset toggling must not leave stale geometry (final Δ\(last))")
    }

    // MARK: - First-character reformatting (B semantics)

    @Test
    func firstCharacterBoldDoesNotMoveCheckbox() async {
        let text = "bold first char todo"
        let row = makeRow(todoText: text, typography: typography(.standard))
        let editor = todoEditor(row.hosting, text: text)
        let before = await pollConvergence(row.hosting, todoEditor: editor, typography: row.typography)
        #expect(before < 1, "precondition: aligned (Δ\(before))")

        let storage = editor.textStorage!
        let baseFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            ?? NSFont.systemFont(ofSize: 13)
        let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        storage.addAttribute(.font, value: bold, range: NSRange(location: 0, length: 1))
        row.hosting.layoutSubtreeIfNeeded()
        row.hosting.displayIfNeeded()

        let after = deviation(hosting: row.hosting, todoEditor: editor, typography: row.typography)
        #expect(after < 1,
                "bold on the first character must keep the nominal offset alignment (Δ\(after))")
    }

    @Test
    func firstCharacterInlineCodeDoesNotMoveCheckbox() async {
        let text = "code first char todo"
        let row = makeRow(todoText: text, typography: typography(.standard))
        let editor = todoEditor(row.hosting, text: text)
        let before = await pollConvergence(row.hosting, todoEditor: editor, typography: row.typography)
        #expect(before < 1, "precondition: aligned (Δ\(before))")

        let storage = editor.textStorage!
        storage.addAttribute(
            .font,
            value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            range: NSRange(location: 0, length: 1)
        )
        row.hosting.layoutSubtreeIfNeeded()
        row.hosting.displayIfNeeded()

        let after = deviation(hosting: row.hosting, todoEditor: editor, typography: row.typography)
        #expect(after < 1,
                "inline code on the first character must keep the nominal offset alignment (Δ\(after))")
    }

    // MARK: - Insertion transition

    @Test
    func insertedTodoConvergesAligned() async {
        // The production insertion flow: the row first hosts ONLY the
        // primary, then the todo block lands (same view identity).
        let noteId = UUID()
        let bodyText = "body before insertion"
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let todoText = "插入后的首行对齐\n第二行"

        let before = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            editorTypography: typography(.standard),
            blocks: [
                Block(noteId: noteId, kind: .richText, sortKey: 0,
                      payload: .richText(.plain(bodyText)),
                      lastModifiedDeviceId: deviceId)
            ],
            onBlocksChanged: { _ in }
        )
        let hosting = NSHostingView(rootView: before)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()

        let after = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            editorTypography: typography(.standard),
            blocks: [
                Block(noteId: noteId, kind: .richText, sortKey: 0,
                      payload: .richText(.plain(bodyText)),
                      lastModifiedDeviceId: deviceId),
                Block(id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                      payload: .todo(TodoPayload(todoId: todoId, richText: .plain(todoText))),
                      lastModifiedDeviceId: deviceId)
            ],
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        hosting.rootView = after
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editor = todoEditor(hosting, text: todoText)
        let last = await pollConvergence(hosting, todoEditor: editor, typography: typography(.standard))
        #expect(last < 1,
                "a freshly inserted todo must converge aligned (Δ\(last))")
    }
}
