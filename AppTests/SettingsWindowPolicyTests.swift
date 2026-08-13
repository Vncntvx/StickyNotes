import Testing
import Foundation
@testable import StickyNotes

// MARK: - SettingsWindowPolicy tests (003 T175, FR-051 Rev 2)
//
// Pins the implementation-level window-shell contract (FR-051 Rev 2 asserts
// the BEHAVIOR; these tests pin the current values): a stable default size
// larger than the minimum, a minimum that keeps the primary (text)
// navigation expanded in en and zh-Hans, tab switches never resizing the
// window, and scrolling containers only on tabs that can actually overflow
// (Sync).

@Suite struct SettingsWindowPolicyTests {
    @Test
    func defaultSizeIsLargerThanMinimum() {
        #expect(SettingsWindowPolicy.defaultWidth > SettingsWindowPolicy.minimumWidth)
        #expect(SettingsWindowPolicy.defaultHeight > SettingsWindowPolicy.minimumHeight)
    }

    @Test
    func minimumKeepsTextNavigationExpanded() {
        // Three text tabs (General/Sync/Privacy + icons) need ≥600pt to
        // stay expanded in en and zh-Hans; the minimum enforces it.
        #expect(SettingsWindowPolicy.minimumWidth >= 600)
        #expect(SettingsWindowPolicy.navigationNeverCollapsesAtMinimumWidth)
    }

    @Test
    func geometryIsStableAcrossTabs() {
        #expect(SettingsWindowPolicy.windowSizeStableAcrossTabs)
        #expect(SettingsWindowPolicy.onlyOverflowingTabsScroll)
    }
}
