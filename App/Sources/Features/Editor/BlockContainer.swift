import SwiftUI
import Domain

// MARK: - BlockContainer (T271, FR-050b)
//
// Per tasks.md T271 and spec FR-050b (clarified 2026-08-07): ONE unified
// block container style consistent with the note-window aesthetic (FR-030a
// corner-radius family; NO per-block borders or backgrounds by default;
// consistent vertical spacing). Category distinction comes ONLY from
// inherent affordances (todo checkbox, monospaced code font, compact file
// card, framed media). No per-category pixel values beyond the affordances.

/// The unified block container (FR-050b).
///
/// 004 修复 (2026-08-13): the container owns NO spacing of its own. The
/// block list's stack spacing is the single inter-block rhythm source, and
/// blocks align to the paper's body-text left edge (the paper inset feeds
/// every block — the container adds no horizontal inset on top). Block
/// components keep only their OWN interior padding (e.g. the code card's
/// rounded-rect padding).
public struct BlockContainer<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, BlockLayoutMetrics.horizontalInset)
            .padding(.vertical, BlockLayoutMetrics.blockVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The single source for block-grid metrics (004 修复 2026-08-13).
public enum BlockLayoutMetrics {
    /// Horizontal inset added by the block container — 0: blocks align to
    /// the paper's body-text edge (the paper inset feeds every block).
    public static let horizontalInset: CGFloat = 0
    /// Vertical padding owned by the block container — 0: the inter-block
    /// rhythm lives on the block list's stack spacing alone.
    public static let blockVerticalPadding: CGFloat = 0
    /// The inter-block rhythm — owned by the block list (LazyVStack
    /// spacing), never by per-block padding.
    public static let interBlockSpacing: CGFloat = 10
}

/// Applies the unified block container to any block view.
public extension View {
    func blockContainer() -> some View {
        BlockContainer { self }
    }
}
