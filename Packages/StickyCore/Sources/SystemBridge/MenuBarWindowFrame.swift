import Foundation
import AppKit
import Domain

// MARK: - MenuBarWindowFrame (T255)
//
// Per tasks.md T255 and spec FR-001a (clarified 2026-08-07): the menu-bar
// library window is positioned with its left edge aligned with the
// menu-bar icon's left edge, clamped fully inside the visible screen frame,
// and its top 4 points below the bottom of the menu bar. Presentation/
// dismissal are instant — NO animation (so the SC-001 ≤150 ms warm-
// presentation target is measurable without animation interference).
//
// The placement math is a pure function (testable headlessly — T250
// MenuBarWindowFrameTests); the App layer applies it with `NSWindow`/
// `MenuBarExtra` window style.

/// Menu-bar library window placement (FR-001a).
public enum MenuBarWindowFrame {

    /// The gap between the bottom of the menu bar and the library window's
    /// top (FR-001a: 4 pt).
    public static let menuBarGap: CGFloat = 4

    /// Computes the library window frame for the given status-item icon
    /// frame and visible screen area.
    ///
    /// - Parameters:
    ///   - iconFrame: the status-item icon frame (screen coordinates).
    ///   - visibleScreenFrame: the visible screen frame (menu-bar-excluded).
    ///   - windowSize: the library window's desired size (falls back to a
    ///     sane default when the caller hasn't sized it yet).
    /// - Returns: a frame whose left edge aligns with the icon's left edge,
    ///   clamped fully inside the visible screen, top 4 pt below the menu
    ///   bar. Height is preserved; the frame never animates (callers apply
    ///   it directly).
    public static func libraryWindowFrame(
        iconFrame: NSRect,
        visibleScreenFrame: NSRect,
        windowSize: NSSize
    ) -> NSRect {
        let size = NSSize(
            width: min(max(windowSize.width, 100), visibleScreenFrame.width),
            height: min(max(windowSize.height, 100), visibleScreenFrame.height)
        )

        var frame = NSRect(
            x: iconFrame.minX,
            y: visibleScreenFrame.maxY - size.height - menuBarGap,
            width: size.width,
            height: size.height
        )

        // Clamp fully inside the visible screen frame (FR-001a).
        frame.origin.x = min(max(frame.origin.x, visibleScreenFrame.minX),
                             visibleScreenFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visibleScreenFrame.minY),
                             visibleScreenFrame.maxY - frame.height)
        return frame
    }

    /// The distance between the window's top edge and the bottom of the
    /// menu bar, per FR-001a (4 pt). Exposed for tests.
    public static func topOffset() -> CGFloat { menuBarGap }
}
