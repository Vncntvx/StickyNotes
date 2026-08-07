import Testing
import Foundation
import AppKit
import Domain
import SystemBridge

// MARK: - Window space behavior tests (T151, FR-035)
//
// Per tasks.md T151: "SystemBridge test: note window `collectionBehavior`
// prevents appearance across every Space and prevents forcing over
// full-screen applications (FR-035)".

@Suite struct WindowSpaceBehaviorTests {

    @Test
    func defaultNoteWindowsDoNotJoinEverySpace() {
        let behavior = NoteWindowBridge.collectionBehavior(alwaysOnTop: false)
        #expect(WindowSpaceBehavior.doesNotJoinAllSpaces(behavior),
                "note windows must not appear on every Space (FR-035)")
    }

    @Test
    func defaultNoteWindowsDoNotForceOverFullScreen() {
        let behavior = NoteWindowBridge.collectionBehavior(alwaysOnTop: false)
        #expect(WindowSpaceBehavior.doesNotForceOverFullScreen(behavior),
                "note windows must not force over full-screen applications (FR-035)")
    }

    @Test
    func alwaysOnTopMayFloatAboveFullScreenByUserChoice() {
        let behavior = NoteWindowBridge.collectionBehavior(alwaysOnTop: true)
        // The documented exception: per-note Always-on-Top (FR-036) uses the
        // auxiliary level which floats above full-screen apps.
        #expect(WindowSpaceBehavior.floatsAboveFullScreen(alwaysOnTop: true))
        #expect(!WindowSpaceBehavior.floatsAboveFullScreen(alwaysOnTop: false))
        // The window STILL does not join every Space.
        #expect(WindowSpaceBehavior.doesNotJoinAllSpaces(behavior))
    }

    @Test
    func normalBehaviorIncludesParticipateInCycle() {
        let behavior = NoteWindowBridge.collectionBehavior(alwaysOnTop: false)
        #expect(behavior.contains(.moveToActiveSpace))
        #expect(behavior.contains(.participatesInCycle))
        #expect(!behavior.contains(.canJoinAllSpaces))
        #expect(!behavior.contains(.fullScreenAuxiliary))
    }
}
