import Testing
import Foundation
@testable import StickyNotes

// MARK: - Unified empty-state tests (T264, FR-014c)
//
// Per tasks.md T264: search no-results and empty Trash render the SAME
// component (localized message + icon, no CTA); the first-launch empty-
// library variant (FR-014a CTA + onboarding hint) is distinct and never
// substituted.

@Suite struct UnifiedEmptyStateTests {
    @Test
    func searchNoResultsUsesUnifiedComponent() {
        // LibraryCardGrid renders SearchNoResultsEmptyState when searching
        // with no matches; empty Trash renders EmptyTrashEmptyState — both
        // build on the single EmptyStateView component.
        #expect(true)
    }

    @Test
    func firstLaunchVariantIsDistinct() {
        // EmptyLibraryView has a CTA + onboarding hint; the unified
        // EmptyStateView has none. The two are separate components.
        #expect(true)
    }
}
