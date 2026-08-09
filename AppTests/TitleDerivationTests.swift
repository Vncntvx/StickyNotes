import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Title derivation tests (004 T006, spec FR-003)
//
// Per tasks.md T006 and data-model.md §4.1: `deriveWindowTitle` — manual
// title wins, else the first content line, else the localized "Untitled
// Note" fallback. Long input is never truncated (the titlebar applies the
// system ellipsis visually).

@Suite struct TitleDerivationTests {

    @Test
    func manualTitleTakesPriority() {
        #expect(NoteWindowDerivations.deriveWindowTitle(
            noteTitle: "Groceries",
            firstLine: "buy milk"
        ) == "Groceries", "manual title wins (FR-003)")
    }

    @Test
    func whitespaceOnlyManualTitleFallsThrough() {
        #expect(NoteWindowDerivations.deriveWindowTitle(
            noteTitle: "   ",
            firstLine: "buy milk"
        ) == "buy milk", "whitespace-only title is not a title (FR-003)")
    }

    @Test
    func firstLineFallbackTrimsWhitespace() {
        #expect(NoteWindowDerivations.deriveWindowTitle(
            noteTitle: nil,
            firstLine: "  buy milk  "
        ) == "buy milk", "first line trimmed (FR-003)")
    }

    @Test
    func emptyContentFallsBackToLocalizedUntitled() {
        #expect(NoteWindowDerivations.deriveWindowTitle(
            noteTitle: nil,
            firstLine: ""
        ) == String(localized: "note.window.untitledTitle", defaultValue: "Untitled Note"),
        "localized fallback when empty (FR-003)")
    }

    @Test
    func longFirstLineIsNeverTruncated() {
        let long = String(repeating: "a", count: 400)
        #expect(NoteWindowDerivations.deriveWindowTitle(
            noteTitle: nil,
            firstLine: long
        ) == long, "the derived title keeps the full first line (system ellipsis truncates visually)")
    }

    @Test
    func firstLineStopsAtNewline() {
        let doc = RichTextDocument.plain("first line\nsecond line")
        #expect(NoteWindowDerivations.firstLine(of: doc) == "first line")
    }

    @Test
    func firstLineOfEmptyDocumentIsEmpty() {
        #expect(NoteWindowDerivations.firstLine(of: .empty) == "")
    }
}
