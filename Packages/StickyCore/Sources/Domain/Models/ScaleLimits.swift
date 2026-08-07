import Foundation

// MARK: - ScaleLimits (T236, FR-090b)
//
// Per tasks.md T236 and spec FR-090b (clarified 2026-08-07):
// - A single asset (pasted image or screenshot original) is capped at
//   50 MB raw bytes and 16,384 px on the longest edge after capture/paste
//   normalization.
// - A single note's structured content (canonical envelope before asset
//   payloads) is capped at 5 MB.
// Oversize insertions are rejected with a localized explanation and no
// partial write; oversize content changes are refused while preserving the
// last valid saved state. Enforced at the asset-store and persistence
// boundaries (T236); covered by T227 ScaleLimitTests.

/// FR-090b scale-limit constants. Documented, language-neutral, covered by
/// tests (constitution XI/IV).
public enum ScaleLimits {
    /// Max raw bytes for a single asset (original or thumbnail).
    public static let maxAssetBytes = 50 * 1024 * 1024

    /// Max pixel dimension on the longest edge for a single asset image.
    public static let maxAssetLongestEdge = 16_384

    /// Max bytes for a single note's structured content (canonical envelope
    /// before asset payloads).
    public static let maxNoteContentBytes = 5 * 1024 * 1024

    /// Validates asset byte size; returns nil when within limits.
    public static func assetBytesError(byteCount: Int) -> String? {
        guard byteCount <= maxAssetBytes else {
            return "asset.tooLarge.50MB"
        }
        return nil
    }

    /// Validates an image's longest edge in pixels; returns nil when within
    /// limits.
    public static func assetLongestEdgeError(longestEdge: Int) -> String? {
        guard longestEdge <= maxAssetLongestEdge else {
            return "asset.tooLarge.16384px"
        }
        return nil
    }

    /// Validates note structured content size; returns nil when within
    /// limits.
    public static func noteContentError(byteCount: Int) -> String? {
        guard byteCount <= maxNoteContentBytes else {
            return "note.tooLarge.5MB"
        }
        return nil
    }
}
