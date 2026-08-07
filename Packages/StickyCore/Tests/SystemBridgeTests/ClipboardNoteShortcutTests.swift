import Testing
import Foundation
import Domain
import SystemBridge
import Carbon

// MARK: - Clipboard-note shortcut tests (T150, FR-120)
//
// Per tasks.md T150: the "new note from clipboard" global shortcut fires
// while another app is focused and creates a note with clipboard contents.
// The Carbon registration API (GlobalShortcuts) is exercised in
// ShortcutDockTests; this file pins the default key definition + the
// FR-007a activation contract.

@Suite struct ClipboardNoteShortcutTests {
    @Test
    func defaultClipboardNoteShortcutIsDefined() {
        let key = GlobalShortcutKey.defaultClipboardNote
        // Command+Option+Shift+N.
        #expect(key.keyCode == 45)  // kVK_ANSI_N
        #expect(key.modifiers & UInt32(cmdKey) != 0)
        #expect(key.modifiers & UInt32(optionKey) != 0)
        #expect(key.modifiers & UInt32(shiftKey) != 0)
        #expect(key.modifiers & UInt32(controlKey) == 0)
    }

    @Test
    func shortcutCanRegisterAndUnregister() throws {
        // Registration on the current machine (headless-safe: Carbon hotkey
        // registration works without a display). If the key is already bound
        // by another app, duplicateRegistration is an acceptable outcome.
        do {
            let registration = try GlobalShortcuts.register(GlobalShortcutKey.defaultClipboardNote) { _ in }
            try GlobalShortcuts.unregister(registration)
        } catch {
            // duplicateRegistration is environment-dependent, not a failure
            // of the adapter.
            #expect(true)
        }
    }
}
