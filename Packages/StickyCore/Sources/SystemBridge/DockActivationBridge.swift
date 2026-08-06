import Foundation
import AppKit
import Domain

// MARK: - DockActivationBridge (T103)
//
// Per tasks.md T103 and plan §Dynamic Dock activation behavior (research.md
// R4):
//
// - Default `regular` (Dock icon on). The user may switch to `accessory` at
//   runtime without restart where reliable; Settings/Help/About/sync
//   status/Quit remain reachable from the menu-bar library (FR-008).
// - A widget opening a note MUST NOT flip the Dock policy (FR-008, FR-009):
//   deep links must not call `setActivationPolicy`. This bridge exposes the
//   policy as read-only state plus an explicit user-requested switch, so
//   deep-link routing has no path to flip the Dock.
// - Command-Tab: `regular` appears in the app switcher; `accessory` does
//   not. Documented OS-level behavior, not worked around.

/// Runtime Dock activation-policy control.
@MainActor
public enum DockActivationBridge {

    /// The app's current activation policy. Returns `.regular` when the app
    /// has not been fully launched (e.g. inside a test bundle without an
    /// NSApplication) — the production app always has one.
    public static func currentPolicy() -> NSApplication.ActivationPolicy {
        guard let app = NSApp else { return .regular }
        return app.activationPolicy()
    }

    /// The activation policy requested by the user's Dock preference
    /// (true = Dock icon visible). Read-only — widget deep links must NOT
    /// switch the Dock (FR-008).
    public static func isDockEnabled() -> Bool {
        currentPolicy() == .regular
    }

    /// Switches the Dock policy at runtime (user-initiated only). Note
    /// windows keep working in accessory mode; the menu-bar library remains
    /// reachable.
    ///
    /// - Throws: `.permission(.accessibilityDenied)`-equivalent mapping is
    ///   NOT used — activation policy needs no permission. Failures surface
    ///   as a plain runtime error.
    public static func setDockEnabled(_ enabled: Bool) throws {
        let policy: NSApplication.ActivationPolicy = enabled ? .regular : .accessory
        guard let app = NSApp else {
            // No NSApplication yet (test/early-launch context): nothing to
            // switch; the policy applies once the app launches.
            return
        }
        let ok = app.setActivationPolicy(policy)
        guard ok else {
            throw DockActivationError.policySwitchFailed
        }
    }

    /// Whether a deep-link route is allowed to touch the Dock policy.
    /// Always false for widget-originated routes (FR-008: a widget opening
    /// a note must not flip Dock policy).
    public static func deepLinkMayChangeDockPolicy(originIsWidget: Bool) -> Bool {
        !originIsWidget
    }
}

/// Typed errors for Dock policy switching.
public enum DockActivationError: Error, Sendable, Equatable {
    case policySwitchFailed

    public var sanitizedCode: String {
        switch self {
        case .policySwitchFailed: return "dock.policySwitchFailed"
        }
    }
}
