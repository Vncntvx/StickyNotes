import CoreGraphics

// MARK: - NoteCardMetrics (003 T008, FR-021/SC-021/SC-022)
//
// Per tasks.md T008 and spec FR-021/SC-021/SC-022: deterministic card-grid
// rules — minCardWidth 180, spacing 12, columns =
// max(1, floor((contentWidth+12)/192)), cardWidth =
// (contentWidth − (columns−1)×12) / columns, card height 72–128 pt.
// The formula replaces the 001 fixed 220×160 constants.

public enum NoteCardMetrics {

    /// FR-021: the minimum card width that keeps cards readable (SC-022).
    public static let minCardWidth: CGFloat = 180

    /// Inter-card spacing (unchanged from 001 FR-002a: 12 pt).
    public static let spacing: CGFloat = 12

    /// The column unit: minCardWidth + spacing (the formula's denominator).
    public static let columnUnit: CGFloat = minCardWidth + spacing

    /// FR-021: deterministic column count.
    public static func columnCount(forContentWidth contentWidth: CGFloat) -> Int {
        guard contentWidth > 0 else { return 1 }
        return max(1, Int(floor((contentWidth + spacing) / columnUnit)))
    }

    /// FR-021: the card width for a given content width — the grid width
    /// minus inter-card gaps, divided by the column count. One column =
    /// full content width.
    public static func cardWidth(forContentWidth contentWidth: CGFloat) -> CGFloat {
        let columns = columnCount(forContentWidth: contentWidth)
        return (contentWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }

    /// SC-022: card height bounds (content-driven).
    public static let minCardHeight: CGFloat = 72
    public static let maxCardHeight: CGFloat = 128
}
