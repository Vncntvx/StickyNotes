import Foundation
import Domain

// MARK: - LocalPreferences (T207, FR-014a clarified 2026-08-07)
//
// Per tasks.md T207 and data-model.md §LocalPreferences: device-local
// persistence of first-launch state in the standard UserDefaults domain.
// NEVER synchronized, NEVER in canonical JSON, NEVER in exported diagnostics
// (FR-191).
//
// Keys:
// - `onboardingHintSeen`: first-launch hint shown at least once.
// - `onboardingHintDismissed`: user dismissed the hint.
// - `hasCreatedFirstNote`: set when the first note is created; once true
//   the hint is never shown again.
//
// Global-shortcut bindings (`local.stickynotes.globalShortcuts.*`) were
// removed 2026-08-10 with the feature (no Carbon hotkeys in the app).

/// Device-local persistence of first-launch preferences (FR-014a). Stored
/// in the standard UserDefaults domain; NEVER synchronized, NEVER in
/// canonical JSON, NEVER in exported diagnostics.
///
/// `@unchecked Sendable`: `UserDefaults` is not statically Sendable, but
/// UserDefaults access is thread-safe (Apple documentation). The stored
/// keys are simple booleans with no intermediate inconsistent state.
public final class LocalPreferences: @unchecked Sendable {    private let defaults: UserDefaults

    /// The UserDefaults keys. Prefixed to avoid collisions.
    private enum Key {
        static let onboardingHintSeen = "local.stickynotes.onboardingHintSeen"
        static let onboardingHintDismissed = "local.stickynotes.onboardingHintDismissed"
        static let hasCreatedFirstNote = "local.stickynotes.hasCreatedFirstNote"
        static let autoSyncEnabled = "local.stickynotes.autoSyncEnabled"
        static let autoSyncPolicy = "local.stickynotes.autoSyncPolicy"
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Convenience initializer using the standard domain.
    public init() {
        self.defaults = .standard
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

    // MARK: - Auto-sync preference (FR-152/FR-152a, T285 + clarified 2026-08-08)

    /// Whether automatic synchronization is enabled (device-local).
    public var autoSyncEnabled: Bool {
        get { defaults.bool(forKey: Key.autoSyncEnabled) }
        set { defaults.set(newValue, forKey: Key.autoSyncEnabled) }
    }

    /// The user-selected automatic-sync strategy (FR-152, clarified
    /// 2026-08-08): change-only or a fixed periodic interval. Device-local,
    /// never synchronized.
    public var autoSyncPolicy: AutoSyncPolicy {
        get {
            guard let raw = defaults.string(forKey: Key.autoSyncPolicy),
                  let policy = AutoSyncPolicy(rawValue: raw) else {
                return .every15
            }
            return policy
        }
        set { defaults.set(newValue.rawValue, forKey: Key.autoSyncPolicy) }
    }
}

// MARK: - AutoSyncPolicy (FR-152, clarified 2026-08-08)

/// The user-selectable automatic-synchronization strategy: sync only after
/// local content changes (the FR-152a debounce), or additionally on a fixed
/// periodic interval. Device-local preference; never synchronized, never in
/// canonical JSON (FR-152).
public enum AutoSyncPolicy: String, CaseIterable, Sendable {
    case changeOnly
    case every5
    case every15
    case every30
    case every60

    /// The periodic interval in seconds; nil = no periodic sync.
    public var interval: TimeInterval? {
        switch self {
        case .changeOnly: return nil
        case .every5: return 5 * 60
        case .every15: return 15 * 60
        case .every30: return 30 * 60
        case .every60: return 60 * 60
        }
    }

    /// The default strategy: periodic every 15 minutes (FR-152).
    public static let `default` = AutoSyncPolicy.every15

    public var displayName: String {
        switch self {
        // Rev 3 (T185): on the "Periodic sync" axis, change-only IS "Off" —
        // the picker label names the axis (periodic), not the strategy.
        case .changeOnly: return String(localized: "Off")
        case .every5: return String(localized: "Every 5 minutes")
        case .every15: return String(localized: "Every 15 minutes")
        case .every30: return String(localized: "Every 30 minutes")
        case .every60: return String(localized: "Every hour")
        }
    }
}
