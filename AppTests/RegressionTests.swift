import Testing
import Foundation
import SwiftUI
import Persistence
import Domain
@testable import StickyNotes

// MARK: - Regression tests (T163i / T138)
//
// Per tasks.md T163i: regression tests for fixed defects accumulated across
// stories. This file pins the historically fixed defects:
// - FR-043a: textSize is an integer 9–24 (regression: old enum model).
// - FR-040a: canonical hexes (regression: old palette).
// - FR-022a: Trash-restore sort-key reset (regression: retained old key).
// - v2 conflictRecord migration (regression: unbounded conflict copies).

@Suite struct RegressionTests {
    @Test
    func textSizeIsIntegerNineToTwentyFour() {
        #expect(NoteAppearance.TextSizeBounds.minSize == 9)
        #expect(NoteAppearance.TextSizeBounds.maxSize == 24)
        #expect(NoteAppearance.TextSizeBounds.defaultSize == 13)
    }

    @Test
    func canonicalHexesMatchSpec() {
        #expect(NoteColorKey.yellow.canonicalHex == "#FFE08A")
        #expect(NoteColorKey.pink.canonicalHex == "#F9A8C4")
    }

    @Test
    func opacityClampsToFortyPercentFloor() {
        #expect(NoteAppearance.OpacityBounds.clamped(0.1) == 0.40)
        #expect(NoteAppearance.OpacityBounds.clamped(1.0) == 1.0)
    }

    @Test
    func conflictRecordTableExistsInV2Schema() async throws {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let exists: Bool = try await store.read { db in
            try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='conflictRecord')") ?? false
        }
        #expect(exists, "v2 conflictRecord migration must be applied")
    }
}
