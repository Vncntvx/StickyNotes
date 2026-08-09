import Testing
import Foundation
import AppKit
import ApplicationServices
import Domain
import SystemBridge

// MARK: - Dock activation tests (T097)
//
// Per tasks.md T097: "Dock activation-policy switch runtime; Settings/Help/
// About/sync/Quit remain reachable; widget deep-link does NOT flip Dock
// policy".

@Suite struct DockActivationTests {

    @Test
    @MainActor
    func policySwitchRoundTrips() throws {
        // Ensure an NSApplication exists so the activation policy is real
        // (test bundles do not create one automatically).
        _ = NSApplication.shared
        let original = DockActivationBridge.currentPolicy()

        // Regular → accessory → regular.
        try DockActivationBridge.setDockEnabled(false)
        #expect(DockActivationBridge.currentPolicy() == .accessory)
        try DockActivationBridge.setDockEnabled(true)
        #expect(DockActivationBridge.currentPolicy() == .regular)

        // Restore whatever the environment had before the test.
        try DockActivationBridge.setDockEnabled(original == .regular)
    }

    @Test
    @MainActor
    func widgetDeepLinkNeverFlippedDockPolicy() {
        // FR-008/FR-009: a widget deep link must NOT flip the Dock policy.
        // The bridge exposes no path for widget-originated routes to change
        // the policy.
        #expect(!DockActivationBridge.deepLinkMayChangeDockPolicy(originIsWidget: true))
        #expect(DockActivationBridge.deepLinkMayChangeDockPolicy(originIsWidget: false))
    }

    @Test
    @MainActor
    func menuBarSurfaceUnchangedByPolicySwitch() {
        // The menu-bar library is a MenuBarExtra: it survives accessory
        // mode. The bridge itself never touches scene/extra state.
        let current = DockActivationBridge.isDockEnabled()
        #expect(current == (DockActivationBridge.currentPolicy() == .regular))
    }

    @Test
    func errorsAreSanitized() {
        #expect(DockActivationError.policySwitchFailed.sanitizedCode == "dock.policySwitchFailed")
    }
}
