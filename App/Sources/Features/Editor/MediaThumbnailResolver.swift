import SwiftUI
import Domain
import AssetStore

// MARK: - R1.4 media thumbnail render source (remediation-phase1 T016/T017)
//
// The screenshot/image blocks previously rendered a placeholder SF symbol
// and NEVER loaded the stored 256px thumbnail (FR-094a declared but not
// implemented — audit S-2). This resolver is the testable core that maps a
// block payload to its render source:
//
// - `.available(thumbnailID)`: the thumbnail asset exists — the view loads
//   it (via the injected provider or the environment asset store).
// - `.unavailable`: no thumbnail (generation failed, SC-008 — never fall
//   back to the full-resolution original) or a non-media payload — the
//   view renders the degraded placeholder.
//
// SC-008: the card grid and inline blocks NEVER decode a full-resolution
// original. The only original-consuming surface is the explicit viewer.

/// The render source for a media block's inline thumbnail frame.
public enum MediaThumbnailState: Equatable, Sendable {
    /// The thumbnail asset id to load.
    case available(UUID)
    /// No thumbnail (absent or failed) — render the degraded placeholder.
    case unavailable
}

/// Maps block payloads to their inline render source and loads thumbnail
/// bytes through an injected provider (testable without a live AssetStore).
public enum MediaThumbnailResolver {

    /// The inline render source for a block payload. Screenshot/image
    /// payloads with a thumbnail asset resolve to `.available`; anything
    /// else (no thumbnail, non-media payload) resolves to `.unavailable`.
    public static func renderState(for payload: CanonicalBlockPayload) -> MediaThumbnailState {
        switch payload {
        case .screenshot(let p):
            return p.thumbnailAssetId.map(MediaThumbnailState.available) ?? .unavailable
        case .image(let p):
            return p.thumbnailAssetId.map(MediaThumbnailState.available) ?? .unavailable
        case .richText, .todo, .code, .fileReference:
            return .unavailable
        }
    }

    /// Loads the thumbnail bytes for a render state through the injected
    /// provider. `.unavailable` never calls the provider; a provider
    /// failure degrades to nil (the placeholder), fail-closed.
    public static func loadThumbnail(
        state: MediaThumbnailState,
        provider: @Sendable (UUID) async throws -> Data?
    ) async -> Data? {
        guard case .available(let id) = state else { return nil }
        return try? await provider(id)
    }
}

// MARK: - Environment access (T017 view wiring)

/// The composed AssetStore in the SwiftUI environment, injected by
/// NoteWindowContent so media block views can load thumbnails without
/// threading a loader through every view initializer.
struct NoteAssetStoreKey: EnvironmentKey {
    static let defaultValue: AssetStore? = nil
}

public extension EnvironmentValues {
    /// The composed asset store (nil before bootstrap / in tests without
    /// assets). Media block views read thumbnails through it.
    var noteAssetStore: AssetStore? {
        get { self[NoteAssetStoreKey.self] }
        set { self[NoteAssetStoreKey.self] = newValue }
    }
}
