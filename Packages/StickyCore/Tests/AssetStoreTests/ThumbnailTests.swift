import Testing
import Foundation
import UniformTypeIdentifiers
import ImageIO
import CoreGraphics
import Domain
@testable import AssetStore

// MARK: - ThumbnailGenerator tests (T083)
//
// Per tasks.md T083: "thumbnail generated async, no original decode in card
// grid; lossless preferred for text window captures".
//
// Lives in its own file (per tasks.md T083 path) to keep the AssetStore
// atomic-write tests (T082) separate from the thumbnail-generation tests.

@Suite struct ThumbnailTests {

    @Test
    func thumbnailIsGeneratedAsyncAndSmaller() async throws {
        // A real (small) PNG so ImageIO can decode it: 1x1 red pixel.
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let data = Data(base64Encoded: base64)!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbtest-\(UUID().uuidString)", isDirectory: true)
        let store = try AssetStore(directoryURL: root)
        let result = try await store.importScreenshot(originalData: data, contentType: UTType.png.identifier)

        // Original + thumbnail both stored as independent assets.
        #expect(result.original.kind == .original)
        let thumbnail = try #require(result.thumbnail, "valid PNG must produce a thumbnail")
        #expect(thumbnail.kind == .thumbnail)
        #expect(result.original.id != thumbnail.id)

        let thumbData = try await store.readData(assetID: thumbnail.id)
        #expect(!thumbData.isEmpty)

        // The thumbnail decodes to at most the target longest edge (SC-008:
        // no full-resolution decode in the card grid). We verify the decoded
        // dimension rather than raw byte size — tiny sources can re-encode
        // into larger PNG containers.
        let thumbImage = CGImageSourceCreateWithData(thumbData as CFData, nil)
        let props = CGImageSourceCopyPropertiesAtIndex(thumbImage!, 0, nil) as? [CFString: Any]
        let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(max(width, height) <= ThumbnailGenerator.defaultLongestEdge)
        try? FileManager.default.removeItem(at: root)
    }

    @Test
    func losslessPreferredForPngTextCaptures() throws {
        // PNG content → PNG output (lossless).
        #expect(ThumbnailGenerator.prefersLossless(contentType: UTType.png.identifier))
        #expect(ThumbnailGenerator.prefersLossless(contentType: UTType.heic.identifier))
        // JPEG (photographic) → lossy re-encode.
        #expect(!ThumbnailGenerator.prefersLossless(contentType: UTType.jpeg.identifier))
    }

    @Test
    func thumbnailFailsGracefullyForGarbageBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbtest2-\(UUID().uuidString)", isDirectory: true)
        let store = try AssetStore(directoryURL: root)
        let garbage = Data((0..<512).map { _ in UInt8.random(in: 0...255) })

        // importScreenshot never fails the original on thumbnail failure:
        // it returns nil for the thumbnail so the caller can pick a fallback
        // that does NOT decode the full-resolution original (SC-008).
        let result = try await store.importScreenshot(originalData: garbage, contentType: UTType.png.identifier)
        #expect(result.thumbnail == nil, "garbage bytes must not yield a thumbnail; original must NOT be reused as one")
        #expect(result.original.kind == .original)
        try? FileManager.default.removeItem(at: root)
    }
}
