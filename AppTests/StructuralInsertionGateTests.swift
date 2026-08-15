import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Structural insertion gate (PR1 Step 3.5, 2026-08-14)
//
// Bug 2 gate: "inserting a Todo visibly changes the surrounding body's
// presentation". The caretSplit pipeline is SHARED by Todo and Code
// insertion, so the gate runs the FULL production pipeline (host →
// RichTextBlockView → live body editor) for BOTH insert kinds under the
// SAME conditions and compares the SURVIVING body content's presentation
// before vs after:
//
//   branch ①  both Todo and Code change the body with an explicit
//              font preference  → structural rebuild drift CONFIRMED
//              (the original Todo-vs-Code asymmetry was a test-condition
//              artifact) → PR2 proceeds
//   branch ②  only Todo changes → Root Cause B incomplete → PR2 paused
//   branch ③  neither changes at Default font → no drift without a
//              stored preference (the screenshot's "Note font = Default"
//              case) → Bug 2 acceptance scope redefined
//
// The test simulates the LIVE TYPED presentation (everything typed after a
// CJK caret stays in the caret family — the typing path rule) by rewriting
// the live storage's fonts before insertion; the canonical model keeps only
// semantic marks, so the insertion's content push re-derives presentation.

@MainActor
@Suite struct StructuralInsertionGateTests {

    private let deviceId = UUID(uuidString: "e2000000-0000-4000-8000-000000000002")!

    private enum InsertKind {
        case todo
        case code
    }

    private enum ScenarioError: Error {
        case noNote
        case noBodyBlock
        case noBodyEditor
        case noPostEditor
    }

    // MARK: - Harness

    private struct HostDrivenPaper: View {
        let host: NoteWindowHostModel
        let typography: EditorTypography

        var body: some View {
            if let note = host.note {
                RichTextBlockView(
                    note: note,
                    editorTypography: typography,
                    blocks: host.blocks,
                    onBlocksChanged: { host.updateBlocks($0) },
                    onStructuralBlocksChanged: { host.updateBlocksStructural($0) },
                    todoProvider: { _ in nil },
                    undoManager: host.undoManager
                )
            }
        }
    }

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices(),
        )
    }

    private func collectTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for sub in view.subviews { found += collectTextViews(in: sub) }
        return found
    }

    private struct BodyPresentation {
        /// "family@size" per attribute run over the measured range.
        let fontRunFamilies: [String]
        /// Laid-out line fragment heights of the WHOLE string.
        let fragmentHeights: [CGFloat]
    }

    private func snapshotBody(editor: NSTextView, range: NSRange?) -> BodyPresentation {
        let storage = editor.textStorage!
        let measured = range ?? NSRange(location: 0, length: storage.length)
        var families: [String] = []
        storage.enumerateAttributes(in: measured, options: []) { attrs, _, _ in
            if let font = attrs[.font] as? NSFont {
                families.append("\(font.familyName ?? "-")@\(font.pointSize)")
            } else {
                families.append("none")
            }
        }
        let layoutManager = editor.layoutManager!
        layoutManager.ensureLayout(for: editor.textContainer!)
        var heights: [CGFloat] = []
        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            var effectiveRange = NSRange(location: 0, length: 0)
            heights.append(layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange).height)
            glyphIndex = NSMaxRange(effectiveRange)
        }
        return BodyPresentation(fontRunFamilies: families, fragmentHeights: heights)
    }

    private struct ScenarioResult {
        let preLeadingRuns: [String]
        let postRuns: [String]
        let preFragmentHeights: [CGFloat]
        let postFragmentHeights: [CGFloat]
        let bodyTextAfter: String
        let leading: String
    }

    /// The full production pipeline: host + live body editor → typed-drift
    /// pre-state → insertion at a caretSplit target → snapshot the
    /// SURVIVING body content's presentation before/after.
    private func runInsertionScenario(
        kind: InsertKind,
        preference: FontPreference?
    ) async throws -> ScenarioResult {
        let line1 = "第一行 hello world 混合内容 wrapping test 继续中文内容 more latin text"
        let line2 = "second line tail"
        let text = line1 + "\n" + line2
        let leading = line1 + "\n"
        let textSize: CGFloat = 13
        let typography = EditorTypography(fontPreference: preference, textSpacing: .standard, textSize: textSize)

        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else { throw ScenarioError.noNote }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard let richId = host.blocks.first(where: { $0.kind == .richText })?.id else {
            throw ScenarioError.noBodyBlock
        }
        // Seed the model with the document shape the app really stores after
        // typing: the canonical round trip of the LIVE typed storage. NOTE:
        // `RichTextDocument.plain` must NOT be used here — its paragraph has
        // no runs at all, so presentationFontPlan's run loop never executes.
        // (A single typed font run spanning the paragraph boundary is
        // dropped by canonicalDocument's run-containment filter — the
        // paragraphs carry no runs and the rebuild falls back to the
        // full-text family rule — which is EXACTLY the production shape.)
        let typedFont = NoteFontResolver(preference: preference).font(size: textSize, for: "")
        let seededAttributed = NSMutableAttributedString(string: text)
        seededAttributed.addAttribute(
            .font, value: typedFont,
            range: NSRange(location: 0, length: (text as NSString).length)
        )
        let seededDocument = RichTextView.Coordinator.canonicalDocument(from: seededAttributed)
        var blocks = host.blocks
        blocks = blocks.map { block in
            guard block.id == richId else { return block }
            return Block(
                id: block.id, noteId: block.noteId, kind: .richText,
                sortKey: block.sortKey,
                payload: .richText(seededDocument),
                versionId: block.versionId, parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt, modifiedAt: Date()
            )
        }
        host.updateBlocks(blocks)
        await host.flush()

        let hosting = NSHostingView(rootView: HostDrivenPaper(host: host, typography: typography))
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 700)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard let editor = collectTextViews(in: hosting).first(where: { $0.string == text }) else {
            throw ScenarioError.noBodyEditor
        }
        // Simulate the LIVE TYPED presentation: everything typed after a
        // CJK caret stays in the caret family (the typing path rule —
        // renderTypingAttributes keeps the caret's family).
        let storage = editor.textStorage!
        storage.addAttribute(.font, value: typedFont, range: NSRange(location: 0, length: storage.length))

        let leadingUTF16 = (leading as NSString).length
        let pre = snapshotBody(editor: editor, range: NSRange(location: 0, length: leadingUTF16))
        let preFragments = snapshotBody(editor: editor, range: nil).fragmentHeights

        let splitOffset = Array(text.unicodeScalars).count - Array(line2.unicodeScalars).count
        switch kind {
        case .todo:
            _ = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: splitOffset))
        case .code:
            _ = await host.insertCodeBlock(target: .caretSplit(blockId: richId, offset: splitOffset))
        }

        var postEditor: NSTextView?
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            if let candidate = collectTextViews(in: hosting).first(where: { $0.string == leading }) {
                postEditor = candidate
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard let postEditor else { throw ScenarioError.noPostEditor }
        let post = snapshotBody(editor: postEditor, range: nil)
        return ScenarioResult(
            preLeadingRuns: pre.fontRunFamilies,
            postRuns: post.fontRunFamilies,
            preFragmentHeights: preFragments,
            postFragmentHeights: post.fragmentHeights,
            bodyTextAfter: postEditor.string,
            leading: leading
        )
    }

    // MARK: - Branch ③: Default font — the insertion must be
    // presentation-NEUTRAL for the surviving body content.

    @Test
    func insertTodoPreservesBodyPresentationAtDefaultFont() async throws {
        let result = try await runInsertionScenario(kind: .todo, preference: nil)
        #expect(result.bodyTextAfter == result.leading,
                "the caretSplit must consume the trailing into a new block (got \(result.bodyTextAfter.debugDescription))")
        #expect(result.postRuns == result.preLeadingRuns,
                "Insert Todo must NOT change the surviving body's font runs (before \(result.preLeadingRuns) vs after \(result.postRuns))")
        #expect(result.postFragmentHeights == Array(result.preFragmentHeights.prefix(result.postFragmentHeights.count)),
                "Insert Todo must NOT change the surviving body's line fragments (before \(result.preFragmentHeights) vs after \(result.postFragmentHeights))")
    }

    @Test
    func insertCodePreservesBodyPresentationAtDefaultFont() async throws {
        let result = try await runInsertionScenario(kind: .code, preference: nil)
        #expect(result.bodyTextAfter == result.leading,
                "the caretSplit must consume the trailing into a new block (got \(result.bodyTextAfter.debugDescription))")
        #expect(result.postRuns == result.preLeadingRuns,
                "Insert Code must NOT change the surviving body's font runs (before \(result.preLeadingRuns) vs after \(result.postRuns))")
        #expect(result.postFragmentHeights == Array(result.preFragmentHeights.prefix(result.postFragmentHeights.count)),
                "Insert Code must NOT change the surviving body's line fragments (before \(result.preFragmentHeights) vs after \(result.postFragmentHeights))")
    }

    // MARK: - Branch ①: explicit custom font preference — the typed
    // presentation (initial caret family = PRIMARY family) must be re-
    // derived by the content push for BOTH insert kinds (the rebuild's
    // full-text family rule lands CJK-containing text in the FALLBACK
    // family — a visible metric flip, NOT Todo-specific).

    @Test
    func insertTodoRerendersBodyCanonicallyWithCustomFont() async throws {
        let result = try await runInsertionScenario(kind: .todo, preference: .systemDefault)
        #expect(result.postRuns != result.preLeadingRuns,
                "with a custom font preference the typed body must re-render on Insert Todo (before \(result.preLeadingRuns) vs after \(result.postRuns))")
        #expect(result.postRuns == ["PingFang SC@13.0"],
                "the rebuild re-derives the whole text in the full-text family rule (CJK → fallback family), flipping the typed primary-family declaration (got \(result.postRuns))")
    }

    @Test
    func insertCodeRerendersBodyCanonicallyWithCustomFont() async throws {
        let result = try await runInsertionScenario(kind: .code, preference: .systemDefault)
        #expect(result.postRuns != result.preLeadingRuns,
                "with a custom font preference the typed body must re-render on Insert Code (before \(result.preLeadingRuns) vs after \(result.postRuns))")
        #expect(result.postRuns == ["PingFang SC@13.0"],
                "the rebuild re-derives the whole text in the full-text family rule (CJK → fallback family), flipping the typed primary-family declaration (got \(result.postRuns))")
    }
}
