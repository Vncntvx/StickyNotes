import Testing
import Foundation
import AppKit
import SwiftUI
import Domain
import Persistence
import AssetStore
import SystemBridge
@testable import StickyNotes

// MARK: - Code-block layout + deletion regression tests (004 修复 2026-08-13)
//
// Reported (用户实测, post phantom-gap fix): "还是有大段间隔 code block 还无法
// 删除". Pixel measurement of the screenshot located the remaining gap ABOVE
// the code card: the primary paper's 12pt BOTTOM text-container inset plus
// the 8pt paper-stack spacing leave ~20pt of dead paper under the body's
// last ink line before the card even begins (and the same insets inflate
// every block-to-block rhythm to 30pt+). The code card itself is
// content-sized. These tests pin the collapsed rhythm.
//
// Second report: a code block has NO delete affordance (only the copy
// button) — the host-level deletion guard below backs the new hover menu's
// wiring (RichTextBlockView onDeleteCode → NoteWindowHostModel.deleteBlock).

@MainActor
@Suite struct CodeBlockLayoutRegressionTests {

    private let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000033")!

    // MARK: environment (same recipe as TodoCaretInsertionRegressionTests)

    private func makeEnvironment() throws -> (AppEnvironment, URL) {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let assetRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("code-layout-tests-\(UUID().uuidString)", isDirectory: true)
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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.codelayout.\(UUID().uuidString)") ?? .standard)
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

    // MARK: hosting helpers

    private func collectTextViews(in view: NSView) -> [NSTextView] {
        var found: [NSTextView] = []
        if let textView = view as? NSTextView { found.append(textView) }
        for sub in view.subviews { found += collectTextViews(in: sub) }
        return found
    }

    private func frameInHosting(_ view: NSView, _ hosting: NSView) -> NSRect {
        view.convert(view.bounds, to: hosting)
    }

    /// Hosts [primary rich-text, code] and measures the rhythm between the
    /// primary surface and the code editor.
    private func measureCodeGeometry(
        bodyText: String,
        codeText: String
    ) throws -> (
        gap: CGFloat,
        primaryFrame: NSRect,
        primaryUsed: CGFloat,
        primaryIntrinsic: CGFloat,
        codeFrame: NSRect
    ) {
        let noteId = UUID()
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: [
                Block(
                    noteId: noteId, kind: .richText, sortKey: 0,
                    payload: .richText(.plain(bodyText)),
                    lastModifiedDeviceId: deviceId
                ),
                Block(
                    noteId: noteId, kind: .code, sortKey: 1024,
                    payload: .code(CodePayload(text: codeText, language: nil)),
                    lastModifiedDeviceId: deviceId
                ),
            ],
            onBlocksChanged: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let textViews = collectTextViews(in: hosting)
        guard let primary = textViews.first(where: { $0.string == bodyText }),
              let code = textViews.first(where: { $0.string == codeText }) else {
            struct Failed: Error {}
            throw Failed()
        }
        let primaryFrame = frameInHosting(primary, hosting)
        let codeFrame = frameInHosting(code, hosting)
        let used = primary.layoutManager?.usedRect(for: primary.textContainer ?? NSTextContainer()).height ?? 0
        return (codeFrame.minY - primaryFrame.maxY, primaryFrame, used,
                primary.intrinsicContentSize.height, codeFrame)
    }

    // MARK: geometry

    /// The code card lands DIRECTLY below the body's last line: the frame
    /// gap is the paper-stack spacing + the card's interior padding/insets
    /// only — the primary surface's bottom text-container inset must NOT
    /// inflate it (that inset is the dead paper under the last ink line the
    /// user reported as 大段间隔).
    @Test
    func codeCardLandsDirectlyBelowBodyLastLine() throws {
        let measured = try measureCodeGeometry(
            bodyText: "这是正文的第一句。连续句子。\n下面开始输入 code:",
            codeText: "首次"
        )
        // Gap = paper-stack spacing (8) + card padding (8) + code inset (4)
        // = 20pt. Before the collapse the primary's 12pt bottom inset
        // inflated it to ~32pt.
        #expect(measured.gap >= 0 && measured.gap <= 21,
                "the code card lands directly below the caret line, got gap \(measured.gap)")
    }

    /// When blocks follow the paper, the primary's intrinsic height keeps
    /// the TOP inset (first-line breathing room under the controls row) but
    /// drops the BOTTOM one (the stack spacing owns the rhythm below).
    @Test
    func primaryCollapsesBottomInsetWhenBlocksFollow() throws {
        let measured = try measureCodeGeometry(
            bodyText: "下面开始输入 code:",
            codeText: "首次"
        )
        // Content-sized primary: used + top inset only.
        #expect(measured.primaryIntrinsic < measured.primaryUsed + 24 - 6,
                "the bottom inset is collapsed once blocks follow (intrinsic \(measured.primaryIntrinsic), used \(measured.primaryUsed))")
        #expect(measured.primaryIntrinsic >= measured.primaryUsed + 12 - 1,
                "the top inset survives the collapse (intrinsic \(measured.primaryIntrinsic), used \(measured.primaryUsed))")
    }

    /// An ALONE primary paper keeps the full symmetric inset — the bottom
    /// inset is part of the comfortable typing/click surface while the
    /// paper IS the whole note.
    @Test
    func primaryAloneKeepsBottomInset() throws {
        let noteId = UUID()
        let bodyText = "独享纸面的一段正文。"
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: [
                Block(
                    noteId: noteId, kind: .richText, sortKey: 0,
                    payload: .richText(.plain(bodyText)),
                    lastModifiedDeviceId: deviceId
                )
            ],
            onBlocksChanged: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        guard let primary = collectTextViews(in: hosting).first(where: { $0.string == bodyText }) else {
            Issue.record("primary editor missing")
            return
        }
        let used = primary.layoutManager?.usedRect(for: primary.textContainer ?? NSTextContainer()).height ?? 0
        let intrinsic = primary.intrinsicContentSize.height
        // Full insets (12 + 12) OR the 320pt paper minimum — never less.
        #expect(intrinsic >= max(used + 24 - 1, 320 - 1),
                "the alone paper keeps its bottom inset / 320pt click target (intrinsic \(intrinsic), used \(used))")
    }

    /// A content-sized editor with EMPTY text keeps a one-line click/caret
    /// target (the zero-inset secondary editors must not collapse to
    /// 0pt — the caret would vanish and the block could not be clicked).
    @Test
    func emptyContentSizedEditorKeepsOneLineTarget() throws {
        let noteId = UUID()
        let bodyText = "正文。"
        let trailingId = UUID()
        let view = RichTextBlockView(
            note: Note(lastModifiedDeviceId: deviceId),
            blocks: [
                Block(
                    noteId: noteId, kind: .richText, sortKey: 0,
                    payload: .richText(.plain(bodyText)),
                    lastModifiedDeviceId: deviceId
                ),
                Block(
                    id: trailingId,
                    noteId: noteId, kind: .richText, sortKey: 1024,
                    payload: .richText(.plain("")),
                    lastModifiedDeviceId: deviceId
                ),
            ],
            onBlocksChanged: { _ in }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 420, height: 600)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let textViews = collectTextViews(in: hosting)
        guard let trailing = textViews.first(where: { $0.string.isEmpty && $0 !== textViews.first }) else {
            Issue.record("trailing editor missing")
            return
        }
        let height = frameInHosting(trailing, hosting).height
        #expect(height >= 12, "the empty content-sized editor keeps a one-line target, got \(height)")
    }

    // MARK: deletion wiring

    /// The code block's delete affordance routes to the host's structural
    /// deletion: the block row disappears immediately (FR-141a) and the
    /// note keeps its remaining blocks.
    @Test
    func codeBlockDeleteRemovesBlockImmediately() async throws {
        let (env, _) = try makeEnvironment()
        let host = try await makeHost(env: env)
        var blocks = host.blocks
        guard let richId = blocks.first(where: { $0.kind == .richText })?.id else {
            Issue.record("rich block missing")
            return
        }
        let codeBlock = Block(
            noteId: host.noteId, kind: .code, sortKey: 1024,
            payload: .code(CodePayload(text: "首次", language: nil)),
            lastModifiedDeviceId: deviceId
        )
        blocks.append(codeBlock)
        host.updateBlocks(blocks, isStructural: true)
        await host.flush()

        await host.deleteBlock(id: codeBlock.id)

        let persisted = try await env.persistence.noteRepository!.fetchBlocks(noteId: host.noteId)
        #expect(persisted.count == 1, "the code block is deleted (got \(persisted.count))")
        #expect(persisted.first?.id == richId)
        #expect(!host.blocks.contains { $0.id == codeBlock.id })
    }
}
