import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Insertion gap repro (user report 2026-08-14)
//
// Reported: creating a todo on the NEXT LINE of the body (caret at the
// end of a line, insert) leaves an abnormally LARGE gap between the body
// and the inserted todo/code block; resizing the window restores it.
//
// The gap must be correct IMMEDIATELY after the insertion — never depend
// on a width change to re-measure. This suite hosts the FULL pipeline
// (host + window + real editors), inserts at the caret, measures the
// body→todo gap, then resizes and asserts the gap did not shrink.

@MainActor
@Suite struct InsertionGapReproTests {

    private let deviceId = UUID(uuidString: "e5000000-0000-4000-8000-000000000005")!

    private enum InsertKind {
        case todo
        case code
    }

    private enum ScenarioError: Error {
        case noNote
        case noBodyBlock
        case noEditors
    }

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

    /// The vertical gap between the BODY editor's frame bottom and the
    /// inserted block's editor frame top, in hosting coordinates.
    private func bodyToInsertedGap(
        hosting: NSHostingView<AnyView>,
        bodyText: String,
        insertedText: String
    ) -> CGFloat? {
        let editors = collectTextViews(in: hosting)
        guard let body = editors.first(where: { $0.string == bodyText }),
              let inserted = editors.first(where: { $0.string == insertedText }) else {
            return nil
        }
        let bodyFrame = body.convert(body.bounds, to: hosting)
        let insertedFrame = inserted.convert(inserted.bounds, to: hosting)
        return insertedFrame.minY - bodyFrame.maxY
    }

    private func runScenario(kind: InsertKind, caretAfterNewline: Bool, preexistingBlockBelow: Bool = false) async throws -> (firstFrameGap: CGFloat?, convergedGap: CGFloat?, resizedGap: CGFloat?, bodyText: String) {
        // caretAfterNewline: caret right after the first newline (the body
        // continues on a second line — Case C produces a non-empty trailing
        // block). Otherwise the caret is at the very end (Case A).
        let bodyText = caretAfterNewline ? "这是正文第一行。\n第二行内容" : "这是正文第一行。\n"
        let typography = EditorTypography(fontPreference: nil, textSpacing: .standard, textSize: 13)

        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else { throw ScenarioError.noNote }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        guard let richId = host.blocks.first(where: { $0.kind == .richText })?.id else {
            throw ScenarioError.noBodyBlock
        }
        var blocks = host.blocks
        blocks = blocks.map { block in
            guard block.id == richId else { return block }
            return Block(
                id: block.id, noteId: block.noteId, kind: .richText,
                sortKey: block.sortKey,
                payload: .richText(.plain(bodyText)),
                versionId: block.versionId, parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt, modifiedAt: Date()
            )
        }
        host.updateBlocks(blocks)
        await host.flush()

        // A pre-existing block BELOW the body: the minimum-height /
        // bottom-inset flags never flip on a later insertion — the
        // intrinsic invalidation must come from the content push itself.
        if preexistingBlockBelow {
            blocks.append(Block(
                noteId: noteId, kind: .code, sortKey: 2048,
                payload: .code(CodePayload(text: "let existing = true", language: nil)),
                lastModifiedDeviceId: deviceId
            ))
            host.updateBlocks(blocks)
            await host.flush()
        }

        let hosting = NSHostingView(rootView: AnyView(HostDrivenPaper(host: host, typography: typography)))
        // A REAL window — the production display cycle (the windowless
        // hosting shape self-converges via its synchronous layout passes).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 700),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 700)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        // The production focus state: the body editor is the first
        // responder (the insertion target comes from its live caret).
        if let body = collectTextViews(in: hosting).first(where: { $0.string == bodyText }) {
            window.makeFirstResponder(body)
            body.setSelectedRange(NSRange(location: (body.string as NSString).length, length: 0))
        }

        // Insert at the caret.
        let splitOffset = caretAfterNewline
            ? Array("这是正文第一行。\n".unicodeScalars).count
            : Array(bodyText.unicodeScalars).count
        switch kind {
        case .todo:
            _ = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: splitOffset))
        case .code:
            _ = await host.insertCodeBlock(target: .caretSplit(blockId: richId, offset: splitOffset))
        }

        // Case A consumes the trailing newline; Case C keeps the leading
        // half — the body's text becomes the leading form after insertion.
        let trimmedBody = caretAfterNewline ? "这是正文第一行。\n" : bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        // FIRST FRAME: the real app displays the insertion without any
        // forced extra layout passes — one runloop turn, one layout.
        // (The previous poll-based harness masked the bug by forcing
        // repeated layout passes until convergence.)
        try? await Task.sleep(nanoseconds: 50_000_000)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let editorsFirst = collectTextViews(in: hosting)
        let bodyFirst = editorsFirst.first { $0.string == trimmedBody }
        let insertedFirst = bodyFirst.flatMap { body in
            editorsFirst.first { $0 !== body }
        }
        var initialGap: CGFloat?
        var insertedText = ""
        if let body = bodyFirst, let inserted = insertedFirst {
            insertedText = inserted.string
            let bodyFrame = body.convert(body.bounds, to: hosting)
            let insertedFrame = inserted.convert(inserted.bounds, to: hosting)
            initialGap = insertedFrame.minY - bodyFrame.maxY
        }

        // CONVERGED: allow the layout to settle (the poll forces the
        // re-measurement the app would get from any subsequent update).
        var convergedGap: CGFloat?
        for _ in 0..<100 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            if let gap = bodyToInsertedGap(
                hosting: hosting, bodyText: trimmedBody, insertedText: insertedText
            ) {
                convergedGap = gap
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        // Resize (the "拉宽" step) and measure again.
        hosting.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
        for _ in 0..<25 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        let resizedGap = bodyToInsertedGap(
            hosting: hosting, bodyText: trimmedBody, insertedText: insertedText
        )
        return (initialGap, convergedGap ?? resizedGap, resizedGap, trimmedBody)
    }

    private func runAndAssert(kind: InsertKind, caretAfterNewline: Bool, label: String, preexistingBlockBelow: Bool = false) async throws {
        let result = try await runScenario(kind: kind, caretAfterNewline: caretAfterNewline, preexistingBlockBelow: preexistingBlockBelow)
        let first = try #require(result.firstFrameGap, "the inserted editor must appear on the first frame")
        let converged = try #require(result.convergedGap, "the inserted editor must converge")
        let resized = try #require(result.resizedGap, "the inserted editor must survive the resize")
        #expect(abs(first - converged) < 20,
                "\(label): the FIRST frame after insertion must already carry the correct gap (first \(first) vs converged \(converged))")
        #expect(abs(first - resized) < 20,
                "\(label): the first-frame gap must match the post-resize gap — a width change must not fix it (first \(first) vs resized \(resized))")
    }

    @Test
    func todoInsertionGapIsStableAcrossResize() async throws {
        try await runAndAssert(kind: .todo, caretAfterNewline: false, label: "end-of-body todo")
    }

    @Test
    func codeInsertionGapIsStableAcrossResize() async throws {
        try await runAndAssert(kind: .code, caretAfterNewline: false, label: "end-of-body code")
    }

    @Test
    func midBodyTodoInsertionGapIsStableAcrossResize() async throws {
        try await runAndAssert(kind: .todo, caretAfterNewline: true, label: "mid-body todo")
    }

    @Test
    func midBodyCodeInsertionGapIsStableAcrossResize() async throws {
        try await runAndAssert(kind: .code, caretAfterNewline: true, label: "mid-body code")
    }

    // The body already has a block below — the minimum-height/bottom-inset
    // flags never flip, so the intrinsic invalidation must come from the
    // content push itself.
    @Test
    func todoInsertionGapWithPreexistingBlockBelow() async throws {
        try await runAndAssert(
            kind: .todo, caretAfterNewline: false,
            label: "todo with a pre-existing block below",
            preexistingBlockBelow: true
        )
    }

    // MARK: - Zero-width first measurement (the bogus tall intrinsic)

    @Test
    func freshRichEditorAtZeroWidthDoesNotReportBogusHeight() {
        let textView = NotePaperTextView()
        textView.isRichText = true
        textView.minimumHeight = 0
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "这是需要换行的长文本内容 wrapping text more content"
        let intrinsic = textView.intrinsicContentSize.height
        #expect(intrinsic < 60,
                "a zero-width first measurement must report the one-line floor, not the width-0 wrapped height (got \(intrinsic))")
    }

    @Test
    func freshCodeEditorAtZeroWidthDoesNotReportBogusHeight() {
        let textView = CodeEditorTextView()
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.size = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "let x = 1\nlet y = 2\nlet z = 3"
        let intrinsic = textView.intrinsicContentSize.height
        #expect(intrinsic < 60,
                "a zero-width code editor must report the single-line floor (got \(intrinsic))")
    }
}
