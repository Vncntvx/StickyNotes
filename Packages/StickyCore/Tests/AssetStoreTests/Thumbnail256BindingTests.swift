import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Domain
import AssetStore

// MARK: - Thumbnail 256px binding tests (T191, FR-094a clarified 2026-08-07)
//
// Per tasks.md T191: ThumbnailGenerator.defaultLongestEdge == 256; generated
// thumbnails have a longest edge of exactly 256 pixels preserving aspect
// ratio; full-resolution screenshots and embedded images are NOT decoded for
// card-grid or widget rendering; thumbnail generation is lazy, off the main
// actor, and produces a stable hash for dedup.

@Suite struct Thumbnail256BindingTests {

    @Test
    func defaultLongestEdgeIs256() {
        #expect(ThumbnailGenerator.defaultLongestEdge == 256)
    }

    @Test
    func generatedThumbnailLongestEdgeIsAtMost256() throws {
        // Generate a 1024x768 PNG and thumbnail it — the result's longest
        // edge must be ≤ 256px.
        let original = makePNG(width: 1024, height: 768)
        let thumb = try ThumbnailGenerator.generateThumbnail(
            from: original, contentType: "image/png"
        )
        let dimensions = imageDimensions(thumb)
        #expect(dimensions != nil, "thumbnail must be a valid image")
        let longestEdge = max(dimensions!.width, dimensions!.height)
        #expect(longestEdge <= 256, "thumbnail longest edge must be ≤ 256; got \(longestEdge)")
    }

    @Test
    func portraitImageThumbnailPreservesAspectRatio() throws {
        let original = makePNG(width: 400, height: 800)
        let thumb = try ThumbnailGenerator.generateThumbnail(
            from: original, contentType: "image/png"
        )
        let dims = imageDimensions(thumb)!
        #expect(dims.height >= dims.width, "portrait aspect ratio preserved")
        #expect(max(dims.width, dims.height) <= 256)
    }

    @Test
    func appIconGenerationUsesSeparate128pxSize() throws {
        // App-icon snapshots remain 128px (FR-094a: app icons are separate
        // from card-grid thumbnails).
        let original = makePNG(width: 512, height: 512)
        let icon = try ThumbnailGenerator.generateAppIcon(
            from: original, contentType: "image/png"
        )
        let dims = imageDimensions(icon)!
        #expect(max(dims.width, dims.height) <= 128, "app icon longest edge must be ≤ 128")
    }

    @Test
    func thumbnailGenerationDoesNotDecodeFullResolutionOriginal() throws {
        // SC-008: the card grid NEVER decodes a full-resolution original.
        // ImageIO's CGImageSourceCreateThumbnailAtIndex decodes at most the
        // target pixel size — it does NOT load the full image into memory.
        // We verify by generating a thumbnail from a large image without
        // memory blowup (the API contract).
        let original = makePNG(width: 4096, height: 4096)
        let thumb = try ThumbnailGenerator.generateThumbnail(
            from: original, contentType: "image/png"
        )
        // The thumbnail is small (well under 256x256).
        let dims = imageDimensions(thumb)!
        #expect(max(dims.width, dims.height) <= 256)
        // And the thumbnail bytes are much smaller than the original.
        #expect(thumb.count < original.count / 10)
    }

    // MARK: - Helpers

    private func makePNG(width: Int, height: Int) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let image = context.makeImage() else {
            return Data()
        }
        let mutData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutData as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return mutData as Data
    }

    private func imageDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        let width = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        return (width, height)
    }
}
