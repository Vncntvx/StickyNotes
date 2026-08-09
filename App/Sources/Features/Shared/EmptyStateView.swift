import SwiftUI
import Domain

// MARK: - EmptyStateView (T270, FR-014c)
//
// Per tasks.md T270 and spec FR-014c (clarified 2026-08-07): the UNIFIED
// empty-state component — a localized message + icon, NO call-to-action, no
// other content; ONE component, spacing, and visual style. Wired into search
// no-results (LibraryCardGrid) and empty Trash (TrashView). The
// first-launch empty-library variant (EmptyLibraryView, FR-014a) is a
// distinct component (CTA + onboarding hint) and is NEVER substituted.

/// The unified empty-state component (FR-014c).
public struct EmptyStateView: View {
    let systemImage: String
    let message: LocalizedStringKey

    public init(systemImage: String, message: LocalizedStringKey) {
        self.systemImage = systemImage
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}

/// Search no-results empty state (FR-014c + FR-011a: never an error).
public struct SearchNoResultsEmptyState: View {
    public init() {}

    public var body: some View {
        EmptyStateView(
            systemImage: "magnifyingglass",
            message: "No notes match your search"
        )
    }
}

/// Empty-Trash empty state (FR-014c).
public struct EmptyTrashEmptyState: View {
    public init() {}

    public var body: some View {
        EmptyStateView(
            systemImage: "trash",
            message: "Trash is empty"
        )
    }
}
