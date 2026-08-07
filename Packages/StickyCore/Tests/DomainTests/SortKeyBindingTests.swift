import Testing
import Foundation
import Domain

// MARK: - Sort-key binding tests (T187, FR-022a clarified 2026-08-07)
//
// Per tasks.md T187: assert VersionLineage.standardGap == 1024,
// normalizationThreshold == 64; inserting a note between two keys uses the
// midpoint; when any adjacent gap in a contiguous run falls below 64, the
// run is renormalized with 1024 gaps within a single transaction.

@Suite struct SortKeyBindingTests {

    @Test
    func standardGapIs1024() {
        #expect(ManualSortKeys.standardGap == 1024)
    }

    @Test
    func normalizationThresholdIs64() {
        #expect(ManualSortKeys.normalizationThreshold == 64)
    }

    @Test
    func initialSortKeyIsZero() {
        #expect(ManualSortKeys.initialSortKey == 0)
    }

    @Test
    func nextAfterLastKeyAddsStandardGap() {
        #expect(ManualSortKeys.next(after: nil) == 0)
        #expect(ManualSortKeys.next(after: 0) == 1024)
        #expect(ManualSortKeys.next(after: 1024) == 2048)
        #expect(ManualSortKeys.next(after: 5000) == 6024)
    }

    @Test
    func insertBetweenUsesMidpoint() {
        let mid = ManualSortKeys.insert(between: 0, and: 1024)
        #expect(mid == 512)
        let mid2 = ManualSortKeys.insert(between: 1024, and: 2048)
        #expect(mid2 == 1536)
    }

    @Test
    func insertAtBeginning() {
        let key = ManualSortKeys.insert(between: nil, and: 1024)
        #expect(key == 0) // 1024 - 1024 = 0
    }

    @Test
    func insertAtEnd() {
        let key = ManualSortKeys.insert(between: 2048, and: nil)
        #expect(key == 3072)
    }

    @Test
    func insertIntoEmptyCollection() {
        let key = ManualSortKeys.insert(between: nil, and: nil)
        #expect(key == 0)
    }

    @Test
    func needsNormalizationTriggersWhenGapBelowThreshold() {
        // The code uses `< threshold` (strictly below 64), so a gap of
        // exactly 64 does NOT trigger.
        #expect(ManualSortKeys.needsNormalization(between: 0, and: 63))
        #expect(!ManualSortKeys.needsNormalization(between: 0, and: 64))
        #expect(!ManualSortKeys.needsNormalization(between: 0, and: 65))
        #expect(!ManualSortKeys.needsNormalization(between: 0, and: 1024))
    }

    @Test
    func normalizeProducesEvenlySpaced1024Gaps() {
        // A crowded run [0, 1, 2, 3, 4] (gaps of 1, below threshold 64).
        let crowded = [0, 1, 2, 3, 4]
        let normalized = ManualSortKeys.normalize(crowded)
        #expect(normalized == [0, 1024, 2048, 3072, 4096])
    }

    @Test
    func normalizeStartsAtInitialSortKey() {
        let keys = [100, 200, 300]
        let normalized = ManualSortKeys.normalize(keys)
        #expect(normalized[0] == 0)
        #expect(normalized == [0, 1024, 2048])
    }

    @Test
    func normalizePreservesCount() {
        let keys = Array(repeating: 0, count: 10).enumerated().map { $0.offset }
        let normalized = ManualSortKeys.normalize(keys)
        #expect(normalized.count == 10)
    }

    @Test
    func midpointInsertionCanTriggerNormalization() {
        // Insert enough notes between 0 and 1024 to push the gap below 64.
        // 0, 512, 768, 896, ... — each insertion halves the gap. After ~5
        // insertions the gap drops below 64 and normalization is required.
        var keys = [0, 1024]
        for _ in 0..<5 {
            let mid = ManualSortKeys.insert(between: keys[0], and: keys[1])
            keys.insert(mid, at: 1)
        }
        // The smallest adjacent gap is now well below 64.
        let minGap = zip(keys, keys.dropFirst()).map { $1 - $0 }.min() ?? 0
        #expect(minGap < 64, "after repeated midpoint insertion, gap must drop below 64")
        #expect(ManualSortKeys.needsNormalization(between: keys[0], and: keys[1]))
    }
}
