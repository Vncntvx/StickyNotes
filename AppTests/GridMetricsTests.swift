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

    // MARK: - T003 pre-redesign snapshot (003-macos27-liquid-glass-redesign)
    //
    // These pins record the CURRENT grid behavior before the FR-021 formula
    // redesign lands (tasks 003 T013/T014 migrate them to the new metric
    // source). They must pass on the pre-redesign code and FAIL after the
    // constants change — that failure is the explicit trigger for the
    // migration, not a regression.

    @Test
    func snapshotGridUsesFlexibleColumnsWithTwelvePointSpacing() {
        // Grid structure snapshot: flexible items, 12 pt spacing, count
        // derived from the column-count breakpoints.
        let items = LibraryCardGrid.columns(forWidth: 700)
        #expect(items.count == 3)
        #expect(items.allSatisfy { item in
            if case .flexible = item.size { return true } else { return false }
        })
        #expect(items.allSatisfy { $0.spacing == LibraryCardGrid.interCardSpacing })
    }

    @Test
    func snapshotLibraryWindowWidthYieldsTwoColumnsAtRedesignBoundary() {
        // The library scene is fixed at 420 pt wide (FR-001); at that width
        // the pre-redesign grid renders 2 columns. The FR-021 formula will
        // change the exact column count here — T013 asserts the new value.
        #expect(LibraryCardGrid.columnCount(forWidth: 420) == 2)
    }

    @Test
    func snapshotCardHeightBoundsAreFixed() {
        // The card's height frame is content-bounded between 140 and the
        // 160 pt constant (SC-022 density bounds arrive with the redesign).
        #expect(LibraryCardGrid.cardApproximateHeight >= 140, "cards are ≤160 pt tall, min frame 140")
    }
}
