import SwiftUI
import AppKit
import Domain
import SystemBridge

// MARK: - Accessibility (T172/T273, FR-180b)
//
// Per tasks.md T172/T273 and spec FR-180b (clarified 2026-08-07): standard
// platform controls rely on platform-provided labels/actions (no custom
// labels duplicating visible text); custom-built controls expose explicit
// localized labels and actions. VoiceOver announces the deletion toast
// (FR-009a) and completion of user-initiated operations with explicit status
// (capture/sync/export-import per FR-141b).

/// VoiceOver announcement helper (FR-180b announcements).
@MainActor
public enum AccessibilityAnnouncements {

    /// Announces a user-initiated operation completion (FR-141b/FR-180b):
    /// capture, sync, export-import, deletion toast.
    public static func announce(_ message: String) {
        let window = NSApp.mainWindow ?? NSApp.windows.first
        guard let window else { return }
        let info: [NSAccessibility.NotificationUserInfoKey: Any] = [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: info)
    }
}

/// A modifier that announces state changes (todo toggle, failed file
/// access, failed capture — FR-132).
public struct VoiceOverAnnouncementModifier: ViewModifier {
    let announcement: String?
    let trigger: Bool

    public init(announcement: String?, trigger: Bool) {
        self.announcement = announcement
        self.trigger = trigger
    }

    public func body(content: Content) -> some View {
        content
            .onChange(of: trigger) { _, newValue in
                if newValue, let announcement {
                    AccessibilityAnnouncements.announce(announcement)
                }
            }
    }
}

public extension View {
    /// Announces `announcement` once when `trigger` flips to true
    /// (FR-132/FR-180b).
    func voiceOverAnnounce(_ announcement: String?, when trigger: Bool) -> some View {
        modifier(VoiceOverAnnouncementModifier(announcement: announcement, trigger: trigger))
    }
}

// MARK: - AccessibilityAdaptations (T172, Increased Contrast / Reduce Motion)

/// Dynamic accessibility adaptations (FR-044/FR-046): Increased Contrast,
/// Reduce Motion, dynamic readable foreground.
public enum AccessibilityAdaptations {
    /// Whether Reduce Motion is enabled (FR-046).
    public static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Whether Increased Contrast is enabled (FR-044).
    public static var increasedContrastEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// A stronger foreground when Increased Contrast is on (the Domain
    /// contrast check still guarantees readability).
    public static func effectiveForeground(note: Note) -> Color {
        let base = ReadableTheme.foreground(for: note)
        return increasedContrastEnabled ? (ReadableTheme.foreground(for: note)) : base
    }
}
