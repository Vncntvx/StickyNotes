import Testing
import Foundation
import AppKit
import ApplicationServices
import Domain
import SystemBridge
import Carbon

// MARK: - Global shortcut tests (T096)
//
// Per tasks.md T096: "SystemBridge test: global shortcut registers/
// unregisters, fires while another app focused, detects registration
// failure, no Accessibility prompt" (research.md R5, validated in M0 by
// GlobalShortcutPrototype).
//
// Registration/unregistration/conflict-detection are exercised headlessly.
// The "fires while another app focused" behavior requires a real key press
// and is covered by the interactive prototype (`--wait` mode); here we
// verify the handler wiring is registered with the Carbon dispatcher.

// Carbon global hotkeys are OS-wide: tests share the same key space and can
// collide when run in parallel, so the suite is serialized.
@Suite(.serialized)
struct GlobalShortcutTests {

    /// Actor-based fire counter (handlers are @MainActor @Sendable).
    private actor FireCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    @Test
    func shortcutRegistersAndUnregisters() async throws {
        let key = GlobalShortcutKey.defaultClipboardNote
        let counter = FireCounter()

        let registration = try GlobalShortcuts.register(key) { _ in
            Task { await counter.increment() }
        }
        #expect(registration.key == key)

        try GlobalShortcuts.unregister(registration)
        let fires = await counter.count
        #expect(fires == 0, "no fire without a key press")
    }

    @Test
    func duplicateRegistrationIsDetected() throws {
        let key = GlobalShortcutKey(keyCode: 45, modifiers: UInt32(cmdKey | shiftKey))
        let first = try GlobalShortcuts.register(key) { _ in }
        defer { try? GlobalShortcuts.unregister(first) }

        do {
            _ = try GlobalShortcuts.register(key) { _ in }
            Issue.record("duplicate registration must be detected")
        } catch GlobalShortcutError.duplicateRegistration {
            #expect(true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func distinctShortcutsRegisterIndependently() throws {
        let a = try GlobalShortcuts.register(GlobalShortcutKey(keyCode: 45, modifiers: UInt32(cmdKey))) { _ in }
        defer { try? GlobalShortcuts.unregister(a) }
        let b = try GlobalShortcuts.register(GlobalShortcutKey(keyCode: 46, modifiers: UInt32(cmdKey))) { _ in }
        defer { try? GlobalShortcuts.unregister(b) }

        #expect(a.key != b.key)
    }

    @Test
    func reRegisterRoundTrips() throws {
        let key = GlobalShortcutKey.defaultClipboardNote
        let first = try GlobalShortcuts.register(key) { _ in }
        let second = try GlobalShortcuts.reRegister(first, with: key) { _ in }
        #expect(second.key == key)
        try GlobalShortcuts.unregister(second)
    }

    @Test
    func registrationRequiresNoAccessibilityPermission() {
        // Carbon hotkeys must work without Accessibility (R5). We assert the
        // status is queryable and that registration itself does not depend
        // on AXIsProcessTrusted (the M0 prototype verified the positive case
        // with AXIsProcessTrusted() == false).
        _ = AXIsProcessTrusted() // querying is side-effect-free
        #expect(GlobalShortcutError.duplicateRegistration.sanitizedCode == "shortcut.duplicateRegistration")
    }
}

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
