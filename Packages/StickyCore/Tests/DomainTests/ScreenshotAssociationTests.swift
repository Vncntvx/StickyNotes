import Testing
import Foundation
import Domain

// MARK: - ScreenshotAssociation / cover selection tests (T084)
//
// Per tasks.md T084: "at most one cover screenshot per note (transactional);
// multiple screenshots allowed".

@Suite struct ScreenshotAssociationTests {

    private func association(blockId: UUID = UUID(), isCover: Bool = false) -> ScreenshotAssociation {
        ScreenshotAssociation(
            blockId: blockId,
            noteId: UUID(),
            originalAssetId: UUID(),
            thumbnailAssetId: UUID(),
            capturedAt: Date(),
            isCover: isCover
        )
    }

    @Test
    func settingCoverClearsPreviousCover() {
        let a = association(blockId: UUID(), isCover: true)
        let b = association(blockId: UUID())
        var associations = [a, b]

        // b becomes the cover → a must lose it (transactional swap).
        let changed = CoverSelection.setCover(blockId: b.blockId, in: &associations)

        #expect(changed)
        #expect(CoverSelection.validateSingleCover(associations))
        #expect(CoverSelection.coverBlockID(in: associations) == b.blockId)
        #expect(associations.first { $0.blockId == a.blockId }?.isCover == false)
        #expect(associations.first { $0.blockId == b.blockId }?.isCover == true)
    }

    @Test
    func multipleScreenshotsAllowedWithOneCover() {
        var associations = (0..<5).map { _ in association() }
        let target = associations[2].blockId

        _ = CoverSelection.setCover(blockId: target, in: &associations)

        // Five screenshot associations, exactly one cover.
        #expect(associations.count == 5)
        #expect(CoverSelection.validateSingleCover(associations))
        #expect(CoverSelection.coverBlockID(in: associations) == target)
    }

    @Test
    func reSettingSameCoverIsIdempotent() {
        let blockId = UUID()
        var associations = [association(blockId: blockId, isCover: true), association()]

        let changedAgain = CoverSelection.setCover(blockId: blockId, in: &associations)

        #expect(!changedAgain, "re-setting the same cover must not report a change")
        #expect(CoverSelection.validateSingleCover(associations))
    }

    @Test
    func clearingCoverByChoosingAnotherIsOnlyChange() {
        let a = association(blockId: UUID(), isCover: true)
        let b = association(blockId: UUID())
        var associations = [a, b]

        _ = CoverSelection.setCover(blockId: b.blockId, in: &associations)

        #expect(associations[0].isCover == false)
        #expect(associations[1].isCover == true)
        // Caption/date metadata untouched by cover selection.
        #expect(associations[0].capturedAt == a.capturedAt)
    }
}
