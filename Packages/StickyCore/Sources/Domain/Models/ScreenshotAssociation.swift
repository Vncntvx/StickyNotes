import Foundation

// MARK: - Cover selection (T084)
//
// The invariant "at most one cover screenshot per note" is enforced
// transactionally by the DB write path AND by this value-type helper so the
// rule is testable and cannot be violated by callers that go through it.
// The `ScreenshotAssociation` entity itself lives in Models.swift
// (data-model.md §ScreenshotAssociation).

/// Enforces the "at most one cover per note" invariant over a collection of
/// associations. Mirrors the transactional behavior of the DB write path:
/// setting a cover clears any previous cover.
public enum CoverSelection {
    /// Sets `blockId` as the note's cover, clearing any other cover in the
    /// collection. Returns `true` if the collection changed.
    public static func setCover(blockId: UUID, in associations: inout [ScreenshotAssociation]) -> Bool {
        var changed = false
        for index in associations.indices {
            let isTarget = associations[index].blockId == blockId
            let wantsCover = isTarget && !associations[index].isCover
            let wantsClear = !isTarget && associations[index].isCover
            if wantsCover || wantsClear {
                associations[index].isCover = isTarget
                changed = true
            }
        }
        return changed
    }

    /// The cover block ID of a collection (nil when none is marked).
    public static func coverBlockID(in associations: [ScreenshotAssociation]) -> UUID? {
        associations.first { $0.isCover }?.blockId
    }

    /// Validates the invariant: at most one `isCover` in a collection.
    public static func validateSingleCover(_ associations: [ScreenshotAssociation]) -> Bool {
        associations.filter(\.isCover).count <= 1
    }
}
