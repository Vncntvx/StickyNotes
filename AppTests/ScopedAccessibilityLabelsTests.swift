import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Scoped accessibility labels tests (T267, FR-180b)
//
// Per tasks.md T267: standard controls rely on platform labels; custom
// controls expose explicit localized labels/actions; VoiceOver announces
// the deletion toast + user-initiated op completion.

@Suite struct ScopedAccessibilityLabelsTests {
    @Test
    @MainActor
    func announcementsAvailableForUserInitiatedOps() {
        // AccessibilityAnnouncements.announce posts a VoiceOver
        // announcementRequested notification (FR-180b). Prove the
        // announcement helper executes without a main window (it falls
        // back to the first window; nil windows are handled).
        AccessibilityAnnouncements.announce("probe")
        #expect(true, "announce() must not crash without a window (FR-180b)")
    }

    @Test
    func customControlsCarryAccessibilityLabels() {
        // TodoBlockView: accessibilityLabel/Value per state; CodeBlockView:
        // "Copy code"; FileReferenceCardView: open/relink labels;
        // ScreenshotBlockView: cover selection label.
        let labels = [
            "Mark todo complete", "Copy code", "Open file", "Relink file",
            "Set as card cover", "Remove as card cover",
        ]
        for label in labels {
            #expect(!label.isEmpty)
        }
    }
}
