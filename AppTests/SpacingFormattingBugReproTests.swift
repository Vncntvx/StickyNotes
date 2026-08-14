import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Spacing × formatting bug repro (debug round, 2026-08-14)
//
// USER BUG: with the global Text Spacing at Compact/Relaxed, applying
// Bold/Italic (⌘B/⌘I) to a selection changes the line spacing of the
// formatted region or surrounding paragraphs — looks like a partial revert
// to Default, while Settings still show the preset.
//
// This suite is the REPRODUCTION VEHICLE: it runs the exact production
// formatting path (`EditorSelectionBridge.applyMarks` →
// `Coordinator.applyMarks` → `RichTextMarkApplier` → commit → SwiftUI
// updateNSView) and asserts the ownership invariant:
//
//     Formatting changes marks. Typography changes presentation.
//     Each operation preserves the other layer.
//
// `.paragraphStyle` / lineSpacing must be byte-identical on every character
// before and after every mark operation. Attribute dumps are surfaced in
// the failure messages.

@MainActor
@Suite struct SpacingFormattingBugReproTests {

    private final class CommitRecorder {
        var documents: [RichTextDocument] = []
    }

    private let deviceId = UUID(uuidString: "e0000000-0000-4000-8000-000000000005")!

    // MARK: - Harness

    /// A 3-paragraph document so the selection can sit mid-line, span a
    /// newline, and leave surrounding paragraphs untouched.
    private static let text = "aaa bbb ccc\nddd eee fff\nggg hhh iii"

    /// UTF-16 range of "eee" (middle of the middle paragraph).
    private static let midWordRange = NSRange(location: 16, length: 3)

    private func makeEditor(
        spacing: TextSpacingPreset,
        undoManager: UndoManager? = UndoManager()
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NSTextView, recorder: CommitRecorder) {
        let recorder = CommitRecorder()
        let view = RichTextView(
            document: .plain(Self.text),
            editorTypography: EditorTypography(fontPreference: nil, textSpacing: spacing, textSize: 13),
            onCommit: { recorder.documents.append($0) },
            undoManager: undoManager
        )
        let coordinator = view.makeCoordinator()
        coordinator.parent = view
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.string = Self.text
        textView.delegate = coordinator
        coordinator.applyDocument(.plain(Self.text), typography: view.editorTypography, to: textView)
        return (view, coordinator, textView, recorder)
    }

    /// Replicates the `updateNSView` branch decisions (content push vs
    /// typography refresh) for a SwiftUI update carrying `document`.
    private func simulateUpdateNSView(
        document: RichTextDocument,
        view: RichTextView,
        coordinator: RichTextView.Coordinator,
        textView: NSTextView
    ) {
        coordinator.parent = view
        if textView.hasMarkedText() { return }
        if textView.string != document.text {
            coordinator.applyDocument(document, typography: view.editorTypography, to: textView)
        } else if view.editorTypography != coordinator.lastAppliedTypography {
            coordinator.restyleTypographyInPlace(view.editorTypography, document: document, to: textView)
        }
    }

    private func expectedSpacing(_ preset: TextSpacingPreset) -> CGFloat? {
        EditorTypography(fontPreference: nil, textSpacing: preset, textSize: 13).lineSpacing
    }

    /// Every character must carry the preset's paragraph style.
    private func spacingIssues(_ textView: NSTextView, expected: CGFloat) -> [String] {
        guard let storage = textView.textStorage else { return ["no storage"] }
        var issues: [String] = []
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, range, _ in
            let actual = (attrs[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing
            if actual != expected {
                issues.append("range \(range.location)..<\(range.location + range.length): lineSpacing \(String(describing: actual)) != expected \(expected)")
            }
        }
        return issues
    }

    /// Debug dump: one line per effective attribute range.
    private func attributeDump(_ textView: NSTextView, label: String) -> String {
        guard let storage = textView.textStorage else { return "\(label): no storage" }
        var lines = ["\(label):"]
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attrs, range, _ in
            let sub = (storage.string as NSString).substring(with: range).replacingOccurrences(of: "\n", with: "\\n")
            let font = attrs[.font] as? NSFont
            let style = attrs[.paragraphStyle] as? NSParagraphStyle
            let italic = font.map { RichTextMarkApplier.hasTrait(.italic, in: $0) } ?? false
            lines.append("  \(range.location)..<\(range.location + range.length) \"\(sub)\" family=\(font?.familyName ?? "-") size=\(String(describing: font?.pointSize)) bold=\(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false) italic=\(italic || attrs[.obliqueness] != nil) obliqueness=\(String(describing: attrs[.obliqueness])) lineSpacing=\(style.map { String(describing: $0.lineSpacing) } ?? "nil") underline=\(attrs[.underlineStyle] != nil) strike=\(attrs[.strikethroughStyle] != nil)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Selection path: marks must not touch paragraphStyle

    @Test
    func boldOnMidWordSelectionPreservesRelaxedSpacing() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        let before = attributeDump(textView, label: "BEFORE")
        textView.setSelectedRange(Self.midWordRange)
        _ = coordinator.applyMarks([.bold], to: textView)
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "⌘B must not change any paragraph's line spacing:\n\(issues.joined(separator: "\n"))\n\n\(before)\n\n\(attributeDump(textView, label: "AFTER"))")
    }

    @Test
    func italicOnMidWordSelectionPreservesCompactSpacing() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .compact)
        textView.setSelectedRange(Self.midWordRange)
        _ = coordinator.applyMarks([.italic], to: textView)
        let issues = spacingIssues(textView, expected: expectedSpacing(.compact)!)
        #expect(issues.isEmpty,
                "⌘I must not change any paragraph's line spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER"))")
    }

    @Test
    func underlineStrikethroughInlineCodePreserveRelaxedSpacing() {
        for mark in [RichTextMark.underline, .strikethrough, .inlineCode] {
            let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
            textView.setSelectedRange(Self.midWordRange)
            _ = coordinator.applyMarks([mark], to: textView)
            let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
            #expect(issues.isEmpty,
                    "\(mark) must not change any paragraph's line spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER"))")
        }
    }

    @Test
    func crossNewlineSelectionPreservesSpacing() {
        // Selection "ccc\nddd" spans the paragraph boundary.
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(NSRange(location: 8, length: 8))
        _ = coordinator.applyMarks([.bold], to: textView)
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "a cross-newline ⌘B must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER"))")
    }

    @Test
    func fullLineSelectionPreservesSpacing() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(NSRange(location: 12, length: 11)) // "ddd eee fff"
        _ = coordinator.applyMarks([.bold], to: textView)
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "a whole-line ⌘B must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER"))")
    }

    // MARK: - Full chain: formatting commit → SwiftUI update

    @Test
    func formatCommitThenSimulatedUpdatePreservesSpacing() {
        let (view, coordinator, textView, recorder) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(Self.midWordRange)
        _ = coordinator.applyMarks([.bold], to: textView)
        guard let committed = recorder.documents.last else {
            Issue.record("⌘B must commit a canonical document")
            return
        }
        // The production re-render passes the committed document back to
        // updateNSView — run the same branch decisions.
        let afterCommit = attributeDump(textView, label: "AFTER-COMMIT")
        simulateUpdateNSView(document: committed, view: view, coordinator: coordinator, textView: textView)
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "the post-commit SwiftUI update must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(afterCommit)\n\n\(attributeDump(textView, label: "AFTER-UPDATE"))")
    }

    // MARK: - Undo / redo

    @Test
    func undoRedoPreserveSpacing() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(Self.midWordRange)
        _ = coordinator.applyMarks([.bold], to: textView)
        let undoManager = try! #require(textView.undoManager)
        #expect(undoManager.canUndo, "precondition: ⌘B registered undo")
        undoManager.undo()
        let afterUndo = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(afterUndo.isEmpty,
                "undo must not change line spacing:\n\(afterUndo.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER-UNDO"))")
        undoManager.redo()
        let afterRedo = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(afterRedo.isEmpty,
                "redo must not change line spacing:\n\(afterRedo.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER-REDO"))")
    }

    // MARK: - Typing path (no selection)

    @Test
    func noSelectionBoldKeepsParagraphStyleInTypingAttributes() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        _ = coordinator.applyMarks([.bold], to: textView)
        let style = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
        #expect(style?.lineSpacing == expectedSpacing(.relaxed),
                "the no-selection ⌘B must preserve the paragraph style in typingAttributes (got \(String(describing: style?.lineSpacing)))")
    }

    @Test
    func textTypedAfterNoSelectionBoldKeepsSpacing() {
        let (_, coordinator, textView, _) = makeEditor(spacing: .compact)
        textView.setSelectedRange(NSRange(location: 5, length: 0))
        _ = coordinator.applyMarks([.bold], to: textView)
        // Simulate typing one character — NSTextView applies typingAttributes.
        textView.insertText("X", replacementRange: textView.selectedRange())
        let issues = spacingIssues(textView, expected: expectedSpacing(.compact)!)
        #expect(issues.isEmpty,
                "text typed after a no-selection ⌘B must carry the compact spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER-TYPE"))")
    }

    // MARK: - Full window chain (real SwiftUI updateNSView loop)

    /// Re-renders `RichTextBlockView` whenever the host's blocks change —
    /// the same observation the production `NoteWindowContent` relies on
    /// (the host is @Observable; a plain NSHostingView snapshot would never
    /// run `updateNSView` after the commit).
    private struct HostDrivenPaper: View {
        let host: NoteWindowHostModel
        let typography: EditorTypography

        var body: some View {
            if let note = host.note {
                RichTextBlockView(
                    note: note,
                    editorTypography: typography,
                    blocks: host.blocks,
                    onBlocksChanged: { host.updateBlocks($0) }
                )
            }
        }
    }

    /// The laid-out line fragment heights — the visual "行距" proxy. A
    /// line-spacing regression shows up here even if the raw attribute
    /// survives (font changes can shift line metrics).
    private func lineFragmentHeights(_ textView: NSTextView) -> [CGFloat] {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return [] }
        lm.ensureLayout(for: tc)
        var heights: [CGFloat] = []
        var glyphIndex = 0
        while glyphIndex < lm.numberOfGlyphs {
            var effectiveRange = NSRange(location: 0, length: 0)
            let rect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            heights.append(rect.height)
            glyphIndex = NSMaxRange(effectiveRange)
        }
        return heights
    }

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.spacingformat.\(UUID().uuidString)") ?? .standard)
        )
    }

    private func allTextViews(in view: NSView) -> [NSTextView] {
        var result: [NSTextView] = []
        if let tv = view as? NSTextView { result.append(tv) }
        for sub in view.subviews {
            result.append(contentsOf: allTextViews(in: sub))
        }
        return result
    }

    @Test
    func fullWindowChainFormattingPreservesSpacing() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard var block = host.blocks.first else {
            Issue.record("blank note must start with a rich-text block")
            return
        }
        let doc = RichTextDocument.plain(Self.text)
        block.payload = .richText(doc)
        host.updateBlocks([block])
        await host.flush()

        let note = try #require(host.note)
        let typography = EditorTypography(fontPreference: nil, textSpacing: .relaxed, textSize: 13)
        let hosting = NSHostingView(rootView: RichTextBlockView(
            note: note,
            editorTypography: typography,
            blocks: host.blocks,
            onBlocksChanged: { host.updateBlocks($0) }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editor = try #require(allTextViews(in: hosting).first { $0.string == Self.text })
        editor.setSelectedRange(Self.midWordRange)
        // Let the bridge attach (RichTextBlockView.task creates it).
        var bridge: EditorSelectionBridge?
        for _ in 0..<100 {
            bridge = EditorSelectionContext.bridges[noteId]
            if bridge != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let liveBridge = try #require(bridge, "the window must register a selection bridge")
        let before = attributeDump(editor, label: "BEFORE")

        // The EXACT production ⌘B path (Format menu → bridge.applyMarks).
        liveBridge.applyMarks([.bold])
        // Wait for the commit → host.updateBlocks → SwiftUI re-render →
        // updateNSView round trip.
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let issues = spacingIssues(editor, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "the full window chain must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(before)\n\n\(attributeDump(editor, label: "AFTER"))")
        window.close()
    }

    @Test
    func hostDrivenWindowRerenderPreservesSpacingAndLineMetrics() async throws {
        // The production observation loop: host.blocks change → SwiftUI
        // re-renders → RichTextView.updateNSView runs with the committed
        // document. CJK+Latin mixed text — the real user content shape.
        let cjkText = "第一行 测试文字 hello\n第二段 内容 world test\n第三段 更多文本 end"
        let cjkRange = NSRange(location: 19, length: 8) // "内容 world" — CJK+space+Latin
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard var block = host.blocks.first else {
            Issue.record("blank note must start with a rich-text block")
            return
        }
        block.payload = .richText(.plain(cjkText))
        host.updateBlocks([block])
        await host.flush()

        let typography = EditorTypography(fontPreference: .systemDefault, textSpacing: .relaxed, textSize: 13)
        let hosting = NSHostingView(rootView: HostDrivenPaper(host: host, typography: typography))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editor = try #require(allTextViews(in: hosting).first { $0.string == cjkText })
        #expect(editor is NotePaperTextView, "precondition: the production editor subclass is in play")
        editor.setSelectedRange(cjkRange)
        var bridge: EditorSelectionBridge?
        for _ in 0..<100 {
            bridge = EditorSelectionContext.bridges[noteId]
            if bridge != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let liveBridge = try #require(bridge, "the window must register a selection bridge")
        let beforeDump = attributeDump(editor, label: "BEFORE")
        let beforeHeights = lineFragmentHeights(editor)

        liveBridge.applyMarks([.bold])
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let issues = spacingIssues(editor, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "the production re-render loop must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(beforeDump)\n\n\(attributeDump(editor, label: "AFTER"))")
        let afterHeights = lineFragmentHeights(editor)
        #expect(beforeHeights == afterHeights,
                "laid-out line heights must be identical (before \(beforeHeights) vs after \(afterHeights))")
        window.close()
    }

    // MARK: - Settings-first sequence (spacing switched AFTER the note opened)

    @Test
    func restyleFirstThenBoldPreservesSpacing() {
        // Open with standard, switch the preset to relaxed (the Settings
        // flow: restyleTypographyInPlace), THEN ⌘B.
        let (_, coordinator, textView, _) = makeEditor(spacing: .standard)
        let relaxed = EditorTypography(fontPreference: nil, textSpacing: .relaxed, textSize: 13)
        let document = RichTextView.Coordinator.canonicalDocument(from: textView.attributedString())
        let relaxedView = RichTextView(document: document, editorTypography: relaxed, onCommit: { _ in })
        coordinator.parent = relaxedView
        coordinator.restyleTypographyInPlace(relaxed, document: document, to: textView)
        #expect(spacingIssues(textView, expected: 4.0).isEmpty,
                "precondition: the restyle applied relaxed spacing everywhere")

        textView.setSelectedRange(Self.midWordRange)
        _ = coordinator.applyMarks([.bold], to: textView)
        let issues = spacingIssues(textView, expected: 4.0)
        #expect(issues.isEmpty,
                "⌘B after an in-session spacing switch must preserve the spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER"))")
    }

    // MARK: - Native AppKit bold (the non-coordinator path)

    @Test
    func nativeToggleBoldBehaviorDocumented() {
        // If ⌘B ever dispatches to AppKit's native toggleBold: (duplicate
        // key equivalent / responder chain), document what it does to the
        // spacing — the coordinator path is the supported one.
        let (_, _, textView, _) = makeEditor(spacing: .relaxed)
        textView.setSelectedRange(Self.midWordRange)
        guard textView.responds(to: Selector(("toggleBold:"))) else {
            Issue.record("NSTextView does not respond to toggleBold: on this OS")
            return
        }
        textView.perform(Selector(("toggleBold:")), with: nil)
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "even the native toggleBold: must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER-NATIVE"))")
    }
}
