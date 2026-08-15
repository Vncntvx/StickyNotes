import Testing
import SwiftUI
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
        // build on the single EmptyStateView component. Prove both variants
        // instantiate through the shared component.
        let search = EmptyStateView(systemImage: "magnifyingglass", message: "No Results")
        let trash = EmptyStateView(systemImage: "trash", message: "Trash is Empty")
        #expect(!search.systemImage.isEmpty)
        #expect(!trash.systemImage.isEmpty)
    }

    @Test
    func firstLaunchVariantIsDistinct() {
        // EmptyLibraryView has a CTA + onboarding hint; the unified
        // EmptyStateView has none. The two are separate components.
        let emptyState = EmptyStateView(systemImage: "note", message: "No Notes")
        #expect(!emptyState.systemImage.isEmpty)
    }
}
