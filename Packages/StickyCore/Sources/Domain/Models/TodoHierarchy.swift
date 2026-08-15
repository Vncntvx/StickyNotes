import Foundation

// MARK: - TodoHierarchy (T056/T189, data-model.md §TodoItem)
//
// Pure-Domain todo hierarchy validation rules. These are the SINGLE source
// of truth for the depth bound and cycle detection (R3.5, remediation
// roadmap 2026-08-15, A-5): previously the test target carried one copy
// (`TodoHierarchy` in TodoRepositoryTests) and Persistence carried a
// private constant + SQL-walking duplicate — the tests validated the copy,
// not the production rule.

public enum TodoHierarchy {
    /// Maximum nesting depth (data-model.md §TodoItem: "depth ≤ maxDepth,
    /// e.g. ≤ 6").
    public static let maxDepth = 6

    /// Returns `true` if making `candidateParent` the parent of `child`
    /// would create a cycle, given the existing `parentOf` map (todoId →
    /// its current parent todoId).
    public static func wouldCreateCycle(
        child: UUID,
        candidateParent: UUID,
        parentOf: [UUID: UUID?]
    ) -> Bool {
        // A todo cannot be its own ancestor. Walk up the candidate's chain.
        var current: UUID? = candidateParent
        var steps = 0
        while let id = current {
            if id == child { return true }
            current = parentOf[id] ?? nil
            steps += 1
            if steps > 1024 { return true }  // defensive against corrupt chains
        }
        return false
    }

    /// Returns the depth of `newParentId` + 1 (the depth a reparented child
    /// would take), or 0 when there is no parent.
    public static func depth(ofParent parentId: UUID?, parentDepthProvider: (UUID) -> Int?) -> Int {
        guard let parentId, let parentDepth = parentDepthProvider(parentId) else { return 0 }
        return parentDepth + 1
    }
}
