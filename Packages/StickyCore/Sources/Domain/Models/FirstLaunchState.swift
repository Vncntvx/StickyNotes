import Foundation

// MARK: - FirstLaunchState (T206, FR-014a clarified 2026-08-07)
//
// Per tasks.md T206 and research R28 / data-model.md §LocalPreferences:
// a pure Foundation-only state machine for the first-launch onboarding hint.
// No UserDefaults or App Group references in Domain (storage lives in the
// App layer, T207). The state machine decides whether the dismissible
// onboarding hint (explaining auto-save and the menu-bar-primary model)
// should be shown on launch.
//
// Rules (FR-014a):
// - `shouldShowOnboardingHint == true` on a fresh state (seen=false,
//   dismissed=false, hasCreatedFirstNote=false).
// - `false` once `hasCreatedFirstNote` is set (never shown again after the
//   first note is created).
// - `false` once `dismissed` is set.
// - `false` when dismissed even if seen.
// - The state is device-local, never synchronized, never in canonical JSON,
//   never in exported diagnostics.

/// Pure-Domain first-launch hint state machine (FR-014a). Storage lives in
/// the App layer (T207 `LocalPreferences`); this type is the pure value the
/// App layer reads/writes.
public struct FirstLaunchState: Sendable, Equatable, Codable {
    /// Whether the hint has been shown at least once.
    public var seen: Bool
    /// Whether the user explicitly dismissed the hint.
    public var dismissed: Bool
    /// Whether the user has created their first note (once true, the hint
    /// is never shown again).
    public var hasCreatedFirstNote: Bool

    public init(seen: Bool = false, dismissed: Bool = false, hasCreatedFirstNote: Bool = false) {
        self.seen = seen
        self.dismissed = dismissed
        self.hasCreatedFirstNote = hasCreatedFirstNote
    }

    /// A fresh state (nothing seen, nothing dismissed, no first note).
    public static let fresh = FirstLaunchState()

    /// Returns `true` if the onboarding hint should be shown on launch.
    /// Per FR-014a: shown only when the user has not dismissed it AND has
    /// not yet created their first note. Once `hasCreatedFirstNote` or
    /// `dismissed` is set, the hint is never shown again.
    public var shouldShowOnboardingHint: Bool {
        !dismissed && !hasCreatedFirstNote
    }

    /// Marks the hint as seen (seen = true). Does not dismiss it.
    public mutating func markSeen() {
        seen = true
    }

    /// Marks the hint as dismissed (never shown again).
    public mutating func dismiss() {
        dismissed = true
    }

    /// Marks that the user has created their first note (never shown again).
    public mutating func markFirstNoteCreated() {
        hasCreatedFirstNote = true
    }
}
