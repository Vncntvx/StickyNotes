import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import Domain

// MARK: - PermissionService (T104)
//
// Per plan §Permissions: the permission service exposes current status,
// feature-specific explanations, request actions, open-System-Settings
// actions, and denied-state recovery.
//
// - Screen recording: requested ONLY on capture invocation. The status check
//   uses `CGPreflightScreenCaptureAccess` — no prompt is shown.
// - Accessibility: reserved for future "identify active window"; NEVER
//   requested at startup or during ordinary capture (constitution VI).
//   Ordinary capture must not need it (research.md R7).
//
// No AppKit is needed for status checks; the "open System Settings" action
// is provided for callers on the main actor.

/// Permission status for the two permission domains the app touches.
public enum PermissionStatus: String, Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

/// Feature-scoped permission model (plan §Permissions).
public enum PermissionDomain: String, Sendable {
    case screenRecording
    case accessibility
}

/// The permission service. Pure status checks; the "open System Settings"
/// helper is AppKit-free (uses the `x-apple.systempreferences` scheme).
public enum PermissionService {

    /// Current screen-recording status. Safe to call at any time; never
    /// prompts.
    public static func screenRecordingStatus() -> PermissionStatus {
        if CGPreflightScreenCaptureAccess() {
            return .granted
        }
        // macOS reports denial vs not-yet-asked through the trusted state;
        // if the process was never asked there is no way to distinguish
        // without prompting, so not-yet-granted is treated as notDetermined.
        return .notDetermined
    }

    /// Whether the app can capture without any further user action.
    public static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests screen-recording permission directly: presents the system
    /// authorization dialog when the user has not decided yet, and routes to
    /// the Screen Capture privacy pane when the user previously denied it
    /// (re-requesting a denied permission opens System Settings). Returns
    /// whether the permission is granted after the request. Only called when
    /// the user invokes the feature (FR-131).
    @MainActor
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Requests accessibility permission: presents the system accessibility
    /// authorization dialog. Constitution 2.0.0 / FR-131 (clarified
    /// 2026-08-08): this MUST only ever be invoked from an explicit,
    /// user-initiated action on the Settings permissions page — never during
    /// startup, first launch, or ordinary note editing. Returns whether the
    /// permission is granted after the request.
    @MainActor
    public static func requestAccessibility() -> Bool {
        // "AXTrustedCheckOptionPrompt" is the stable public value of
        // kAXTrustedCheckOptionPrompt (AXUIElement.h); the non-Sendable
        // global `var` constant cannot be referenced under Swift 6 strict
        // concurrency.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Current accessibility status. NEVER called at startup or during
    /// ordinary capture (constitution VI; plan §Permissions).
    public static func accessibilityStatus() -> PermissionStatus {
        let trusted = AXIsProcessTrusted()
        return trusted ? .granted : .notDetermined
    }

    /// Feature-specific explanation for the permission domain (localized by
    /// the App layer; the code here is language-neutral).
    public static func featureExplanation(for domain: PermissionDomain) -> String {
        switch domain {
        case .screenRecording:
            return "screenRecording.required.forCapture"
        case .accessibility:
            return "accessibility.required.advancedWindowIDOnly"
        }
    }

    /// A short, sanitized recovery hint per domain (language-neutral key).
    public static func recoveryHint(for domain: PermissionDomain) -> String {
        switch domain {
        case .screenRecording:
            return "screenRecording.denied.openSystemSettings"
        case .accessibility:
            return "accessibility.denied.onlyAdvancedWindowIDUnavailable"
        }
    }

    /// Opens the relevant pane of System Settings via NSWorkspace on the main
    /// actor (the SystemBridge module is App-linked; DockActivationBridge
    /// already imports AppKit, so there is no "AppKit-free" constraint to
    /// preserve here).
    @MainActor
    public static func openSystemSettings(for domain: PermissionDomain) -> Bool {
        switch domain {
        case .screenRecording:
            return openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        case .accessibility:
            return openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    private static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
