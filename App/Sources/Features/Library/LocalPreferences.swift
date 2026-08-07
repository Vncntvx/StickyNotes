import Foundation
import Domain

// MARK: - LocalPreferences (T207, FR-014a clarified 2026-08-07)
//
// Per tasks.md T207 and data-model.md §LocalPreferences: device-local
// persistence of first-launch state in App Group UserDefaults. NEVER
// synchronized, NEVER in canonical JSON, NEVER in exported diagnostics
// (FR-191). The Widget Extension does NOT read these keys.
//
// Keys:
// - `onboardingHintSeen`: first-launch hint shown at least once.
// - `onboardingHintDismissed`: user dismissed the hint.
// - `hasCreatedFirstNote`: set when the first note is created; once true
//   the hint is never shown again.

/// Device-local persistence of first-launch preferences (FR-014a). Stored
/// in App Group UserDefaults so the app and any future App-Group-aware
/// surface share the state; NEVER synchronized, NEVER in canonical JSON,
/// NEVER in exported diagnostics.
///
/// `@unchecked Sendable`: `UserDefaults` is not statically Sendable, but
/// UserDefaults access is thread-safe (Apple documentation). The stored
/// keys are simple booleans with no intermediate inconsistent state.
public final class LocalPreferences: @unchecked Sendable {
    private let defaults: UserDefaults

    /// The App Group UserDefaults suite. The widget does NOT read these
    /// keys (data-model.md §LocalPreferences).
    public static let suiteName = "group.local.stickynotes.placeholder"

    /// The UserDefaults keys. Prefixed to avoid collisions.
    private enum Key {
        static let onboardingHintSeen = "local.stickynotes.onboardingHintSeen"
        static let onboardingHintDismissed = "local.stickynotes.onboardingHintDismissed"
        static let hasCreatedFirstNote = "local.stickynotes.hasCreatedFirstNote"
        static let autoSyncEnabled = "local.stickynotes.autoSyncEnabled"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience initializer using the App Group suite.
    public init() {
        self.defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    // MARK: - FirstLaunchState (FR-014a)

    /// Reads the current first-launch state from UserDefaults.
    public var firstLaunchState: FirstLaunchState {
        FirstLaunchState(
            seen: defaults.bool(forKey: Key.onboardingHintSeen),
            dismissed: defaults.bool(forKey: Key.onboardingHintDismissed),
            hasCreatedFirstNote: defaults.bool(forKey: Key.hasCreatedFirstNote)
        )
    }

    /// Persists the first-launch state to UserDefaults.
    public func saveFirstLaunchState(_ state: FirstLaunchState) {
        defaults.set(state.seen, forKey: Key.onboardingHintSeen)
        defaults.set(state.dismissed, forKey: Key.onboardingHintDismissed)
        defaults.set(state.hasCreatedFirstNote, forKey: Key.hasCreatedFirstNote)
    }

    /// Marks the onboarding hint as seen (shown at least once).
    public func markOnboardingHintSeen() {
        defaults.set(true, forKey: Key.onboardingHintSeen)
    }

    /// Marks the onboarding hint as dismissed (never shown again).
    public func dismissOnboardingHint() {
        defaults.set(true, forKey: Key.onboardingHintDismissed)
    }

    /// Marks that the user has created their first note (never shown again).
    public func markFirstNoteCreated() {
        defaults.set(true, forKey: Key.hasCreatedFirstNote)
    }

    /// Resets all first-launch state (for tests / fresh-launch scenarios).
    public func resetFirstLaunchState() {
        defaults.removeObject(forKey: Key.onboardingHintSeen)
        defaults.removeObject(forKey: Key.onboardingHintDismissed)
        defaults.removeObject(forKey: Key.hasCreatedFirstNote)
    }

    // MARK: - Auto-sync preference (FR-152, T285)

    /// Whether automatic synchronization is enabled (device-local).
    public var autoSyncEnabled: Bool {
        get { defaults.bool(forKey: Key.autoSyncEnabled) }
        set { defaults.set(newValue, forKey: Key.autoSyncEnabled) }
    }
}
