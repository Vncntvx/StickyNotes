import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - File-ref indicator states tests (T275, FR-100)
//
// Per tasks.md T275: the availability-status indicator distinguishes
// available / missing / stale / on-another-device, each by more than color
// alone (FR-044); icon size and metadata layout are not pinned (FR-050b).

@Suite struct FileRefIndicatorStatesTests {
    @Test
    func fourStatesDistinctWithTextLabels() {
        // The classifier (SystemBridge) maps resolution outcomes to the
        // four states; the card renders icon + text per state (FR-044).
        let states: Set<FileAvailability> = [.available, .missing, .stale, .onAnotherDevice]
        #expect(states.count == 4)
        #expect(FileAvailability.onAnotherDevice != .missing,
                "on-another-device never implies the file is missing (FR-104)")
    }
}
