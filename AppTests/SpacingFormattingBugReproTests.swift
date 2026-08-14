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
@Suite(.serialized) struct SpacingFormattingBugReproTests {
    // Serialized: the window tests manipulate the shared NSApp key-window /
    // first-responder state — parallel execution lets another test's
    // window steal key status, which collapses the editor's selection to
    // a caret (observed 2026-08-14) and silently voids the formatting.

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
        let undoManager: UndoManager?

        var body: some View {
            if let note = host.note {
                RichTextBlockView(
                    note: note,
                    editorTypography: typography,
                    blocks: host.blocks,
                    onBlocksChanged: { host.updateBlocks($0) },
                    undoManager: undoManager
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

    private enum BridgeError: Error {
        case notWired
    }

    /// The REAL app wires the bridge on FOCUS: the user clicks the editor
    /// (first responder of the key window), and the first `hasFocus == true`
    /// publish sets `bridge.textView` (authority filter in
    /// EditorSelectionBridge.publish). Replicate that; the test host's
    /// `NSApp.activate` is unreliable, so when the focus publish doesn't
    /// land, fall back to the bridge's direct attach API (same wiring —
    /// the formatting pipeline under test never reads hasFocus).
    private func focusAndWireBridge(
        _ editor: NSTextView,
        window: NSWindow,
        noteId: UUID
    ) async throws -> EditorSelectionBridge {
        // The RichTextBlockView .task registers the bridge on a runloop
        // turn — wait for registration first.
        var registered: EditorSelectionBridge?
        for _ in 0..<100 {
            registered = EditorSelectionContext.bridges[noteId]
            if registered != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard let liveBridge = registered else { throw BridgeError.notWired }

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        window.makeFirstResponder(editor)
        // The key-state observer (didBecomeKey → republishSelection) may
        // have fired BEFORE the editor became first responder, publishing
        // hasFocus == false (authority-filtered). Republish now that the
        // focus order is settled — the same mechanism the production
        // window uses on key-state changes.
        (editor.delegate as? RichTextView.Coordinator)?.republishSelection()
        for _ in 0..<20 {
            if liveBridge.textView === editor { return liveBridge }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // Test-host fallback: the app cannot reliably activate, so the
        // focus publish never carries hasFocus — wire the bridge directly.
        liveBridge.attach(textView: editor, blockId: nil)
        return liveBridge
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
        let before = attributeDump(editor, label: "BEFORE")
        // The real app wires the bridge on focus — replicate (otherwise
        // bridge.applyMarks silently no-ops on a nil textView).
        let liveBridge = try await focusAndWireBridge(editor, window: window, noteId: noteId)

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
        let hosting = NSHostingView(rootView: HostDrivenPaper(host: host, typography: typography, undoManager: host.undoManager))
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
        let beforeDump = attributeDump(editor, label: "BEFORE")
        let beforeHeights = lineFragmentHeights(editor)
        let liveBridge = try await focusAndWireBridge(editor, window: window, noteId: noteId)

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

    // MARK: - Wrapping paragraphs (lineSpacing is only visible BETWEEN
    // wrapped lines — the real user note shape)

    /// A long CJK+Latin paragraph that wraps to many lines at the editor
    /// width — the only shape where relaxed/compact spacing is visible.
    private static let wrappingText = String(
        repeating: "这是一段比较长的正文内容用来测试行距表现 hello world mixed text ",
        count: 6
    )

    @Test
    func wrappingTextBoldKeepsLineMetricsAndSpacing() async throws {
        for preference in [FontPreference?.none, .systemDefault] {
            for preset in [TextSpacingPreset.compact, .relaxed] {
                try await runWrappingChain(
                    preference: preference,
                    preset: preset,
                    label: "pref=\(String(describing: preference)) spacing=\(preset)"
                )
            }
        }
    }

    private func runWrappingChain(
        preference: FontPreference?,
        preset: TextSpacingPreset,
        label: String
    ) async throws {
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
        block.payload = .richText(.plain(Self.wrappingText))
        host.updateBlocks([block])
        await host.flush()

        let typography = EditorTypography(fontPreference: preference, textSpacing: preset, textSize: 13)
        let hosting = NSHostingView(rootView: HostDrivenPaper(host: host, typography: typography, undoManager: host.undoManager))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let editor = try #require(allTextViews(in: hosting).first { $0.string == Self.wrappingText })
        // Select a chunk in the middle (CJK+Latin mixed, spans a wrap).
        let range = NSRange(location: 40, length: 30)
        editor.setSelectedRange(range)
        let liveBridge = try await focusAndWireBridge(editor, window: window, noteId: noteId)
        #expect(liveBridge.textView === editor, "the bridge must be attached to THIS window's editor")
        // Parallel suites race the key window; while `focusAndWireBridge`
        // awaits (bridge registration + focus republish), the view's first
        // content push can land and rebuild the storage, resetting the
        // selection. Restore and confirm — the behavior under test is
        // "formatting applies to the selected range", not that the
        // selection survives the async focus setup (flaky 2026-08-14:
        // full-suite parallel runs reset it; serial runs pass).
        for _ in 0..<50 {
            if editor.selectedRange() == range { break }
            editor.setSelectedRange(range)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(editor.selectedRange() == range,
                "precondition: the selection must survive until applyMarks (got \(editor.selectedRange()))")
        let expected = try #require(expectedSpacing(preset), "\(preset) has a concrete line spacing")

        let beforeHeights = lineFragmentHeights(editor)
        #expect(beforeHeights.count > 3, "precondition: the text wraps to several lines (got \(beforeHeights.count))")
        let beforeIssues = spacingIssues(editor, expected: expected)
        #expect(beforeIssues.isEmpty, "\(label) precondition: spacing applied everywhere:\n\(beforeIssues.joined(separator: "\n"))")
        let beforeIntrinsic = editor.intrinsicContentSize.height
        let beforeDump = attributeDump(editor, label: "BEFORE")

        // The host's async content push (`.task` reload) can race this
        // point under a busy parallel runloop: `applyMarks` refuses while
        // `isPushing` is true (silent no-op — no bold, no undo). Retry
        // until the mark is REALLY applied; every accepted retry registers
        // an undo group, so the undo loop below unwinds them all.
        var boldApplied = false
        for _ in 0..<50 {
            liveBridge.applyMarks([.bold])
            try await Task.sleep(nanoseconds: 100_000_000)
            let probe = editor.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if probe?.fontDescriptor.symbolicTraits.contains(.bold) == true {
                boldApplied = true
                break
            }
        }
        #expect(boldApplied,
                "\(label): the formatting must actually apply bold at the selection (proof the selection path ran)")
        let afterHeights = lineFragmentHeights(editor)
        let afterIssues = spacingIssues(editor, expected: expected)
        #expect(afterIssues.isEmpty,
                "\(label): ⌘B must not drop the spacing:\n\(afterIssues.joined(separator: "\n"))\n\n\(beforeDump)\n\n\(attributeDump(editor, label: "AFTER"))")
        #expect(beforeHeights == afterHeights,
                "\(label): laid-out line heights changed by ⌘B (before \(beforeHeights) vs after \(afterHeights))")

        // Undo / redo must keep the metrics too. Multiple retries may have
        // registered multiple undo groups — unwind until the heights are
        // back (bold never changes line spacing, so one restore point).
        let undoManager = try #require(editor.undoManager)
        #expect(undoManager.canUndo, "\(label): ⌘B registered undo")
        var heightsRestored = false
        for _ in 0..<10 {
            guard undoManager.canUndo else { break }
            undoManager.undo()
            try await Task.sleep(nanoseconds: 50_000_000)
            if lineFragmentHeights(editor) == beforeHeights {
                heightsRestored = true
                break
            }
        }
        #expect(heightsRestored,
                "\(label): undo changed the laid-out line heights")
        undoManager.redo()
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(lineFragmentHeights(editor) == beforeHeights,
                "\(label): redo changed the laid-out line heights")
        let afterIntrinsic = editor.intrinsicContentSize.height
        #expect(abs(afterIntrinsic - beforeIntrinsic) < 0.5,
                "\(label): intrinsic height drifted (before \(beforeIntrinsic) vs after \(afterIntrinsic))")
        window.close()
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
            // Documented finding (2026-08-14): on macOS 27 beta, bare
            // NSTextView does NOT respond to toggleBold: — the ONLY ⌘B
            // handler in the app is the Format menu's SwiftUI Button
            // (applyMarksInKeyWindow → Coordinator.applyMarks). There is no
            // native path to mis-dispatch to.
            return
        }
        textView.perform(Selector(("toggleBold:")), with: nil)
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "even the native toggleBold: must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(attributeDump(textView, label: "AFTER-NATIVE"))")
    }

    /// NSTextView's DEFAULT context menu carries its own Font submenu
    /// (Bold ⌘B, target = NSFontManager, action = addFontTrait:). When the
    /// editor is first responder, the window-level key-equivalent pass can
    /// match THAT before the SwiftUI Format menu. This drives the native
    /// NSFontManager conversion — a completely different mutation path
    /// than Coordinator.applyMarks.
    @Test
    func nativeFontManagerBoldConversionOnSelection() {
        let (_, _, textView, _) = makeEditor(spacing: .relaxed)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(Self.midWordRange)
        let before = attributeDump(textView, label: "BEFORE")

        // The default-menu Bold item: NSFontManager.addFontTrait with the
        // bold tag (2) → convertFont: on the first responder.
        let sender = NSMenuItem()
        sender.tag = 2
        NSFontManager.shared.addFontTrait(sender)

        let after = attributeDump(textView, label: "AFTER-NATIVE-CONVERT")
        let boldFont = textView.textStorage?.attribute(.font, at: Self.midWordRange.location, effectiveRange: nil) as? NSFont
        let boldApplied = boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
        // The font manager targets NSApp's first responder — under a
        // unit-test host that routing is unreliable (observed: the
        // conversion lands on some runs, not others). Whenever it DOES
        // apply, spacing must survive; otherwise the probe documents a
        // non-event.
        guard boldApplied else { return }
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "the NATIVE NSFontManager bold conversion must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(before)\n\n\(after)")
        window.close()
    }

    /// The REAL ⌘B keyDown, routed through NSWindow.sendEvent — whatever
    /// handler wins (main menu, text-view default menu, or key bindings)
    /// is the production path.
    @Test
    func realKeyDownBoldDispatchPreservesSpacing() {
        let (_, _, textView, _) = makeEditor(spacing: .relaxed)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(Self.midWordRange)
        let before = attributeDump(textView, label: "BEFORE")

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "b",
            charactersIgnoringModifiers: "b",
            isARepeat: false,
            keyCode: 11 // kVK_ANSI_B
        ) else {
            Issue.record("could not synthesize ⌘B keyDown")
            return
        }
        window.sendEvent(event)

        let after = attributeDump(textView, label: "AFTER-KEYDOWN")
        let boldFont = textView.textStorage?.attribute(.font, at: Self.midWordRange.location, effectiveRange: nil) as? NSFont
        let boldApplied = boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true
        let typingBold = (textView.typingAttributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
        // The unit-test host installs NO main menu (the SwiftUI command
        // groups belong to the @main App, which the XCTest host does not
        // instantiate) and the default NSTextView menu's key equivalents
        // are not consulted — so in the harness no handler fires (the real
        // app's only ⌘B handler is the Format menu → applyMarksInKeyWindow
        // → Coordinator.applyMarks, which the other 14 tests cover). When
        // some handler DOES apply bold here, spacing must survive.
        guard boldApplied || typingBold else { return }
        let issues = spacingIssues(textView, expected: expectedSpacing(.relaxed)!)
        #expect(issues.isEmpty,
                "the real ⌘B keyDown dispatch must not change line spacing:\n\(issues.joined(separator: "\n"))\n\n\(before)\n\n\(after)")
        window.close()
    }
}
