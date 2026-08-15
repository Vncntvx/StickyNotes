import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Typography live-update tests (Phase 3, 2026-08-14)
//
// The in-place restyle engine: a typography preference change restyles an
// OPEN editor without closing/reopening, without replacing the string,
// without committing (no canonical/autosave traffic), with the selection,
// caret and first responder preserved, CJK fallback intact, invalid
// families degrading to the system font, and completed-todo display
// styling surviving as an overlay (never becoming a semantic mark).

@MainActor
@Suite struct TypographyLiveUpdateTests {

    private final class CommitRecorder {
        var documents: [RichTextDocument] = []
    }

    /// A tiny view layer reproducing what NoteWindowContent does: read the
    /// observable preferences, compute the EditorTypography VALUE, hand it
    /// to the editor (the editor itself never sees the preference object).
    private struct TypographyProbe: View {
        let prefs: TypographyPreferences
        let document: RichTextDocument
        let displayStyling: EditorDisplayStyling?
        let onCommit: (RichTextDocument) -> Void

        var body: some View {
            let typography = EditorTypography(
                fontPreference: prefs.fontPreference,
                textSpacing: prefs.textSpacing,
                textSize: 13
            )
            RichTextView(
                document: document,
                editorTypography: typography,
                onCommit: onCommit,
                displayStyling: displayStyling
            )
        }
    }

    // MARK: - Harness

    private func makeEditor(
        text: String = "Hello 世界",
        fontPreference: FontPreference? = nil,
        displayStyling: EditorDisplayStyling? = nil,
        recorder: CommitRecorder? = nil
    ) -> (view: RichTextView, coordinator: RichTextView.Coordinator, textView: NSTextView, recorder: CommitRecorder) {
        let recorder = recorder ?? CommitRecorder()
        let view = RichTextView(
            document: .plain(text),
            editorTypography: EditorTypography(fontPreference: fontPreference, textSpacing: .standard, textSize: 13),
            onCommit: { recorder.documents.append($0) },
            displayStyling: displayStyling
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

    /// Simulates the updateNSView typography-only branch: refresh the
    /// parent struct with a new typography and restyle in place. The
    /// document comes from the LIVE storage (canonicalized) — exactly
    /// what the model holds after the last commit (runs and marks intact,
    /// like production's updateNSView path).
    private func restyle(
        _ coordinator: RichTextView.Coordinator,
        textView: NSTextView,
        to fontPreference: FontPreference?,
        displayStyling: EditorDisplayStyling? = nil
    ) {
        let document = RichTextView.Coordinator.canonicalDocument(
            from: textView.attributedString(),
            excludesDisplayStyling: displayStyling?.strikethrough == true
        )
        let view = RichTextView(
            document: document,
            editorTypography: EditorTypography(fontPreference: fontPreference, textSpacing: .standard, textSize: 13),
            onCommit: { _ in },
            displayStyling: displayStyling
        )
        coordinator.parent = view
        coordinator.restyleTypographyInPlace(view.editorTypography, document: document, to: textView)
    }

    private func font(at index: Int, in textView: NSTextView) -> NSFont? {
        textView.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    private func family(at index: Int, in textView: NSTextView) -> String? {
        font(at: index, in: textView)?.familyName
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("condition not met within \(timeout)")
    }

    // MARK: - Live update through the observable chain

    @Test
    func livePreferenceRestylesOpenEditorWithoutReopening() async throws {
        FontPreferenceStore.clear()
        defer { FontPreferenceStore.clear() }
        let prefs = TypographyPreferences()
        let recorder = CommitRecorder()
        let hosting = NSHostingView(rootView: TypographyProbe(
            prefs: prefs,
            document: .plain("hello world"),
            displayStyling: nil,
            onCommit: { recorder.documents.append($0) }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        let textView = try #require(findTextView(in: hosting), "the editor must render")
        #expect(family(at: 0, in: textView) != "Helvetica Neue", "precondition: system font before the change")

        prefs.setFontPreference(.systemDefault)
        try await waitUntil {
            self.family(at: 0, in: textView) == "Helvetica Neue"
        }
        #expect(textView.string == "hello world", "the restyle must never replace the string")
        #expect(recorder.documents.isEmpty,
                "a typography change commits nothing (no canonical/autosave traffic)")
        window.close()
    }

    // MARK: - Family resolution

    @Test
    func latinFamilyChangesOnRestyle() {
        let (_, coordinator, textView, _) = makeEditor(text: "hello world")
        restyle(coordinator, textView: textView, to: .systemDefault)
        #expect(family(at: 0, in: textView) == "Helvetica Neue")
        #expect(family(at: 8, in: textView) == "Helvetica Neue")
    }

    @Test
    func cjkFallbackKeepsWorkingAfterRestyle() {
        let (_, coordinator, textView, _) = makeEditor(text: "Hello 世界")
        restyle(coordinator, textView: textView, to: .systemDefault)
        #expect(family(at: 0, in: textView) == "Helvetica Neue", "Latin uses the primary family")
        #expect(family(at: 7, in: textView) == "PingFang SC", "CJK keeps the fallback family")
    }

    @Test
    func mixedSegmentationDoesNotDegradeAfterRestyle() {
        let (_, coordinator, textView, _) = makeEditor(text: "Hello 世界 Hello")
        restyle(coordinator, textView: textView, to: .systemDefault)
        #expect(family(at: 0, in: textView) == "Helvetica Neue")
        #expect(family(at: 7, in: textView) == "PingFang SC")
        #expect(family(at: 10, in: textView) == "Helvetica Neue",
                "the post-CJK Latin segment returns to the primary family")
    }

    @Test
    func invalidFamilyFallsBackToSystemFont() {
        let (_, coordinator, textView, _) = makeEditor(text: "hello world")
        let invalid = FontPreference(primaryFamily: "No Such Family 42", fallbackFamily: "PingFang SC")
        restyle(coordinator, textView: textView, to: invalid)
        #expect(family(at: 0, in: textView) == NSFont.systemFont(ofSize: 13).familyName,
                "an invalid family degrades to the system font")
    }

    @Test
    func inlineCodePresentationSurvivesRestyle() {
        // Bold/italic/inlineCode are font-affecting marks — the restyle
        // must re-derive all of them under the new family (F revision).
        let (_, coordinator, textView, _) = makeEditor(text: "hello world")
        textView.selectedRange = NSRange(location: 0, length: 5)
        _ = coordinator.applyMarks([.inlineCode], to: textView)
        restyle(coordinator, textView: textView, to: .systemDefault)
        let family0 = family(at: 0, in: textView) ?? ""
        #expect(family0.localizedCaseInsensitiveContains("mono") || family0.localizedCaseInsensitiveContains("courier"),
                "inlineCode stays monospaced across the restyle")
    }

    // MARK: - Selection / caret / first responder

    @Test
    func restylePreservesCaretSelectionAndFirstResponder() {
        let (_, coordinator, textView, _) = makeEditor(text: "hello world")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = textView
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 4))
        restyle(coordinator, textView: textView, to: .systemDefault)
        #expect(textView.selectedRange() == NSRange(location: 3, length: 4),
                "the selection survives the restyle")
        #expect(window.firstResponder === textView,
                "the editor stays first responder")
        window.close()
    }

    @Test
    func restyleNeverReplacesStringOrCommits() {
        let (_, coordinator, textView, recorder) = makeEditor(text: "hello world")
        restyle(coordinator, textView: textView, to: .systemDefault)
        #expect(textView.string == "hello world", "the string is untouched (no setAttributedString path)")
        #expect(recorder.documents.isEmpty, "no canonical commit on a typography change")
    }

    // MARK: - Display styling stays an overlay

    @Test
    func completedTodoDisplayStylingSurvivesRestyleAndNeverBecomesSemanticStrike() {
        let styling = EditorDisplayStyling(strikethrough: true, secondaryColor: true)
        let (_, coordinator, textView, _) = makeEditor(
            text: "buy milk",
            displayStyling: styling
        )
        restyle(coordinator, textView: textView, to: .systemDefault, displayStyling: styling)
        guard let storage = textView.textStorage else {
            Issue.record("no storage")
            return
        }
        #expect(storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil,
                "the display-only strikethrough survives the restyle")
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil,
                "the display-only secondary color survives the restyle")
        let canonical = RichTextView.Coordinator.canonicalDocument(
            from: textView.attributedString(),
            excludesDisplayStyling: true
        )
        let marks = canonical.paragraphs.flatMap(\.runs).flatMap(\.marks)
        #expect(!marks.contains(.strikethrough),
                "todo completion must never leak into semantic marks")
        #expect(textView.typingAttributes[.strikethroughStyle] != nil,
                "typing attributes keep the display overlay for continued input")
    }
}
