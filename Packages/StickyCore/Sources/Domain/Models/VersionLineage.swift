import Foundation

// MARK: - Version lineage + sort-key normalization (T013)
//
// Per data-model.md §Version lineage and §Conventions. Every synced mutation
// assigns a new `versionId` and sets `parentVersionId` to the prior
// `versionId`. Divergence = local and remote `versionId` differ but share a
// common ancestor in `parentVersionId` lineage (or one side's parent is the
// other's id).
//
// Conflict-copy dedup key: `(originalNoteId, localVersionId, remoteVersionId)`
// (plan §Conflict model; research.md R18).

/// Per-mutation version lineage for a synced entity.
///
/// `Sendable` value type (constitution IV — explicit, durable, versioned data).
public struct VersionLineage: Sendable, Codable, Equatable, Hashable {
    /// Per-mutation version UUID. New on every synced mutation.
    public let versionId: UUID

    /// Previous version UUID; nil for the initial version.
    public let parentVersionId: UUID?

    /// The device that made this mutation.
    public let lastModifiedDeviceId: UUID

    /// When the mutation happened (UTC ISO 8601).
    public let modifiedAt: Date

    public init(
        versionId: UUID,
        parentVersionId: UUID?,
        lastModifiedDeviceId: UUID,
        modifiedAt: Date
    ) {
        self.versionId = versionId
        self.parentVersionId = parentVersionId
        self.lastModifiedDeviceId = lastModifiedDeviceId
        self.modifiedAt = modifiedAt
    }

    /// Initial lineage for a brand-new entity.
    public static func initial(deviceId: UUID, at date: Date = Date()) -> VersionLineage {
        VersionLineage(
            versionId: UUID(),
            parentVersionId: nil,
            lastModifiedDeviceId: deviceId,
            modifiedAt: date
        )
    }

    /// Next lineage after a mutation on the given device.
    public func next(deviceId: UUID, at date: Date = Date()) -> VersionLineage {
        // If the device differs from the last modifier, the parent is still
        // our versionId — divergence detection compares lineages, not device
        // ids (plan §Conflict model).
        VersionLineage(
            versionId: UUID(),
            parentVersionId: versionId,
            lastModifiedDeviceId: deviceId,
            modifiedAt: date
        )
    }
}

// MARK: - Conflict-copy dedup key
//
// Per plan §Conflict model and research.md R18: once a conflict copy is
// created for a given (originalNoteId, localVersionId, remoteVersionId)
// triple, retrying the same reconciliation reuses the existing conflict copy
// instead of making another. This prevents unbounded duplicates on retry.

/// Deterministic dedup key for a conflict copy. Retry of the same
/// reconciliation MUST reuse the existing conflict copy (constitution VIII).
public struct ConflictDedupKey: Sendable, Codable, Equatable, Hashable {
    public let originalNoteId: UUID
    public let localVersionId: UUID
    public let remoteVersionId: UUID

    public init(originalNoteId: UUID, localVersionId: UUID, remoteVersionId: UUID) {
        self.originalNoteId = originalNoteId
        self.localVersionId = localVersionId
        self.remoteVersionId = remoteVersionId
    }
}

// MARK: - Sort-key normalization (1024-gap)
//
// Per data-model.md §Conventions: ordered integers with a 1024 gap
// (e.g., 0, 1024, 2048) so a drag usually changes only the moved row.
// Normalization: when the gap between two neighbors drops below a threshold
// (e.g., < 64), renumber the contiguous run by 1024 steps within a single
// transaction.

public enum ManualSortKeys {
    /// The gap between adjacent sort keys under normal conditions.
    public static let standardGap: Int = 1024

    /// Below this gap, a normalization pass is triggered.
    public static let normalizationThreshold: Int = 64

    /// The initial sort key for the first item in a fresh collection.
    public static let initialSortKey: Int = 0

    /// Returns a sort key for a new item appended after the given last key.
    /// - Parameter lastSortKey: The current last sort key, or `nil` for the
    ///   first item.
    /// - Returns: The next sort key, `lastSortKey + standardGap`.
    public static func next(after lastSortKey: Int?) -> Int {
        (lastSortKey ?? initialSortKey - standardGap) + standardGap
    }

    /// Returns a sort key for an item inserted between two existing keys.
    /// If the gap between `before` and `after` is too small to support a
    /// clean midpoint, the caller MUST trigger a normalization pass on the
    /// contiguous run (see `needsNormalization`).
    public static func insert(between before: Int?, and after: Int?) -> Int {
        switch (before, after) {
        case (nil, nil):
            return initialSortKey
        case (nil, let after?):
            return after - standardGap
        case (let before?, nil):
            return before + standardGap
        case (let before?, let after?):
            precondition(before < after, "Sort keys out of order: \(before) >= \(after)")
            return (before + after) / 2
        }
    }

    /// Returns `true` if the gap between two adjacent sort keys is small
    /// enough to require a normalization pass.
    public static func needsNormalization(between a: Int, and b: Int) -> Bool {
        abs(b - a) < normalizationThreshold
    }

    /// Renormalizes a sorted list of sort keys so adjacent items are spaced
    /// by `standardGap`, starting at `initialSortKey`. Used when a drag would
    /// otherwise leave too-small gaps.
    ///
    /// - Parameter sortedKeys: The current sort keys in their desired order.
    /// - Returns: A new array of evenly-spaced sort keys, one per input.
    public static func normalize(_ sortedKeys: [Int]) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(sortedKeys.count)
        var current = initialSortKey
        for _ in sortedKeys {
            result.append(current)
            current += standardGap
        }
        return result
    }
}
