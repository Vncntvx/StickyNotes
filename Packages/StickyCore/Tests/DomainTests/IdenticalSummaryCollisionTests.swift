import Testing
import Foundation
import Domain

// MARK: - Identical summary collision tests (T274, FR-021)
//
// Per tasks.md T274: "Domain test: identical-summary collision acceptance per
// FR-021 — two notes whose first meaningful content is byte-identical: assert
// both generate identical summary strings (no disambiguation suffix); assert
// the cards remain distinguishable through the other deterministic card
// fields (last-modified time, note color, 2-line body preview per FR-020a);
// assert the generated summary never becomes a permanent manual title per
// FR-021".

@Suite struct IdenticalSummaryCollisionTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    private func note(blocks: [Block], modifiedAt: Date, colorKey: NoteColorKey) -> Note {
        Note(
            colorKey: colorKey,
            lastModifiedDeviceId: Self.deviceId,
            modifiedAt: modifiedAt
        )
    }

    private func richBlock(noteId: UUID, text: String) -> Block {
        Block(
            noteId: noteId,
            kind: .richText,
            sortKey: 0,
            payload: .richText(RichTextDocument.plain(text)),
            lastModifiedDeviceId: Self.deviceId
        )
    }

    @Test
    func byteIdenticalContentProducesIdenticalSummaries() {
        let text = "Buy milk and eggs"
        let noteA = note(blocks: [], modifiedAt: Date(), colorKey: .yellow)
        let noteB = note(blocks: [], modifiedAt: Date(), colorKey: .blue)

        let blocksA = [richBlock(noteId: noteA.id, text: text)]
        let blocksB = [richBlock(noteId: noteB.id, text: text)]

        let summaryA = NoteSummary.generatedSummary(for: blocksA)
        let summaryB = NoteSummary.generatedSummary(for: blocksB)

        // No disambiguation suffix — both are identical (FR-021).
        #expect(summaryA == summaryB)
        #expect(summaryA == text)
    }

    @Test
    func identicalSummariesDoNotCarryDistinguishingSuffix() {
        let text = "Meeting notes"
        let noteA = note(blocks: [], modifiedAt: Date(), colorKey: .yellow)
        let noteB = note(blocks: [], modifiedAt: Date(), colorKey: .yellow)

        let summaryA = NoteSummary.generatedSummary(for: [richBlock(noteId: noteA.id, text: text)])!
        let summaryB = NoteSummary.generatedSummary(for: [richBlock(noteId: noteB.id, text: text)])!

        #expect(summaryA == "Meeting notes")
        #expect(summaryB == "Meeting notes")
        // A disambiguation suffix like "(2)" would violate FR-021.
        #expect(!summaryA.contains("("))
        #expect(!summaryB.contains("(2)"))
    }

    @Test
    func cardsRemainDistinguishableViaOtherDeterministicFields() {
        let text = "Shared content"
        let noteA = note(blocks: [], modifiedAt: Date(timeIntervalSince1970: 1_700_000_000), colorKey: .yellow)
        let noteB = note(blocks: [], modifiedAt: Date(timeIntervalSince1970: 1_700_100_000), colorKey: .pink)

        #expect(noteA.modifiedAt != noteB.modifiedAt, "last-modified time distinguishes cards")
        #expect(noteA.colorKey != noteB.colorKey, "note color distinguishes cards")

        // The 2-line body preview source (FR-020a) comes from the first
        // rich-text block — same here, but the display rule is App-side.
        let blocksA = [richBlock(noteId: noteA.id, text: text)]
        let blocksB = [richBlock(noteId: noteB.id, text: text)]
        #expect(NoteSummary.generatedSummary(for: blocksA) == NoteSummary.generatedSummary(for: blocksB))
    }

    @Test
    func generatedSummaryNeverBecomesManualTitle() {
        let text = "Auto-generated"
        let note = note(blocks: [], modifiedAt: Date(), colorKey: .yellow)
        let blocks = [richBlock(noteId: note.id, text: text)]

        #expect(note.title == nil, "summary must never be stored as title")
        let summary = NoteSummary.generatedSummary(for: blocks)!
        // displayTitle prefers a manual title, falls back to the summary.
        var withTitle = note
        withTitle.title = "Manual"
        #expect(NoteSummary.displayTitle(note: withTitle, blocks: blocks) == "Manual")
        #expect(summary == text)
    }
}
