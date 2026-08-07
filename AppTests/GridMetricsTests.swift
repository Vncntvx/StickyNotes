import Testing
import Foundation
import SwiftUI
@testable import StickyNotes

// MARK: - Card-grid metrics tests (T287, FR-002a)
//
// Per tasks.md T287: the card grid uses 3 columns at ≥600 pt window width,
// 2 below 600, and 1 below 400; cards are ≈220×160 pt; inter-card spacing
// is 12 pt.

@Suite struct GridMetricsTests {

    @Test
    func columnCountFollowsResponsiveBreakpoints() {
        #expect(LibraryCardGrid.columnCount(forWidth: 700) == 3, "3 columns at ≥600")
        #expect(LibraryCardGrid.columnCount(forWidth: 600) == 3, "3 columns at exactly 600")
        #expect(LibraryCardGrid.columnCount(forWidth: 599) == 2, "2 columns below 600")
        #expect(LibraryCardGrid.columnCount(forWidth: 400) == 2, "2 columns at exactly 400")
        #expect(LibraryCardGrid.columnCount(forWidth: 399) == 1, "1 column below 400")
        #expect(LibraryCardGrid.columnCount(forWidth: 420) == 2, "the 420 pt library window renders 2 columns (FR-002a)")
    }

    @Test
    func gridUsesTwelvePointSpacing() {
        let columns = LibraryCardGrid.columns(forWidth: 700)
        #expect(columns.count == 3)
        #expect(columns.allSatisfy { $0.spacing == LibraryCardGrid.interCardSpacing })
        #expect(LibraryCardGrid.interCardSpacing == 12, "12 pt inter-card spacing")
    }

    @Test
    func cardDimensionsMatchSpec() {
        #expect(LibraryCardGrid.cardApproximateWidth == 220, "card width ≈ 220 pt")
        #expect(LibraryCardGrid.cardApproximateHeight == 160, "card height ≈ 160 pt")
    }
}
