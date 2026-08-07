import Testing
import Foundation
import Carbon
import Domain
import SystemBridge
@testable import StickyNotes

// MARK: - Global-shortcut configuration tests (T296, FR-120/FR-121)
//
// Per tasks.md T296: per-action shortcut persistence (language-neutral key
// codes) and conflict detection on registration (FR-121 — never silently
// replaced).

@MainActor
@Suite struct ShortcutConfigurationTests {

    @Test
    func shortcutStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "test.shortcuts.\(UUID().uuidString)")!
        let preferences = LocalPreferences(defaults: defaults)
        let action = LocalPreferences.ShortcutAction.newBlankNote

        #expect(preferences.shortcutKey(for: action) == nil, "unset by default")
        let key = GlobalShortcutKey(keyCode: 45, modifiers: UInt32(cmdKey | optionKey | shiftKey))
        preferences.setShortcutKey(key, for: action)
        let stored = preferences.shortcutKey(for: action)
        #expect(stored == key, "key code + modifiers round-trip (language-neutral, FR-120)")

        preferences.setShortcutKey(nil, for: action)
        #expect(preferences.shortcutKey(for: action) == nil, "clear removes the binding")
    }

    @Test
    func eachActionHasItsOwnBinding() {
        let defaults = UserDefaults(suiteName: "test.shortcuts.\(UUID().uuidString)")!
        let preferences = LocalPreferences(defaults: defaults)
        let a = GlobalShortcutKey(keyCode: 45, modifiers: UInt32(cmdKey | shiftKey))
        let b = GlobalShortcutKey(keyCode: 46, modifiers: UInt32(cmdKey | shiftKey))
        preferences.setShortcutKey(a, for: .newBlankNote)
        preferences.setShortcutKey(b, for: .clipboardNote)
        #expect(preferences.shortcutKey(for: .newBlankNote) == a)
        #expect(preferences.shortcutKey(for: .clipboardNote) == b)
    }

    @Test
    func duplicateRegistrationIsDetected() throws {
        // FR-121: registering the same shortcut twice fails loudly instead
        // of silently replacing (Carbon reports the conflict).
        let key = GlobalShortcutKey.defaultClipboardNote
        let registration = try GlobalShortcuts.register(key) { _ in }
        defer { try? GlobalShortcuts.unregister(registration) }
        do {
            _ = try GlobalShortcuts.register(key) { _ in }
            Issue.record("expected a duplicate-registration error (FR-121)")
        } catch GlobalShortcutError.duplicateRegistration {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
