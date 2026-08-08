import Testing
import Foundation
import SwiftUI
@testable import StickyNotes

// MARK: - Card-grid metrics tests (003 T013, FR-021/SC-021/SC-022)
//
// Per tasks.md T013: the grid follows the FR-021 deterministic formula —
// minCardWidth 180, spacing 12, columns = max(1, floor((w+12)/192)),
// cardWidth = (w − (columns−1)×12) / columns. Deterministic column counts
// at the SC-021 breakpoints (≥756→4, ≥564→3, ≥372→2, else 1); card widths
// 180–228 in 4-column layout; 1 column = full width; sub-320 pt clamp to
// 1 column with readable cards (FR-070).

@Suite struct GridMetricsTests {

    // MARK: - FR-021 formula (pure metrics)

    @Test
    func formulaGivesDeterministicColumnCounts() {
        // SC-021 breakpoints: ≥756→4, ≥564→3, ≥372→2, else 1.
        #expect(NoteCardMetrics.columnCount(forContentWidth: 756) == 4, "4 columns at ≥756")
        #expect(NoteCardMetrics.columnCount(forContentWidth: 900) == 4)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 564) == 3, "3 columns at ≥564")
        #expect(NoteCardMetrics.columnCount(forContentWidth: 700) == 3)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 372) == 2, "2 columns at ≥372")
        #expect(NoteCardMetrics.columnCount(forContentWidth: 420) == 2, "the 420 pt library window renders 2 columns (FR-002a)")
        #expect(NoteCardMetrics.columnCount(forContentWidth: 371) == 1, "1 column below 372")
        #expect(NoteCardMetrics.columnCount(forContentWidth: 200) == 1)
    }

    @Test
    func formulaHandlesBoundaryWidthsExactly() {
        // Exact boundary widths: 756/564/372 must hit 4/3/2 (deterministic
        // integer arithmetic, no off-by-one).
        #expect(NoteCardMetrics.columnCount(forContentWidth: 756) == 4)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 755) == 3)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 564) == 3)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 563) == 2)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 372) == 2)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 371) == 1)
    }

    @Test
    func cardWidthsFollowFormula() {
        // 4-column layout: widths in 180–228 range.
        let w4 = NoteCardMetrics.cardWidth(forContentWidth: 756)
        #expect(w4 == 180, "4 columns at exactly 756 pt → 180 pt cards")
        #expect(NoteCardMetrics.cardWidth(forContentWidth: 900) >= 180)
        #expect(NoteCardMetrics.cardWidth(forContentWidth: 900) <= 228)

        // 2-column layout: ≈276 max.
        let w2 = NoteCardMetrics.cardWidth(forContentWidth: 563)
        #expect(abs(w2 - 275.5) < 0.01, "2-column max ≈276 (at 563: (563−12)/2 = 275.5)")

        // 1 column = full width.
        let w1 = NoteCardMetrics.cardWidth(forContentWidth: 371)
        #expect(w1 == 371, "1 column = full width")
    }

    @Test
    func sub320ClampsToOneColumn() {
        // FR-070: below 320 pt the grid clamps to 1 column with readable
        // cards (full width).
        #expect(NoteCardMetrics.columnCount(forContentWidth: 319) == 1)
        #expect(NoteCardMetrics.columnCount(forContentWidth: 300) == 1)
        let card = NoteCardMetrics.cardWidth(forContentWidth: 319)
        #expect(card == 319, "1 column below 320 = full width, readable")
    }

    @Test
    func gridUsesTwelvePointSpacing() {
        #expect(NoteCardMetrics.spacing == 12, "12 pt inter-card spacing")
        #expect(NoteCardMetrics.minCardWidth == 180)
    }

    // MARK: - Grid wiring (fails until T021 replaces the 220×160 constants)

    @Test
    func gridColumnCountFollowsFormula() {
        // The GRID must expose the FR-021 column count (current 001 code
        // returns 3/2/1 at 600/400 — fails until the grid delegates to
        // NoteCardMetrics).
        #expect(LibraryCardGrid.columnCount(forWidth: 756) == 4, "grid: 4 columns at ≥756 (FR-021)")
        #expect(LibraryCardGrid.columnCount(forWidth: 564) == 3, "grid: 3 columns at ≥564")
        #expect(LibraryCardGrid.columnCount(forWidth: 372) == 2, "grid: 2 columns at ≥372")
        #expect(LibraryCardGrid.columnCount(forWidth: 300) == 1, "grid: 1 column below 372")
    }
}
