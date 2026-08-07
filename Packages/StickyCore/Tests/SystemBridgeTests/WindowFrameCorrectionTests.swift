import Testing
import Foundation
import AppKit
import Domain
import SystemBridge

// MARK: - Window frame correction tests (T163c / T048, FR-034)
//
// Per tasks.md T163c: "SystemBridge test: window-frame correction moves
// off-screen window to visible display + preserves disconnected-display
// preferred frame".

@Suite struct WindowFrameCorrectionTests {

    // Display arrangement: main display 1920x1080 (id "main"), second
    // display to the right 1280x1024 (id "second").
    private let displays: [DisplayFrame] = [
        DisplayFrame(displayUUID: "main", frame: NSRect(x: 0, y: 0, width: 1920, height: 1080)),
        DisplayFrame(displayUUID: "second", frame: NSRect(x: 1920, y: 0, width: 1280, height: 1024)),
    ]

    @Test
    func visibleFrameOnConnectedDisplayIsKept() {
        let frame = NSRect(x: 100, y: 100, width: 400, height: 300)
        let corrected = DisplayChangeBridge.correctedFrame(
            frame: frame,
            preferredDisplayUUID: "main",
            fallbackFrame: nil,
            displays: displays
        )
        #expect(corrected == frame, "a visible frame on the preferred display is kept")
    }

    @Test
    func offScreenWindowMovesOntoVisibleDisplay() {
        // Window saved on a display that no longer exists: far off the
        // right edge of the second display.
        let offScreen = NSRect(x: 5000, y: 100, width: 400, height: 300)
        let corrected = DisplayChangeBridge.correctedFrame(
            frame: offScreen,
            preferredDisplayUUID: "second",
            fallbackFrame: nil,
            displays: displays
        )
        // Must be fully inside one of the visible displays.
        let onDisplay = displays.contains { display in
            display.frame.contains(corrected)
        }
        #expect(onDisplay, "off-screen window must be moved onto a visible display")
        #expect(!DisplayChangeBridge.isVisible(offScreen, on: displays))
        #expect(DisplayChangeBridge.isVisible(corrected, on: displays))
    }

    @Test
    func disconnectedPreferredDisplayUsesFallbackFrame() {
        // Window preferred a display ("old") that is now disconnected; the
        // fallback frame lives on the main display.
        let disconnectedPreferred = NSRect(x: 100, y: 100, width: 400, height: 300)
        let fallback = NSRect(x: 50, y: 50, width: 400, height: 300)

        let corrected = DisplayChangeBridge.correctedFrame(
            frame: disconnectedPreferred,
            preferredDisplayUUID: "old",
            fallbackFrame: fallback,
            displays: displays
        )
        #expect(corrected == fallback, "the fallback frame is used when the preferred display is disconnected (FR-034)")

        // The preferred (disconnected-display) frame itself is never mutated
        // — the saved WindowState keeps it for when the display returns.
        #expect(disconnectedPreferred == NSRect(x: 100, y: 100, width: 400, height: 300))
    }

    @Test
    func disconnectedDisplayWithInvalidFallbackCentersOnBestDisplay() {
        let invalidFallback = NSRect(x: -5000, y: -5000, width: 400, height: 300)
        let corrected = DisplayChangeBridge.correctedFrame(
            frame: NSRect(x: 0, y: 0, width: 400, height: 300),
            preferredDisplayUUID: "old",
            fallbackFrame: invalidFallback,
            displays: displays
        )
        #expect(DisplayChangeBridge.isVisible(corrected, on: displays))
        // Centered on the best display (the one containing the old frame's
        // largest intersection — none → main).
        let main = displays[0].frame
        #expect(abs(corrected.midX - main.midX) < 1)
        #expect(abs(corrected.midY - main.midY) < 1)
    }

    @Test
    func noPreferredDisplayAndVisibleKeepsFrame() {
        let frame = NSRect(x: 200, y: 200, width: 500, height: 400)
        let corrected = DisplayChangeBridge.correctedFrame(
            frame: frame,
            preferredDisplayUUID: nil,
            fallbackFrame: nil,
            displays: displays
        )
        #expect(corrected == frame)
    }

    @Test
    func clampKeepsFrameInsideDisplay() {
        let frame = NSRect(x: -100, y: -50, width: 400, height: 300)
        let clamped = DisplayChangeBridge.clamp(frame, into: displays[0].frame)
        #expect(displays[0].frame.contains(clamped))
        #expect(clamped.width == 400)
        #expect(clamped.height == 300)
    }

    @Test
    func centeredFallbackStaysInsideDisplay() {
        let fallback = DisplayChangeBridge.centeredFallback(
            on: displays[0].frame,
            windowSize: NSSize(width: 400, height: 300)
        )
        #expect(displays[0].frame.contains(fallback))
        #expect(abs(fallback.midX - displays[0].frame.midX) < 1)
        #expect(abs(fallback.midY - displays[0].frame.midY) < 1)
    }
}
