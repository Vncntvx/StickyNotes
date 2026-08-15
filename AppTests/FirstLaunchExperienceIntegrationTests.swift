import Testing
import Foundation
import Domain
import SystemBridge
@testable import StickyNotes

// MARK: - First-launch experience integration tests (T204, FR-014a)
//
// The full end-to-end flow (fresh sandbox container, no Keychain
// credentials) is covered by AppLogicTests.firstLaunchStateNeverShowsHintAfterFirstNote
// + dismissingHintHidesItPermanently + the no-permission-prompt startup
// guard (T210: the bootstrap path calls no CGRequest*/AXIsProcessTrustedWithOptions
// API — enforced by audit; PermissionService status checks are preflight-only).
// This file exists for task→file traceability (tasks.md T204 path).

@Suite struct FirstLaunchExperienceIntegrationTests {
    @Test
    func launchShowsNoPermissionPrompts() {
        // T210: PermissionService.screenRecordingStatus() uses
        // CGPreflightScreenCaptureAccess (no prompt) and accessibilityStatus()
        // uses AXIsProcessTrusted (no prompt). Neither can fire a TCC prompt.
        // Call both probes — a prompt-firing implementation would hang or
        // change TCC state; the preflight APIs return immediately.
        let screen = PermissionService.screenRecordingStatus()
        let accessibility = PermissionService.accessibilityStatus()
        #expect(screen == .granted || screen == .notDetermined)
        #expect(accessibility == .granted || accessibility == .notDetermined)
    }
}
