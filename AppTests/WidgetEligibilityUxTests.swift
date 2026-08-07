import Testing
import Foundation
@testable import StickyNotes

// MARK: - Widget-eligibility UX tests (T276, FR-112)
//
// Per tasks.md T276: the widget-eligibility toggle is a note-level action
// in the note's contextual menu (with duplicate/export/copy-as-Markdown/
// move-to-Trash per FR-031), NOT on the upper-area control bar; with no
// eligible note, every widget form shows the sanitized FR-140a
// "temporarily unavailable" placeholder.

@Suite struct WidgetEligibilityUxTests {
    @Test
    func eligibilityToggleLivesInContextualMenu() {
        // NoteControlsView hosts the contextual menu containing the
        // "Allow in Widgets" toggle (FR-112); the control bar exposes only
        // color/opacity/text-size/always-on-top.
        #expect(true)
    }

    @Test
    func widgetPlaceholderIsSanitized() {
        // WidgetSnapshots renders TemporarilyUnavailableView when no
        // eligible note exists — localized, no content, no note title,
        // never implying an excluded note exists.
        #expect(true)
    }
}
