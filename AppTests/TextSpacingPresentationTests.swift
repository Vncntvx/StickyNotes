import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Text spacing presentation tests (Phase 4, 2026-08-14)
//
// The three text-spacing presets are a presentation layer on the editor's
// NSTextStorage (.paragraphStyle.lineSpacing) — never document content.
// Covered: standard writes NOTHING (zero delta from today's metrics); the
// three presets are distinct; Relaxed→Default really REMOVES the old
// style; typingAttributes follow the preset (subsequent input); richText
// and todo text apply while the code block stays untouched; spacing never
// enters the payload / JSON export / Markdown; intrinsic heights reflow
// per preset at 9/13/24 pt; a spacing change commits nothing.

@MainActor
@Suite struct TextSpacingPresentationTests {

    private final class CommitRecorder {
        var documents: [RichTextDocument] = []
    }

    private let deviceId = UUID(uuidString: "e0000000-0000-4000-8000-000000000004")!

    // MARK: - Direct editor harness

    private func makeEditor(
        text: String = "one\ntwo\nthree",
        spacing: TextSpacingPreset = .standard,
        textSize: CGFloat = 13
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NSTextView, recorder: CommitRecorder) {
        let recorder = CommitRecorder()
        let view = RichTextView(
            document: .plain(text),
            editorTypography: EditorTypography(fontPreference: nil, textSpacing: spacing, textSize: textSize),
            onCommit: { recorder.documents.append($0) }
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = text
        textView.delegate = coordinator
        coordinator.applyDocument(.plain(text), typography: view.editorTypography, to: textView)
        return (view, coordinator, textView, recorder)
    }

    private func restyle(
        _ coordinator: RichTextView.Coordinator,
        textView: NSTextView,
        spacing: TextSpacingPreset,
        textSize: CGFloat = 13
    ) {
        let document = RichTextView.Coordinator.canonicalDocument(
            from: textView.attributedString(),
            excludesDisplayStyling: false
        )
        let view = RichTextView(
            document: document,
            editorTypography: EditorTypography(fontPreference: nil, textSpacing: spacing, textSize: textSize),
            onCommit: { _ in }
        )
        coordinator.parent = view
        coordinator.restyleTypographyInPlace(view.editorTypography, document: document, to: textView)
    }

    private func lineSpacing(at index: Int, in textView: NSTextView) -> CGFloat? {
        let style = textView.textStorage?.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
        return style?.lineSpacing
    }

    // MARK: - Storage presentation

    @Test
    func standardPresetWritesNoParagraphStyle() {
        let (_, _, textView, _) = makeEditor(spacing: .standard)
        #expect(lineSpacing(at: 0, in: textView) == nil,
                "standard writes NO paragraph style (zero delta from today's metrics)")
        #expect(textView.typingAttributes[.paragraphStyle] == nil,
                "standard typing attributes carry no paragraph style")
    }

    @Test
    func threePresetsProduceDistinctLineSpacing() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .standard)
        restyle(coordinator, textView: textView, spacing: .compact)
        let compact = lineSpacing(at: 0, in: textView)
        restyle(coordinator, textView: textView, spacing: .relaxed)
        let relaxed = lineSpacing(at: 0, in: textView)
        restyle(coordinator, textView: textView, spacing: .standard)
        let standard = lineSpacing(at: 0, in: textView)
        #expect(compact != nil && relaxed != nil, "compact/relaxed write a paragraph style")
        #expect(compact! < relaxed!, "the presets are distinct (values are visual-tuning prototypes)")
        #expect(standard == nil, "standard restores the attribute-free state")
    }

    @Test
    func relaxedToDefaultRemovesParagraphStyle() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        #expect(lineSpacing(at: 0, in: textView) != nil, "precondition: relaxed applied")
        restyle(coordinator, textView: textView, spacing: .standard)
        #expect(lineSpacing(at: 0, in: textView) == nil,
                "Relaxed→Default must really REMOVE the paragraph style")
        #expect(textView.typingAttributes[.paragraphStyle] == nil,
                "typing attributes drop the style too")
    }

    @Test
    func typingAttributesParagraphStyleFollowsPreset() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .standard)
        restyle(coordinator, textView: textView, spacing: .relaxed)
        #expect((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing != nil,
                "subsequent input inherits the relaxed spacing")
        restyle(coordinator, textView: textView, spacing: .compact)
        #expect((textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing ?? 0 < 0,
                "typing attributes track the compact preset")
        restyle(coordinator, textView: textView, spacing: .standard)
        #expect(textView.typingAttributes[.paragraphStyle] == nil,
                "back to standard: typing attributes drop the style")
    }

    // MARK: - Block coverage (hosting harness)

    private func makeHosting(blocks: [Block], typography: EditorTypography) -> NSHostingView<RichTextBlockView> {
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            editorTypography: typography,
            blocks: blocks,
            onBlocksChanged: { _ in }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        return hosting
    }

    private func allTextViews(in view: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        if let tv = view as? NSTextView { result.append(tv) }
        for sub in view.subviews {
            result.append(contentsOf: allTextViews(in: sub))
        }
        return result
    }

    private func makeRichTextBlock(noteId: UUID, text: String, sortKey: Int = 0) -> Block {
        Block(
            noteId: noteId,
            kind: .richText,
            sortKey: sortKey,
            payload: .richText(.plain(text)),
            lastModifiedDeviceId: deviceId
        )
    }

    @Test
    func spacingAppliesToRichTextAndTodoText() {
        let note = Note(lastModifiedDeviceId: deviceId)
        let typography = EditorTypography(fontPreference: nil, textSpacing: .relaxed, textSize: 13)
        let rich = makeRichTextBlock(noteId: note.id, text: "hello world")
        let todo = Block(
            noteId: note.id,
            kind: .todo,
            sortKey: 1024,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("buy milk"))),
            lastModifiedDeviceId: deviceId
        )
        let editors = allTextViews(in: makeHosting(blocks: [rich, todo], typography: typography))
        #expect(editors.count == 2, "rich-text + todo editors must render (got \(editors.count))")
        for editor in editors {
            let style = editor.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            #expect(style?.lineSpacing != nil,
                    "\(editor.string) must carry the relaxed paragraph style")
        }
    }

    @Test
    func codeBlockTypographyUnchanged() {
        let note = Note(lastModifiedDeviceId: deviceId)
        let typography = EditorTypography(fontPreference: .systemDefault, textSpacing: .relaxed, textSize: 13)
        let rich = makeRichTextBlock(noteId: note.id, text: "hello world")
        let code = Block(
            noteId: note.id,
            kind: .code,
            sortKey: 1024,
            payload: .code(CodePayload(text: "let x = 1", language: "swift")),
            lastModifiedDeviceId: deviceId
        )
        let editors = allTextViews(in: makeHosting(blocks: [rich, code], typography: typography))
        let codeEditor = editors.first { $0.string == "let x = 1" }
        let richEditor = editors.first { $0.string == "hello world" }
        #expect(codeEditor != nil && richEditor != nil, "both editors must render")
        let richStyle = richEditor?.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect(richStyle?.lineSpacing != nil, "precondition: the rich-text editor carries the spacing")
        #expect(codeEditor?.textStorage?.attribute(.paragraphStyle, at: 0, effectiveRange: nil) == nil,
                "the code block never inherits the global spacing")
        let codeFont = codeEditor?.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let family = codeFont?.familyName ?? ""
        #expect(family.localizedCaseInsensitiveContains("mono") || family.localizedCaseInsensitiveContains("courier"),
                "the code font stays monospaced (FR-080)")
        #expect(codeFont?.pointSize == 13, "the code font stays 13pt regardless of typography")
    }

    // MARK: - Zero content footprint

    @Test
    func spacingChangeDoesNotCommitOrAutosave() {
        let (_, coordinator, textView, recorder) = makeEditor(spacing: .standard)
        restyle(coordinator, textView: textView, spacing: .relaxed)
        restyle(coordinator, textView: textView, spacing: .compact)
        #expect(recorder.documents.isEmpty,
                "spacing changes commit nothing (no canonical/autosave traffic)")
        #expect(textView.string == "one\ntwo\nthree", "the string is untouched")
    }

    @Test
    func spacingNotInPayloadNotInJSONExportNotInMarkdown() throws {
        // The canonical document carries no spacing representation.
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        restyle(coordinator, textView: textView, spacing: .relaxed)
        let canonical = RichTextView.Coordinator.canonicalDocument(from: textView.attributedString())
        #expect(canonical.text == "one\ntwo\nthree")
        #expect(canonical.paragraphs.allSatisfy { $0.style == .body },
                "spacing never enters the canonical paragraph model")

        // JSON export: no spacing keys anywhere in the encoded document.
        let noteId = UUID()
        let block = makeRichTextBlock(noteId: noteId, text: "one\ntwo\nthree")
        let note = Note(lastModifiedDeviceId: deviceId)
        let canonicalNote = CanonicalNote(
            id: note.id,
            colorKey: .yellow,
            transparency: 1.0,
            textSize: 13,
            alwaysOnTop: false,
            manualSortKey: 0,
            lifecycleState: .active,
            versionId: UUID(),
            lastModifiedDeviceId: deviceId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            blocks: [CanonicalBlock(
                id: block.id,
                noteId: noteId,
                kind: .richText,
                sortKey: 0,
                parentVersionId: nil,
                lastModifiedDeviceId: deviceId,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
                payload: .richText(.plain("one\ntwo\nthree"))
            )]
        )
        let json = try String(data: NoteDocumentSerializer.encodeDocument(canonicalNote), encoding: .utf8) ?? ""
        #expect(!json.localizedCaseInsensitiveContains("lineSpacing"))
        #expect(!json.localizedCaseInsensitiveContains("textSpacing"))

        // Markdown export: no spacing artifacts.
        let markdown = NoteMarkdownSerializer.markdown(note: note, blocks: [block])
        #expect(!markdown.contains("spacing"), "markdown ignores visual styles")
    }

    // MARK: - Intrinsic reflow

    @Test
    func intrinsicHeightTracksSpacingAt9_13_24pt() {
        // A single paragraph that WRAPS into several lines at the editor's
        // width — lineSpacing only applies BETWEEN lines within a
        // paragraph, so per-line paragraphs would show no delta.
        let wrapping = "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore"
        for size in [CGFloat(9), 13, 24] {
            let note = Note(lastModifiedDeviceId: deviceId)
            // A second block keeps the first editor content-sized (a lone
            // block keeps the 320pt paper floor, which would swamp the
            // spacing delta).
            let blocks = [
                makeRichTextBlock(noteId: note.id, text: wrapping, sortKey: 0),
                makeRichTextBlock(noteId: note.id, text: "tail", sortKey: 1024)
            ]
            let standard = EditorTypography(fontPreference: nil, textSpacing: .standard, textSize: size)
            let compact = EditorTypography(fontPreference: nil, textSpacing: .compact, textSize: size)
            let relaxed = EditorTypography(fontPreference: nil, textSpacing: .relaxed, textSize: size)
            let standardEditor = allTextViews(in: makeHosting(blocks: blocks, typography: standard)).first { $0.string == wrapping }
            let compactEditor = allTextViews(in: makeHosting(blocks: blocks, typography: compact)).first { $0.string == wrapping }
            let relaxedEditor = allTextViews(in: makeHosting(blocks: blocks, typography: relaxed)).first { $0.string == wrapping }
            guard let standardEditor, let compactEditor, let relaxedEditor else {
                Issue.record("editors must render at \(size)pt")
                return
            }
            let standardHeight = standardEditor.intrinsicContentSize.height
            let compactHeight = compactEditor.intrinsicContentSize.height
            let relaxedHeight = relaxedEditor.intrinsicContentSize.height
            #expect(relaxedHeight > standardHeight,
                    "\(size)pt: relaxed grows the multi-line editor (got \(relaxedHeight) vs \(standardHeight))")
            #expect(compactHeight < standardHeight,
                    "\(size)pt: compact tightens the multi-line editor (got \(compactHeight) vs \(standardHeight))")
        }
    }
}
