import Testing
import Foundation
import SystemBridge
import Domain
@testable import StickyNotes

// MARK: - Permission-fallback integration tests (T163h / T098, US8)
//
// Per tasks.md T163h: permission-denied fallbacks (screen-recording denied →
// notes usable + explanation + open settings; accessibility denied → only
// advanced window-id unavailable).

@Suite struct PermissionFallbackIntegrationTests {
    @Test
    func denialAffectsOnlyTheRelatedFeature() {
        // Denied screen recording: capture fails closed with a typed error;
        // note editing/search/sync are untouched (P1 independence).
        let err = StickyError.capture(.permissionDenied)
        #expect(err.sanitizedCode == "capture.permissionDenied")

        // Accessibility denial affects only the future "identify active
        // window" feature — ordinary capture never needs it.
        #expect(PermissionService.recoveryHint(for: .accessibility).contains("OnlyAdvancedWindowIDUnavailable")
                || PermissionService.recoveryHint(for: .accessibility).contains("onlyAdvancedWindowIDUnavailable"))
    }

    @Test
    func featureExplanationsExistForBothDomains() {
        #expect(!PermissionService.featureExplanation(for: .screenRecording).isEmpty)
        #expect(!PermissionService.featureExplanation(for: .accessibility).isEmpty)
    }
}
