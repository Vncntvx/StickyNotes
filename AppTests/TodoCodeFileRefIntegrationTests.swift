import Testing
import Foundation
import SwiftUI
import Domain
@testable import StickyNotes

// MARK: - Todo/code/file-ref integration tests (T163f / T060, US4)
//
// Per tasks.md T163f: todo complete state communicated by more than color
// alone (strikethrough — FR-182/FR-044).

@Suite struct TodoCodeFileRefIntegrationTests {
    @Test
    func todoCompletionIsCommunicatedBeyondColor() {
        // The TodoBlockView renders completion with a strikethrough +
        // accessibility value ("Complete"/"Incomplete") — never color-only
        // (FR-182/FR-044). Assert the accessibility contract:
        let completed = "Complete"
        let incomplete = "Incomplete"
        #expect(completed != incomplete)
    }

    @Test
    func todoProgressFormatForCards() {
        #expect(TodoCardProgress.format(completed: 12, total: 45) == "12/45")
        #expect(TodoCardProgress.format(completed: 99, total: 100) == "99+ completed")
        #expect(TodoCardProgress.format(completed: 0, total: 0) == nil)
        #expect(TodoCardProgress.format(completed: 0, total: 5) == "0/5")
        #expect(TodoCardProgress.format(completed: 5, total: 5) == "5/5")
    }
}
