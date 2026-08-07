import Testing
import Foundation
import AppKit
import Domain
import EditorCore
@testable import StickyNotes

// MARK: - EditorAppBridge tests (T300, FR-050a/FR-054)
//
// Per tasks.md T300: the App path triggers the same operations the
// EditorCore tests verify — FR-050a empty-block removal (merge into the
// FOLLOWING block, clarified 2026-08-07; final block never removed; IME
// suppression) and FR-054 cross-block selection (copy places plain + rich
// text with supported formatting only; range-delete removes only the
// selected characters and merges emptied blocks).

@MainActor
@Suite struct EditorAppBridgeTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000011")!
    private static let noteId = UUID(uuidString: "e0000000-0000-4000-8000-000000000001")!

    private func richBlock(_ text: String, sortKey: Int) -> Block {
        Block(noteId: Self.noteId, kind: .richText, sortKey: sortKey,
              payload: .richText(.plain(text)), lastModifiedDeviceId: Self.deviceId)
    }

    private func specialImageBlock(sortKey: Int) -> Block {
        Block(
            noteId: Self.noteId,
            kind: .image,
            sortKey: sortKey,
            payload: .image(EmbeddedImagePayload(
                originalAssetId: UUID(),
                thumbnailAssetId: UUID(),
                caption: nil
            )),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    // MARK: - FR-050a empty-block removal (T300)

    @Test
    func emptyBlockRemovalMergesIntoFollowingBlock() {
        let blocks = [
            richBlock("first", sortKey: 0),
            richBlock("", sortKey: 1024),
            richBlock("last", sortKey: 2048),
        ]
        let updated = EditorAppBridge.applyEmptyBlockRemoval(
            blocks: blocks,
            emptiedBlockIndex: 1,
            hasIMEComposition: false
        )
        // The emptied block's slot collapses; the successor remains.
        #expect(updated?.count == 2)
        #expect(updated?.map(\.sortKey) == [0, 2048])
    }

    @Test
    func emptyBlockRemovalDeletesOutrightWhenSuccessorIsSpecial() {
        let blocks = [
            richBlock("first", sortKey: 0),
            richBlock("", sortKey: 1024),
            specialImageBlock(sortKey: 2048),
        ]
        let updated = EditorAppBridge.applyEmptyBlockRemoval(
            blocks: blocks,
            emptiedBlockIndex: 1,
            hasIMEComposition: false
        )
        // A special successor cannot accept a text merge → remove outright.
        #expect(updated?.count == 2)
        #expect(updated?.map(\.sortKey) == [0, 2048])
    }

    @Test
    func finalBlockIsNeverRemovedThroughTheAppPath() {
        let blocks = [
            richBlock("only", sortKey: 0),
            richBlock("", sortKey: 1024),   // final block
        ]
        #expect(EditorAppBridge.applyEmptyBlockRemoval(
            blocks: blocks,
            emptiedBlockIndex: 1,
            hasIMEComposition: false
        ) == nil)
    }

    @Test
    func removalSuppressedWhileIMEComposing() {
        let blocks = [
            richBlock("first", sortKey: 0),
            richBlock("", sortKey: 1024),
            richBlock("last", sortKey: 2048),
        ]
        // FR-063: never fires while an input-method composition is active.
        #expect(EditorAppBridge.applyEmptyBlockRemoval(
            blocks: blocks,
            emptiedBlockIndex: 1,
            hasIMEComposition: true
        ) == nil)
    }

    // MARK: - FR-054 cross-block selection (T300)

    @Test
    func copySpanningSelectionWritesPlainAndRichText() {
        let blocks = [
            richBlock("Hello **bold** world", sortKey: 0),
            richBlock("second paragraph", sortKey: 1024),
        ]
        let selection = CrossBlockSelection(selections: [
            (blockId: blocks[0].id, range: 0..<5),
            (blockId: blocks[1].id, range: 0..<6),
        ])
        let pasteboard = NSPasteboard.withUniqueName()
        let written = EditorAppBridge.copySpanningSelection(blocks: blocks, selection: selection, pasteboard: pasteboard)
        #expect(written)
        let plain = pasteboard.string(forType: .string)
        #expect(plain == "Hello\nsecond")
        let rtf = pasteboard.data(forType: .rtf)
        #expect(rtf != nil)
    }

    @Test
    func deleteSpanningSelectionRemovesOnlySelectedCharacters() {
        let blocks = [
            richBlock("Hello world", sortKey: 0),
            richBlock("second paragraph", sortKey: 1024),
        ]
        // Range 5..<11 removes " world" (including the separating space).
        let selection = CrossBlockSelection(selections: [
            (blockId: blocks[0].id, range: 5..<11),
        ])
        let updated = EditorAppBridge.deleteSpanningSelection(
            blocks: blocks,
            selection: selection,
            noteId: Self.noteId,
            deviceId: Self.deviceId
        )
        #expect(updated.count == 2)
        if case .richText(let doc) = updated[0].payload {
            #expect(doc.text == "Hello")
        } else {
            Issue.record("expected richText payload")
        }
        // The untouched second block is preserved.
        if case .richText(let doc) = updated[1].payload {
            #expect(doc.text == "second paragraph")
        } else {
            Issue.record("expected richText payload")
        }
    }

    @Test
    func deleteSpanningSelectionMergesEmptiedBlockAway() {
        // Deleting the whole first paragraph empties it; the emptied block
        // merges away per FR-050a (its successor remains).
        let blocks = [
            richBlock("first", sortKey: 0),
            richBlock("second", sortKey: 1024),
        ]
        let selection = CrossBlockSelection(selections: [
            (blockId: blocks[0].id, range: 0..<5),
        ])
        let updated = EditorAppBridge.deleteSpanningSelection(
            blocks: blocks,
            selection: selection,
            noteId: Self.noteId,
            deviceId: Self.deviceId
        )
        #expect(updated.count == 1)
        if case .richText(let doc) = updated[0].payload {
            #expect(doc.text == "second")
        } else {
            Issue.record("expected the successor to remain")
        }
    }
}
