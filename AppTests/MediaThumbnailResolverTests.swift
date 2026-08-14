import Testing
import Foundation
import Domain
@testable import StickyNotes

// MARK: - R1.4 media thumbnail render state (remediation-phase1 T016)
//
// The screenshot/image blocks previously rendered a placeholder SF symbol
// and NEVER loaded the stored 256px thumbnail (FR-094a declared but not
// implemented — audit S-2). The resolver below is the testable core that
// maps a block payload to its render source: the thumbnail when present
// (SC-008 — never the full-resolution original), a degraded placeholder
// when the thumbnail is absent or fails to load.

@Suite struct MediaThumbnailResolverTests {

    @Test
    func screenshotPayloadWithThumbnailResolvesAvailable() {
        let thumbID = UUID()
        let payload = ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: thumbID, capturedAt: Date())
        #expect(MediaThumbnailResolver.renderState(for: .screenshot(payload)) == .available(thumbID))
    }

    @Test
    func screenshotPayloadWithoutThumbnailIsUnavailable() {
        let payload = ScreenshotPayload(originalAssetId: UUID(), thumbnailAssetId: nil, capturedAt: Date())
        #expect(MediaThumbnailResolver.renderState(for: .screenshot(payload)) == .unavailable)
    }

    @Test
    func imagePayloadWithThumbnailResolvesAvailable() {
        let thumbID = UUID()
        let payload = EmbeddedImagePayload(originalAssetId: UUID(), thumbnailAssetId: thumbID)
        #expect(MediaThumbnailResolver.renderState(for: .image(payload)) == .available(thumbID))
    }

    @Test
    func nonMediaPayloadIsUnavailable() {
        #expect(MediaThumbnailResolver.renderState(for: .richText(.plain("text"))) == .unavailable)
    }

    @Test
    func loadThumbnailFetchesThroughProvider() async {
        let data = await MediaThumbnailResolver.loadThumbnail(
            state: .available(UUID()),
            provider: { _ in Data("png-bytes".utf8) }
        )
        #expect(data == Data("png-bytes".utf8))
    }

    @Test
    func loadThumbnailReturnsNilForUnavailable() async {
        let data = await MediaThumbnailResolver.loadThumbnail(
            state: .unavailable,
            provider: { _ in Data("png-bytes".utf8) }
        )
        #expect(data == nil)
    }

    @Test
    func loadThumbnailFailsClosedOnProviderError() async {
        let data = await MediaThumbnailResolver.loadThumbnail(
            state: .available(UUID()),
            provider: { _ in throw StickyError.assetStorage(.writeFailed) }
        )
        #expect(data == nil, "a failed thumbnail load degrades to the placeholder, never crashes")
    }
}
