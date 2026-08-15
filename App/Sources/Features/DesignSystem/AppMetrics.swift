import SwiftUI

// MARK: - AppMetrics (003 T009, FR-080/FR-081)
//
// Per tasks.md T009 and spec FR-080/FR-081: restrained semantic spacing and
// typography tokens for cross-window consistency (Library/Note/Settings/
// Trash share one visual language). System metrics are preferred over
// inflated padding/radii; these tokens are deliberately few and small.

public enum AppMetrics {

    // MARK: Spacing

    /// Base content inset for surfaces (library content area, settings
    /// panels).
    public static let contentInset: CGFloat = 12

    /// Standard inter-control spacing within a row.
    public static let rowSpacing: CGFloat = 8    // MARK: Corner radii

    /// Standard surface corner radius (cards, panels) — restrained, macOS
    /// system-like (cards: 10 pt; note surfaces keep their 8 pt per 001).
    public static let surfaceRadius: CGFloat = 10

    // MARK: Typography
    /// Card preview / metadata size.
    public static let cardPreviewSize: CGFloat = 11
    /// Banner text size (sync attention banner).
    public static let bannerTextSize: CGFloat = 12
}
