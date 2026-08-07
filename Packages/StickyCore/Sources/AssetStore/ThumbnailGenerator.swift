import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Domain

// MARK: - ThumbnailGenerator (T088)
//
// Per tasks.md T088 and plan §Asset storage:
//
// - Thumbnails are generated async, sized by longest edge for the card
//   grid / widgets (SC-008: the card grid NEVER decodes a full-resolution
//   original).
// - Lossless is preferred for text-heavy window captures (screenshots of
//   text must stay crisp): PNG sources stay PNG; photographic content is
//   re-encoded to JPEG.
// - Originals, thumbnails, and app icons are stored independently
//   (`AssetKind`); a thumbnail failure must never break the original.

public enum ThumbnailGenerator {

    /// Default longest-edge size for card-grid thumbnails (points).
    ///
    /// Per FR-094a (clarified 2026-08-07): the single canonical thumbnail
    /// size for card-grid and widget display is 256px on the longest edge.
    /// Full-resolution screenshots and embedded images are NEVER decoded
    /// for card-grid or widget rendering (SC-008).
    public static let defaultLongestEdge = 256

    /// Whether a content type is "text-heavy" and should keep a lossless
    /// thumbnail. PNG (the ScreenshotKit default for window captures) and
    /// HEIC are lossless; JPEG is photographic.
    public static func prefersLossless(contentType: String) -> Bool {
        guard let type = UTType(contentType) else { return false }
        return type.conforms(to: .png) || type.conforms(to: .heic)
    }

    /// Generates a thumbnail from the original's bytes without ever loading
    /// a full-resolution image into memory: ImageIO's
    /// `CGImageSourceCreateThumbnailAtIndex` decodes at most the target
    /// pixel size (SC-008).
    ///
    /// - Parameters:
    ///   - data: The original asset bytes.
    ///   - contentType: The original's content type (drives lossless choice).
    ///   - longestEdge: Target longest edge in pixels.
    /// - Returns: Re-encoded thumbnail data (PNG for lossless sources,
    ///   JPEG otherwise).
    public static func generateThumbnail(
        from data: Data,
        contentType: String,
        longestEdge: Int = ThumbnailGenerator.defaultLongestEdge
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AssetStoreError.writeFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: longestEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AssetStoreError.writeFailed
        }

        let lossless = prefersLossless(contentType: contentType)
        let outputUTI = lossless ? UTType.png.identifier : UTType.jpeg.identifier

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, outputUTI as CFString, 1, nil) else {
            throw AssetStoreError.writeFailed
        }
        let encodeOptions: [CFString: Any] = lossless
            ? [:]  // PNG: lossless by construction
            : [kCGImageDestinationLossyCompressionQuality: 0.8]
        CGImageDestinationAddImage(destination, thumbnail, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw AssetStoreError.writeFailed
        }
        return data as Data
    }

    /// Generates a thumbnail for an app-icon snapshot (smallest; always
    /// lossless for crisp icons).
    public static func generateAppIcon(from data: Data, contentType: String, longestEdge: Int = 128) throws -> Data {
        try generateThumbnail(from: data, contentType: contentType, longestEdge: longestEdge)
    }
}
