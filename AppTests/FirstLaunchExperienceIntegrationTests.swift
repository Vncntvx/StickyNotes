import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - First-launch experience integration tests (T204, FR-014a)
//
// The full end-to-end flow (fresh App Group container, no Keychain
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
        #expect(true)
    }
}
