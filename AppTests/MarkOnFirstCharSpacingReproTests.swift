import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Mark-on-first-char spacing repro (user report 2026-08-14)
//
// Reported: formatting the FIRST character of a todo (⌘B bold / inline
// code / emoji first char) keeps the checkbox aligned (PR1 ✓) but the
// note's TEXT SPACING visibly changes. This diagnostic suite measures
// every presentation metric of the BODY and TODO editors before/after the
// mark commit and pins down exactly what moves.

@MainActor
@Suite struct MarkOnFirstCharSpacingReproTests {

    private let deviceId = UUID(uuidString: "e3000000-0000-4000-8000-000000000003")!

    private func makeRow(
        bodyText: String,
        todoText: String
    ) -> (hosting: NSHostingView<AnyView>, bodyEditor: NSTextView, todoEditor: NSTextView) {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let typography = EditorTypography(fontPreference: .systemDefault, textSpacing: .relaxed, textSize: 13)
        let blocks = [
            Block(
                noteId: noteId, kind: .richText, sortKey: 0,
                payload: .richText(.plain(bodyText)),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: .plain(todoText))),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            editorTypography: typography,
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let editors = collectTextViews(in: hosting)
        let body = editors.first { $0.string == bodyText }!
        let todo = editors.first { $0.string == todoText }!
        return (hosting, body, todo)
    }

    private func collectTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for sub in view.subviews { found += collectTextViews(in: sub) }
        return found
    }

    private struct Metrics: CustomStringConvertible, Equatable {
        let paragraphLineSpacing: CGFloat?
        let fontFamilies: [String]
        let fragmentHeights: [CGFloat]
        let intrinsicHeight: CGFloat
        let glyphZeroFamily: String
        let glyphZeroSize: CGFloat

        var description: String {
            "paraSpacing=\(String(describing: paragraphLineSpacing)) families=\(fontFamilies) fragHeights=\(fragmentHeights) intrinsic=\(intrinsicHeight) glyph0=\(glyphZeroFamily)@\(glyphZeroSize)"
        }
    }

    private func metrics(of editor: NSTextView) -> Metrics {
        let storage = editor.textStorage!
        let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        var families: [String] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                families.append(font.familyName ?? "-")
            }
        }
        let lm = editor.layoutManager!
        lm.ensureLayout(for: editor.textContainer!)
        var heights: [CGFloat] = []
        var glyphIndex = 0
        while glyphIndex < lm.numberOfGlyphs {
            var eff = NSRange(location: 0, length: 0)
            heights.append(lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &eff).height)
            glyphIndex = NSMaxRange(eff)
        }
        let glyphZero = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        return Metrics(
            paragraphLineSpacing: style?.lineSpacing,
            fontFamilies: families,
            fragmentHeights: heights,
            intrinsicHeight: editor.intrinsicContentSize.height,
            glyphZeroFamily: glyphZero?.familyName ?? "-",
            glyphZeroSize: glyphZero?.pointSize ?? 0
        )
    }

    private func settle(_ hosting: NSView, turns: Int = 25) async {
        for _ in 0..<turns {
            try? await Task.sleep(nanoseconds: 20_000_000)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
    }

    private func runMarkScenario(
        todoText: String,
        mark: RichTextMark
    ) async -> (bodyBefore: Metrics, bodyAfter: Metrics, todoBefore: Metrics, todoAfter: Metrics) {
        let row = makeRow(
            bodyText: "这是正文第一行 hello world 混排内容\n第二行正文内容",
            todoText: todoText
        )
        await settle(row.hosting)
        let bodyBefore = metrics(of: row.bodyEditor)
        let todoBefore = metrics(of: row.todoEditor)

        row.todoEditor.setSelectedRange(NSRange(location: 0, length: 1))
        if let coordinator = row.todoEditor.delegate as? RichTextView.Coordinator {
            coordinator.applyMarks([mark], to: row.todoEditor)
        }
        await settle(row.hosting)
        return (bodyBefore, metrics(of: row.bodyEditor), todoBefore, metrics(of: row.todoEditor))
    }

    // MARK: - Diagnostics: what exactly moves?

    @Test(arguments: ["✅ 完成 todo 内容\n第二行", "hello world todo\nsecond line"])
    func boldOnFirstCharImpact(todoText: String) async {
        let r = await runMarkScenario(todoText: todoText, mark: .bold)
        print("BOLD \(todoText)\n  body before: \(r.bodyBefore)\n  body after : \(r.bodyAfter)\n  todo before: \(r.todoBefore)\n  todo after : \(r.todoAfter)")
        #expect(r.bodyBefore == r.bodyAfter,
                "BODY must be untouched by a todo-side bold commit:\n\(r.bodyBefore)\nvs\n\(r.bodyAfter)")
    }

    @Test(arguments: ["✅ 完成 todo 内容\n第二行", "hello world todo\nsecond line"])
    func inlineCodeOnFirstCharImpact(todoText: String) async {
        let r = await runMarkScenario(todoText: todoText, mark: .inlineCode)
        print("INLINECODE \(todoText)\n  body before: \(r.bodyBefore)\n  body after : \(r.bodyAfter)\n  todo before: \(r.todoBefore)\n  todo after : \(r.todoAfter)")
        #expect(r.bodyBefore == r.bodyAfter,
                "BODY must be untouched by a todo-side inline-code commit:\n\(r.bodyBefore)\nvs\n\(r.bodyAfter)")
    }
}
