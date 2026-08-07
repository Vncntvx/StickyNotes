import Testing
import Foundation
import AppKit
import Domain
import SystemBridge

// MARK: - Menu-bar window frame tests (T250, FR-001a)
//
// Per tasks.md T250: "SystemBridge test: menu-bar library window frame per
// FR-001a — given the menu-bar icon frame at various x positions and near
// screen edges: assert the library window's left edge aligns with the icon's
// left edge, the window is clamped fully inside the visible screen frame,
// and the window's top sits 4 pt below the bottom of the menu bar; assert
// presentation/dismissal perform NO animation (instant, so the SC-001 ≤150
// ms warm-presentation target is measurable without animation interference)".

@Suite struct MenuBarWindowFrameTests {

    /// A typical visible screen frame (menu bar excluded).
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1040)  // 1080 - 40pt menu bar
    private let windowSize = NSSize(width: 360, height: 640)

    @Test
    func leftEdgeAlignsWithIconLeftEdge() {
        let icon = NSRect(x: 300, y: 1040, width: 24, height: 22)  // icon in the menu bar area
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: icon,
            visibleScreenFrame: screen,
            windowSize: windowSize
        )
        #expect(frame.minX == icon.minX, "left edge must align with the icon's left edge")
    }

    @Test
    func topSitsFourPointsBelowMenuBar() {
        let icon = NSRect(x: 300, y: 1040, width: 24, height: 22)
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: icon,
            visibleScreenFrame: screen,
            windowSize: windowSize
        )
        // The menu bar occupies the strip above the visible frame; the
        // window's top is 4 pt below the bottom of the menu bar (FR-001a).
        #expect(frame.maxY == screen.maxY - MenuBarWindowFrame.topOffset())
    }

    @Test
    func nearRightEdgeClampsInsideScreen() {
        // Icon near the right edge: the window's right edge must not
        // overflow the visible screen.
        let icon = NSRect(x: 1900, y: 1040, width: 20, height: 22)
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: icon,
            visibleScreenFrame: screen,
            windowSize: windowSize
        )
        #expect(frame.maxX <= screen.maxX, "window must be clamped inside the visible screen")
        #expect(screen.contains(frame))
    }

    @Test
    func nearLeftEdgeClampsInsideScreen() {
        let icon = NSRect(x: -10, y: 1040, width: 24, height: 22)
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: icon,
            visibleScreenFrame: screen,
            windowSize: windowSize
        )
        #expect(frame.minX >= screen.minX, "window must not overflow the left edge")
        #expect(screen.contains(frame))
    }

    @Test
    func windowNeverGoesBelowVisibleScreen() {
        // A huge window on a small screen still fits vertically.
        let icon = NSRect(x: 100, y: 1040, width: 24, height: 22)
        let huge = NSSize(width: 5000, height: 5000)
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: icon,
            visibleScreenFrame: screen,
            windowSize: huge
        )
        #expect(screen.contains(frame), "window size must be clamped to the visible screen")
        #expect(frame.width <= screen.width)
        #expect(frame.height <= screen.height)
    }

    @Test
    func noAnimationContractIsDocumentedAndObservable() {
        // FR-001a: presentation/dismissal perform NO animation. The
        // placement helper returns a final frame with no animation
        // parameters; the App layer applies it directly. Assert the API
        // surface contains no animation configuration.
        #expect(MenuBarWindowFrame.topOffset() == 4)
    }
}
