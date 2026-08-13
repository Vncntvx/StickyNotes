import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Add-Todo caret regression tests (004 修复 2026-08-13, 用户实测)
//
// Reported: inserting a todo with the caret at the END of the body's last
// visible line drops the todo far below the caret line and the body's
// paragraph rhythm shifts. Root cause candidate: when the block's text ends
// with a newline and the caret sits right BEFORE it (the visual end of the
// line), the split's trailing side is whitespace-only — the old Case C
// materialized it as an orphan rich-text block that renders extra vertical
// space. A whitespace-only trailing must be consumed exactly like an empty
// one (Case A).

@MainActor
@Suite struct TodoCaretInsertionRegressionTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000032")!

    // MARK: model-level insertion

    private func makeEnvironment() throws -> (AppEnvironment, URL) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("todo-caret-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: assetRoot, withIntermediateDirectories: true)
        let assetStore = try AssetStore(directoryURL: assetRoot)
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(directoryURL: assetRoot, store: assetStore),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.todocaret.\(UUID().uuidString)") ?? .standard)
        )
        return (env, assetRoot)
    }

    private func makeHost(env: AppEnvironment) async throws -> NoteWindowHostModel {
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            struct Failed: Error {}
            throw Failed()
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        return host
    }

    private func seedRichText(_ host: NoteWindowHostModel, text: String) async throws -> UUID {
        var blocks = host.blocks
        guard let richId = blocks.first(where: { $0.kind == .richText })?.id else {
            struct Failed: Error {}
            throw Failed()
        }
        blocks = blocks.map { block in
            guard block.id == richId else { return block }
            return Block(
                id: block.id, noteId: block.noteId, kind: .richText,
                sortKey: block.sortKey,
                payload: .richText(.plain(text)),
                versionId: block.versionId, parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt, modifiedAt: Date()
            )
        }
        host.updateBlocks(blocks)
        await host.flush()
        return richId
    }

    /// The caret at the END of the last visible line, right BEFORE the
    /// block's trailing newline ("…todo:|" with text "…todo:\n"). The
    /// whitespace-only trailing side must be consumed — never materialized
    /// as an orphan block below the inserted todo.
    @Test
    func caretBeforeTrailingNewlineConsumesItInsteadOfSplitting() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "body line\n下面开始输入 todo:\n")

        // The caret sits after ":" — one scalar before the trailing \n.
        let offset = Array("body line\n下面开始输入 todo:\n".unicodeScalars).count - 1
        guard let todoId = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: offset)) else {
            Issue.record("targeted insert failed")
            return
        }

        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2,
                "the whitespace-only trailing must be consumed, not split off (got \(persisted.count) blocks)")
        #expect(!persisted.contains { block in
            if case .richText(let doc) = block.payload, block.id != richId {
                return doc.text.allSatisfy(\.isWhitespace)
            }
            return false
        }, "no orphan whitespace-only rich-text block may remain")
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "body line\n下面开始输入 todo:",
                "the block keeps its visible text, trailing newline consumed (got \(doc.text.debugDescription))")
        guard let todo = persisted.first(where: { $0.id == todoId }) else {
            Issue.record("todo block missing")
            return
        }
        #expect(rich.sortKey < todo.sortKey, "the todo lands after the body block")
    }

    /// Several trailing empty paragraphs — all consumed, single insertion.
    @Test
    func caretBeforeRunOfTrailingEmptyLinesConsumesAllOfThem() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "alpha\n\n\n")

        // Caret right after "alpha", before the first of three newlines.
        guard let todoId = await host.insertTodoBlock(target: .caretSplit(blockId: richId, offset: 5)) else {
            Issue.record("targeted insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2, "all trailing empty paragraphs are consumed (got \(persisted.count))")
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "alpha")
        #expect(persisted.contains { $0.id == todoId })
    }

    /// A phantom left behind by the pre-fix build (whitespace-only secondary
    /// rich-text block) is swept by the NEXT structural insertion — the
    /// note heals without the user ever focusing the invisible block.
    @Test
    func preexistingWhitespacePhantomIsSweptByNextInsertion() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "body text")
        // The phantom: a whitespace-only secondary rich-text block.
        var blocks = host.blocks
        blocks.append(Block(
            noteId: host.noteId, kind: .richText, sortKey: 512,
            payload: .richText(.plain("\n")),
            lastModifiedDeviceId: deviceId
        ))
        host.updateBlocks(blocks)
        await host.flush()

        guard let todoId = await host.insertTodoBlock(target: .afterBlock(blockId: richId)) else {
            Issue.record("targeted insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2, "the phantom is swept by the insertion (got \(persisted.count))")
        #expect(persisted.contains { $0.id == richId })
        #expect(persisted.contains { $0.id == todoId })
    }

    /// The PRIMARY surface is exempt from the sweep — a whitespace-only
    /// primary stays (the caret-at-start zero-height slot / empty-note
    /// click target must survive).
    @Test
    func whitespaceOnlyPrimarySurvivesInsertion() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "\n")

        guard let todoId = await host.insertTodoBlock(target: .append) else {
            Issue.record("targeted insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2, "the primary surface is never swept (got \(persisted.count))")
        #expect(persisted.contains { $0.id == richId }, "the whitespace-only primary survives")
        #expect(persisted.contains { $0.id == todoId })
    }

    /// The menu-command path (⌘⇧T / Insert menu / degraded context) lands
    /// as `.append` — the insertion must STILL consume the trailing empty
    /// lines of the block it lands after, otherwise the new block renders
    /// below a phantom gap of empty paragraphs (the 错位 that survived the
    /// caretSplit fix).
    @Test
    func appendConsumesTrailingEmptyLinesOfPrecedingBlock() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "这是正文。\n下面开始输入 todo:\n\n")

        guard let todoId = await host.insertTodoBlock(target: .append) else {
            Issue.record("append insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 2, "append lands right after the content (got \(persisted.count))")
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "这是正文。\n下面开始输入 todo:",
                "the trailing empty lines are consumed (got \(doc.text.debugDescription))")
        guard let todo = persisted.first(where: { $0.id == todoId }) else {
            Issue.record("todo block missing")
            return
        }
        #expect(rich.sortKey < todo.sortKey)
    }

    /// Same consumption for `.afterBlock` (insertion right behind a
    /// rich-text block whose tail carries empty lines).
    @Test
    func afterBlockConsumesTrailingEmptyLines() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "body text\n\n")

        guard let codeId = await host.insertCodeBlock(target: .afterBlock(blockId: richId)) else {
            Issue.record("afterBlock insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "body text", "trailing empty lines consumed (got \(doc.text.debugDescription))")
        #expect(persisted.contains { $0.id == codeId })
    }

    /// Append never clobbers real content — only the whitespace tail goes.
    @Test
    func appendKeepsContentAndOnlyTrimsWhitespaceTail() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        let richId = try await seedRichText(host, text: "alpha\nbeta")  // no trailing whitespace

        guard let todoId = await host.insertTodoBlock(target: .append) else {
            Issue.record("append insert failed")
            return
        }
        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        guard let rich = persisted.first(where: { $0.id == richId }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "alpha\nbeta", "content untouched when no whitespace tail")
        #expect(persisted.contains { $0.id == todoId })
    }

    /// Existing notes repaired on open: persisted trailing empty lines are
    /// consumed at load, so the phantom gap disappears without the user
    /// having to trigger another insertion first.
    @Test
    func loadHealsPersistedTrailingEmptyLines() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        _ = try await seedRichText(host, text: "body\n下面开始输入 todo:\n\n")

        // Reopen: a fresh host over the same database.
        let reopened = NoteWindowHostModel(noteId: host.noteId, environment: env)
        await reopened.load()
        guard let rich = reopened.blocks.first(where: { $0.kind == .richText }),
              case .richText(let doc) = rich.payload else {
            Issue.record("rich block missing")
            return
        }
        #expect(doc.text == "body\n下面开始输入 todo:",
                "load heals the persisted trailing empty lines (got \(doc.text.debugDescription))")
    }

    // MARK: laid-out geometry (headless NSHostingView)

    private func collectTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for sub in view.subviews { found += collectTextViews(in: sub) }
        return found
    }

    private func frameInHosting(_ view: NSView, _ hosting: NSView) -> NSRect {
        view.convert(view.bounds, to: hosting)
    }

    /// Hosts [primary rich-text, todo] and measures the vertical gap
    /// between the primary's view bottom and the todo row's text editor.
    private func measureTodoGap(
        bodyText: String,
        extraBlocks: [Block] = []
    ) throws -> (gap: CGFloat, primaryFrame: NSRect, todoFrame: NSRect, primaryIntrinsic: CGFloat, extentBelowTodo: CGFloat) {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        var blocks = [
            Block(
                noteId: noteId, kind: .richText, sortKey: 0,
                payload: .richText(.plain(bodyText)),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                id: todoBlockId,
                noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: RichTextDocument.plain(""))),
                lastModifiedDeviceId: deviceId
            ),
        ]
        blocks.append(contentsOf: extraBlocks)
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        guard let primary = textViews.first(where: { $0.string == bodyText }),
              let todoEditor = textViews.first(where: { $0.string.isEmpty }) else {
            struct Failed: Error {}
            throw Failed()
        }
        let primaryFrame = frameInHosting(primary, hosting)
        let todoFrame = frameInHosting(todoEditor, hosting)
        let lowestBottom = textViews
            .map { frameInHosting($0, hosting).maxY }
            .max() ?? todoFrame.maxY
        return (todoFrame.minY - primaryFrame.maxY, primaryFrame, todoFrame,
                primary.intrinsicContentSize.height, max(0, lowestBottom - todoFrame.maxY))
    }

    /// The inserted todo sits DIRECTLY below the body's last line: the gap
    /// is the paper stack rhythm only (primary bottom inset + stack spacing
    /// + todo top inset) — never an inflated primary surface or a phantom
    /// block.
    @Test
    func todoLandsDirectlyBelowBodyLastLine() throws {
        let measured = try measureTodoGap(bodyText: "这是正文的第一句。连续句子，连续句子，连续句子。\n\n下面开始输入 todo:")
        // Primary must be content-sized once blocks follow it (the 320pt
        // click-target minimum must not survive the insertion).
        #expect(measured.primaryIntrinsic < 200,
                "the primary surface is content-sized after an insertion, got \(measured.primaryIntrinsic)")
        // Frame gap = the paper stack spacing only (8) — the 12pt insets
        // live INSIDE the editor views (visual gap ≈ 32).
        #expect(measured.gap >= 0 && measured.gap < 20,
                "the todo lands directly below the caret line, got gap \(measured.gap)")
    }

    /// The real user flow: the primary editor renders ALONE first (empty
    /// secondary list → minimumHeight stays the 320pt click target), THEN
    /// the todo insertion updates the same view in place. The 320pt
    /// minimum must collapse on that update — the todo lands directly
    /// below the body's last line, never far below it.
    @Test
    func primaryCollapsesWhenFirstBlockInsertedAfterIt() throws {
        let noteId = UUID()
        let bodyText = "这是正文的第一句。连续句子，连续句子，连续句子。\n\n下面开始输入 todo:"
        let before = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
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

        // The insertion lands — same identity, blocks gain the todo.
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let after = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: [
                Block(noteId: noteId, kind: .richText, sortKey: 0,
                      payload: .richText(.plain(bodyText)),
                      lastModifiedDeviceId: deviceId),
                Block(id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                      payload: .todo(TodoPayload(todoId: todoId, richText: RichTextDocument.plain(""))),
                      lastModifiedDeviceId: deviceId)
            ],
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        hosting.rootView = after
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        guard let primary = textViews.first(where: { $0.string == bodyText }),
              let todoEditor = textViews.first(where: { $0.string.isEmpty }) else {
            struct Failed: Error {}
            throw Failed()
        }
        let primaryFrame = frameInHosting(primary, hosting)
        let todoFrame = frameInHosting(todoEditor, hosting)
        let gap = todoFrame.minY - primaryFrame.maxY
        #expect(primary.intrinsicContentSize.height < 200,
                "the primary collapses to content height once blocks follow, got \(primary.intrinsicContentSize.height)")
        #expect(gap >= 0 && gap < 20,
                "the todo lands directly below the caret line after the in-place update, got gap \(gap)")
    }

    /// An orphan whitespace-only rich-text block (the pre-fix Case C
    /// trailing) renders a phantom editor BELOW the todo — visible dead
    /// space at the insertion site. The model fix (consume the trailing)
    /// guarantees this shape never reaches the renderer.
    @Test
    func orphanWhitespaceBlockRendersPhantomSpaceBelowTodo() throws {
        let noteId = UUID()
        let orphan = Block(
            noteId: noteId, kind: .richText, sortKey: 2048,
            payload: .richText(.plain("\n")),
            lastModifiedDeviceId: deviceId
        )
        let withOrphan = try measureTodoGap(bodyText: "下面开始输入 todo:", extraBlocks: [orphan])
        let clean = try measureTodoGap(bodyText: "下面开始输入 todo:")
        // The phantom editor materializes ~40pt of dead space below the
        // todo row (one empty line + insets) — this is what the user sees
        // as "the insertion landed with a gap".
        #expect(withOrphan.extentBelowTodo - clean.extentBelowTodo > 20,
                "an orphan block renders phantom space below the todo")
    }

    // MARK: - Width reflow (Goal A / Test Group B, 2026-08-13)
    //
    // A todo's OWN text editor is an NSTextView too: narrowing the window
    // must reflow its soft-wrapped text and push the block below — never
    // overflow into it.

    @Test
    func todoTextReflowsPushingCodeBelowAtNarrowWidth() async throws {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let todoText = String(
            repeating: "这条待办没有任何硬换行只依赖软换行来换行显示。", count: 4
        )
        let blocks = [
            Block(
                noteId: noteId, kind: .richText, sortKey: 0,
                payload: .richText(.plain("below")),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: RichTextDocument.plain(todoText))),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                noteId: noteId, kind: .code, sortKey: 2048,
                payload: .code(CodePayload(text: "let x = 1", language: nil)),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let todoEditor = try #require(
            collectTextViews(in: hosting).first { $0.string == todoText },
            "todo editor not realized"
        )
        let wideIntrinsic = todoEditor.intrinsicContentSize.height
        let codeWide = try #require(
            collectTextViews(in: hosting).first { $0 is CodeEditorTextView },
            "code editor not realized"
        )
        let wideCodeMinY = frameInHosting(codeWide, hosting).minY

        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 900)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        let todoNarrow = try #require(
            textViews.first { $0.string == todoText },
            "todo editor missing after narrow resize"
        )
        let codeEditor = try #require(
            textViews.first { $0 is CodeEditorTextView },
            "code editor not realized"
        )

        #expect(todoNarrow.intrinsicContentSize.height > wideIntrinsic + 1,
                "the todo text must reflow taller at 320 (\(wideIntrinsic) → \(todoNarrow.intrinsicContentSize.height))")
        // The deferred first-line metric lands on the next runloop turn —
        // poll until the row settles, then measure the FINAL frames: the
        // applied frame must match the reflowed intrinsic and the code
        // block must have moved down below it.
        var frameDelta: CGFloat = .greatestFiniteMagnitude
        var todoFrame = frameInHosting(todoNarrow, hosting)
        var codeFrame = frameInHosting(codeEditor, hosting)
        for _ in 0..<25 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            todoFrame = frameInHosting(todoNarrow, hosting)
            codeFrame = frameInHosting(codeEditor, hosting)
            frameDelta = abs(todoFrame.height - todoNarrow.intrinsicContentSize.height)
            if frameDelta < 3 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(frameDelta < 3,
                "SwiftUI must apply the reflowed height to the todo editor frame (Δ\(frameDelta))")
        #expect(codeFrame.minY > wideCodeMinY + 1,
                "the code block must move DOWN when the todo text reflows (\(wideCodeMinY) → \(codeFrame.minY))")
        #expect(codeFrame.minY >= todoFrame.maxY - 0.5,
                "the reflowed todo must not overflow into the code block: todo.maxY \(todoFrame.maxY) vs code.minY \(codeFrame.minY)")
    }

    // MARK: - Todo marker alignment (Test Group F, 004 修复 2026-08-14, P0)
    //
    // Three separated sizes: visual marker (symbol intrinsic), the layout
    // marker COLUMN (fixed gutter), the interaction hit target (the whole
    // column). The todo text leading must be paper edge + column + gap —
    // expanding the hit target must never drift the text.

    @Test
    func todoMarkerGutterKeepsTextLeadingStable() throws {
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
                payload: .richText(.plain("hello")),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: .plain("single line todo"))),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        let primary = try #require(textViews.first { $0.string == "hello" }, "primary not realized")
        let todo = try #require(textViews.first { $0.string == "single line todo" }, "todo editor not realized")
        let primaryFrame = frameInHosting(primary, hosting)
        let todoFrame = frameInHosting(todo, hosting)

        let expectedLeading = primaryFrame.minX
            + BlockLayoutMetrics.todoMarkerColumnWidth
            + BlockLayoutMetrics.todoMarkerGap
        #expect(abs(todoFrame.minX - expectedLeading) < 2,
                "todo text leading = paper edge + marker column + gap (fixed gutter), got Δ\(todoFrame.minX - expectedLeading)")
        #expect(BlockLayoutMetrics.todoMarkerColumnWidth >= 16,
                "the marker column must be wide enough for a comfortable hit target")
    }

    /// The platform baseline override must report the layout manager's REAL
    /// first-line baseline (container inset + first-line ascender).
    @Test
    func notePaperFirstBaselineTracksFontMetrics() {
        let editor = NotePaperTextView()
        editor.isRichText = true
        editor.font = NSFont.systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 0, height: 12)
        editor.textContainer?.lineFragmentPadding = 0
        editor.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        editor.string = "hello"
        let baseline = editor.firstBaselineOffsetFromTop
        let expected = 12 + (editor.font?.ascender ?? 0)
        #expect(abs(baseline - expected) < 2,
                "firstBaselineOffsetFromTop = container inset + first-line ascender, got \(baseline) vs \(expected)")
    }

    /// The checkbox's VISUAL center sits on the FIRST line's typographic
    /// center (real TextKit geometry — no hardcoded offset). CJK text is
    /// the discriminator: the fallback font changes the actual line metric
    /// vs the nominal font the old resolver-based math used. The metric
    /// bridge lands on the next runloop turn (state writes are deferred
    /// out of the update pass) — poll until the row converges.
    @Test
    func todoMarkerAlignsToFirstLineTypographicCenter() async throws {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let blocks = [
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: .plain("这是 todo 内容"))),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { _ in item }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let todoEditor = try #require(
            collectTextViews(in: hosting).first { $0.string.hasPrefix("这是") },
            "todo editor not realized"
        )
        let layoutManager = try #require(todoEditor.layoutManager)
        let container = try #require(todoEditor.textContainer)

        var lastDelta: CGFloat = .greatestFiniteMagnitude
        var converged = false
        for _ in 0..<50 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            layoutManager.ensureLayout(for: container)
            let todoFrame = frameInHosting(todoEditor, hosting)
            let fragmentRect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let expectedCenterY = todoFrame.minY
                + todoEditor.textContainerInset.height
                + fragmentRect.midY

            // Candidate marker backing views: small views LEFT of the todo
            // text, vertically overlapping its first line. The row also
            // carries the insertion-control overlay at the same leading
            // edge — collect ALL candidates and converge on the closest
            // center (the checkbox is the one aligned to the line).
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
            let deltas = candidates.map { abs($0.midY - expectedCenterY) }
            lastDelta = deltas.min() ?? .greatestFiniteMagnitude
            if lastDelta < 3 {
                converged = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(converged,
                "the marker's visual center must converge onto the first line's typographic center (last Δ\(lastDelta))")
    }

    /// Single-line and multi-line todos share the EXACT same text leading
    /// — the marker column is fixed, the hit target overflow never widens
    /// it.
    @Test
    func todoTextLeadingIdenticalForSingleAndMultiLine() throws {
        let noteId = UUID()
        let singleBlockId = UUID()
        let multiBlockId = UUID()
        let singleTodoId = UUID()
        let multiTodoId = UUID()
        let items = [
            TodoItem(id: singleTodoId, noteId: noteId, blockId: singleBlockId, sortKey: 1024, depth: 0, lastModifiedDeviceId: deviceId),
            TodoItem(id: multiTodoId, noteId: noteId, blockId: multiBlockId, sortKey: 2048, depth: 0, lastModifiedDeviceId: deviceId),
        ]
        let blocks = [
            Block(
                id: singleBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: singleTodoId, richText: .plain("single line"))),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                id: multiBlockId, noteId: noteId, kind: .todo, sortKey: 2048,
                payload: .todo(TodoPayload(todoId: multiTodoId, richText: .plain("line one\nline two\nline three"))),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: blocks,
            onBlocksChanged: { _ in },
            todoProvider: { blockId in items.first { $0.blockId == blockId } }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        let single = try #require(textViews.first { $0.string == "single line" }, "single-line todo not realized")
        let multi = try #require(textViews.first { $0.string.hasPrefix("line one") }, "multi-line todo not realized")
        let singleFrame = frameInHosting(single, hosting)
        let multiFrame = frameInHosting(multi, hosting)

        #expect(abs(singleFrame.minX - multiFrame.minX) < 0.5,
                "single-line and multi-line todos must share one text leading (Δ\(singleFrame.minX - multiFrame.minX))")
    }

    /// A multi-line todo's row stays text-driven: the marker column adds
    /// no height of its own (the row height = the text editor's height —
    /// the checkbox aligns within it), so the block below tracks directly.
    /// (The checkbox's exact Y is baseline-aligned via the platform metric
    /// asserted in `notePaperFirstBaselineTracksFontMetrics`; the optical
    /// result is verified visually.)
    @Test
    func multiLineTodoRowStaysTextDriven() throws {
        let noteId = UUID()
        let todoBlockId = UUID()
        let todoId = UUID()
        let item = TodoItem(
            id: todoId, noteId: noteId, blockId: todoBlockId, sortKey: 1024,
            depth: 0, lastModifiedDeviceId: deviceId
        )
        let blocks = [
            Block(
                id: todoBlockId, noteId: noteId, kind: .todo, sortKey: 1024,
                payload: .todo(TodoPayload(todoId: todoId, richText: .plain("line one\nline two\nline three"))),
                lastModifiedDeviceId: deviceId
            ),
            Block(
                noteId: noteId, kind: .code, sortKey: 2048,
                payload: .code(CodePayload(text: "let x = 1", language: nil)),
                lastModifiedDeviceId: deviceId
            ),
        ]
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
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
            textViews.first { $0.string.hasPrefix("line one") },
            "todo editor not realized"
        )
        let codeEditor = try #require(
            textViews.first { $0 is CodeEditorTextView },
            "code editor not realized"
        )
        let todoFrame = frameInHosting(todoEditor, hosting)
        let codeFrame = frameInHosting(codeEditor, hosting)

        // Three lines of text — the row must actually be multi-line
        // (proving the marker column did not flatten or inflate it).
        #expect(todoFrame.height > 40,
                "the multi-line todo row keeps its text height, got \(todoFrame.height)")
        // No phantom inflation: the code card starts right below the text.
        #expect(codeFrame.minY - 8 - todoFrame.maxY < 20,
                "the marker column must not inflate the row, gap \(codeFrame.minY - 8 - todoFrame.maxY)")
    }
}
