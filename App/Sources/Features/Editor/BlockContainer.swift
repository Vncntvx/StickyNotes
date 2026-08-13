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

/// The single source for block-grid metrics (004 修复 2026-08-13; 扩展
/// 2026-08-14, P0 — the document grid's spacing ownership):
/// - the DOCUMENT VStack owns the title↔control↔blocklist rhythm
///   (`documentSpacing`);
/// - the block list owns the inter-block rhythm (`interBlockSpacing`);
/// - each block owns only its INTERIOR padding (`codeCardPadding`,
///   `todoMarkerColumnWidth` + `todoMarkerGap`).
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
    /// The document VStack spacing between the title field, the insertion
    /// control row, and the block list (004 修复 2026-08-14 — previously a
    /// bare 8 in the paper VStack).
    public static let documentSpacing: CGFloat = 8
    /// The todo marker column (gutter) width — the FIXED slot the checkbox
    /// lives in. The todo text starts at paperInset + column + gap; the
    /// interaction hit target expands INSIDE the column, so the text
    /// leading never drifts.
    public static let todoMarkerColumnWidth: CGFloat = 20
    /// The todo row's marker↔text gap (004 修复 2026-08-14 — previously a
    /// bare 8 in the todo HStack).
    public static let todoMarkerGap: CGFloat = 8
    /// The code card's interior padding — the card's OWN inner inset; the
    /// card outer edge stays on the paper's block edge.
    public static let codeCardPadding: CGFloat = 8
    /// The tail continuation region's minimum clickable height (004 修复
    /// 2026-08-14, P0) — the region grows to fill the remaining visible
    /// paper when the document is shorter than the viewport.
    public static let continuationAreaMinHeight: CGFloat = 44

    // MARK: Paper inset (FR-019 semantic insets; 004 T042)

    /// The paper horizontal inset: compact 10pt below 480pt; regular
    /// 14–16pt above; capped at 24pt. The ONLY custom width-aware rule
    /// (plan §5/§8). 10pt is the compact floor at the 320pt minimum width
    /// (DoD: a reasonable minimum inset must survive the narrowest
    /// window).
    public static func paperInset(for paperWidth: CGFloat) -> CGFloat {
        paperWidth < 480 ? 10 : min(14 + (paperWidth - 480) / 240, 24)
    }
}

/// Applies the unified block container to any block view.
public extension View {
    func blockContainer() -> some View {
        BlockContainer { self }
    }
}
