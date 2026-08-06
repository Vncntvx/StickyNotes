import Testing
import Foundation
@testable import Domain

// MARK: - Version lineage + sort-key tests (T013)
//
// Per tasks.md T013 and data-model.md §Conventions:
// - Version lineage: versionId, parentVersionId, lastModifiedDeviceId, modifiedAt.
// - Sort keys: 1024-gap; normalize contiguous runs when gap < threshold.
// - Conflict dedup key: (originalNoteId, localVersionId, remoteVersionId).

@Suite struct VersionLineageTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!
    private static let otherDeviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000002")!

    @Test
    func initialLineageHasNoParent() {
        let lineage = VersionLineage.initial(deviceId: Self.deviceId)
        #expect(lineage.parentVersionId == nil)
        #expect(lineage.versionId != UUID())
        #expect(lineage.lastModifiedDeviceId == Self.deviceId)
    }

    @Test
    func nextLineageChainsParent() {
        let v0 = VersionLineage.initial(deviceId: Self.deviceId)
        let v1 = v0.next(deviceId: Self.deviceId)
        #expect(v1.parentVersionId == v0.versionId)
        #expect(v1.versionId != v0.versionId)
    }

    @Test
    func conflictDedupKeyIsDeterministic() {
        let originalNoteId = UUID()
        let localVersionId = UUID()
        let remoteVersionId = UUID()

        let key1 = ConflictDedupKey(
            originalNoteId: originalNoteId,
            localVersionId: localVersionId,
            remoteVersionId: remoteVersionId
        )
        let key2 = ConflictDedupKey(
            originalNoteId: originalNoteId,
            localVersionId: localVersionId,
            remoteVersionId: remoteVersionId
        )

        #expect(key1 == key2)
        #expect(key1.hashValue == key2.hashValue)

        // A different remote version yields a different key (no false dedup).
        let key3 = ConflictDedupKey(
            originalNoteId: originalNoteId,
            localVersionId: localVersionId,
            remoteVersionId: UUID()
        )
        #expect(key1 != key3)
    }
}

@Suite struct ManualSortKeyTests {

    @Test
    func nextAppendsWithStandardGap() {
        #expect(ManualSortKeys.next(after: nil) == 0)
        #expect(ManualSortKeys.next(after: 0) == 1024)
        #expect(ManualSortKeys.next(after: 1024) == 2048)
    }

    @Test
    func insertBetweenMidpoints() {
        let mid = ManualSortKeys.insert(between: 0, and: 1024)
        #expect(mid == 512)
    }

    @Test
    func insertBeforeFirst() {
        let before = ManualSortKeys.insert(between: nil, and: 0)
        #expect(before == -1024)
    }

    @Test
    func insertAfterLast() {
        let after = ManualSortKeys.insert(between: 1024, and: nil)
        #expect(after == 2048)
    }

    @Test
    func needsNormalizationTriggersBelowThreshold() {
        #expect(ManualSortKeys.needsNormalization(between: 0, and: 32))
        #expect(ManualSortKeys.needsNormalization(between: 100, and: 150))
        #expect(!ManualSortKeys.needsNormalization(between: 0, and: 1024))
        #expect(!ManualSortKeys.needsNormalization(between: 0, and: 64))
    }

    @Test
    func normalizeRenumbersByStandardGap() {
        let cramped = [0, 32, 64, 96, 128]  // gaps too small
        let normalized = ManualSortKeys.normalize(cramped)
        #expect(normalized == [0, 1024, 2048, 3072, 4096])
    }

    @Test
    func normalizeEmptyListIsEmpty() {
        #expect(ManualSortKeys.normalize([]) == [])
    }

    @Test
    func normalizeSingleItemListIsZero() {
        #expect(ManualSortKeys.normalize([42]) == [0])
    }
}
