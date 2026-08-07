import Testing
import Foundation
import Domain

// MARK: - Card todo-progress format tests (T241, FR-072b)
//
// Per tasks.md T241: the card progress string is "completed/total" (e.g.
// "12/45"); totals > 99 render as "99+ completed"; 0-completed and
// all-completed edge cases.

@Suite struct NoteCardProgressTests {
    @Test
    func completedTotalFormat() {
        #expect(TodoCardProgress.format(completed: 12, total: 45) == "12/45")
        #expect(TodoCardProgress.format(completed: 0, total: 5) == "0/5")
        #expect(TodoCardProgress.format(completed: 5, total: 5) == "5/5")
    }

    @Test
    func ninetyNinePlusRule() {
        #expect(TodoCardProgress.format(completed: 99, total: 100) == "99+ completed")
        #expect(TodoCardProgress.format(completed: 500, total: 1000) == "99+ completed")
        #expect(TodoCardProgress.format(completed: 99, total: 99) == "99/99",
                "totals ≤ 99 keep the completed/total form")
    }

    @Test
    func noTodosYieldsNil() {
        #expect(TodoCardProgress.format(completed: 0, total: 0) == nil)
    }
}
