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
public struct BlockContainer<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Applies the unified block container to any block view.
public extension View {
    func blockContainer() -> some View {
        BlockContainer { self }
    }
}
