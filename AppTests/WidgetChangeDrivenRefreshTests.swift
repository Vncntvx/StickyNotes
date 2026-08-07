import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - Widget change-driven refresh tests (T228, FR-110a)
//
// Covered in AppLogicTests.widgetRefreshTargetsAffectedKindsOnly. The widget
// process contains NO fixed-interval polling timer (no Timer/repeating
// refresh scheduling in WidgetExtension — timeline policies are
// `.after(15 min)` refresh-soon hints driven by change reloads).
// File exists for task→file traceability.

@Suite struct WidgetChangeDrivenRefreshTests {
    @Test
    func affectedKindsOnly() {
        let noteKinds = WidgetRefreshCoordinator.kindsAffectedByNoteChange()
        #expect(noteKinds.contains(.smallRecent))
        let todoKinds = WidgetRefreshCoordinator.kindsAffectedByTodoToggle()
        #expect(todoKinds.contains(.mediumTodo))
        let eligibility = WidgetRefreshCoordinator.kindsAffectedByEligibilityChange()
        #expect(eligibility.contains(.smallSelected))
    }
}
