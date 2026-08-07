import Foundation
import AppKit
import Domain

// MARK: - DisplayChangeBridge (T165)
//
// Per tasks.md T165 and spec FR-034: display connect/disconnect handling +
// frame restoration + fallback frame, preserving the disconnected-display
// preferred frame. AppKit isolated here; the frame-correction math is a pure
// function (testable headlessly — T048/T163c WindowFrameCorrectionTests).

/// A visible display's frame + identifier, in the same coordinate space as
/// the note window frames.
public struct DisplayFrame: Sendable, Equatable {
    public let displayUUID: String
    public let frame: NSRect

    public init(displayUUID: String, frame: NSRect) {
        self.displayUUID = displayUUID
        self.frame = frame
    }
}

/// Display-change handling: moves off-screen windows to a visible display
/// while preserving the disconnected-display preferred frame (FR-034).
public enum DisplayChangeBridge {

    /// How much of a window must intersect a display for it to count as
    /// "on" that display.
    public static let minimumVisibleFraction: CGFloat = 0.1

    /// The desired fallback frame when a window ends up entirely off-screen:
    /// centered on the main visible display.
    public static func centeredFallback(on displayFrame: NSRect, windowSize: NSSize) -> NSRect {
        let x = displayFrame.midX - windowSize.width / 2
        let y = displayFrame.midY - windowSize.height / 2
        return NSRect(
            x: max(displayFrame.minX, min(x, displayFrame.maxX - windowSize.width)),
            y: max(displayFrame.minY, min(y, displayFrame.maxY - windowSize.height)),
            width: windowSize.width,
            height: windowSize.height
        )
    }

    /// Whether a window frame is (substantially) visible on any of the given
    /// display frames.
    public static func isVisible(_ frame: NSRect, on displays: [DisplayFrame]) -> Bool {
        for display in displays {
            let intersection = frame.intersection(display.frame)
            let area = frame.width * frame.height
            guard area > 0 else { return false }
            let fraction = (intersection.width * intersection.height) / area
            if fraction >= minimumVisibleFraction {
                return true
            }
        }
        return false
    }

    /// The display whose frame contains the largest intersection with the
    /// window (used to pick the "current" display).
    public static func bestDisplay(for frame: NSRect, among displays: [DisplayFrame]) -> DisplayFrame? {
        displays.max { lhs, rhs in
            let l = lhs.frame.intersection(frame).width * lhs.frame.intersection(frame).height
            let r = rhs.frame.intersection(frame).width * rhs.frame.intersection(frame).height
            return l < r
        }
    }

    /// Corrects a note window frame for the current display arrangement.
    ///
    /// - Parameters:
    ///   - frame: the preferred frame (saved WindowState.frame).
    ///   - preferredDisplayUUID: the display the window prefers (may be
    ///     disconnected — FR-034).
    ///   - fallbackFrame: a frame previously saved for a disconnected
    ///     display (WindowState.fallbackFrame), used when the preferred
    ///     display is missing.
    ///   - displays: the current visible display frames.
    /// - Returns: the frame to apply now. When the preferred display is
    ///   connected and the frame is visible, the preferred frame is kept
    ///   (and the fallback frame is the one to remember). When the
    ///   preferred display is disconnected, the fallback frame is used if
    ///   visible; otherwise a centered fallback on the best display. The
    ///   disconnected-display preferred frame is never mutated.
    public static func correctedFrame(
        frame: NSRect,
        preferredDisplayUUID: String?,
        fallbackFrame: NSRect?,
        displays: [DisplayFrame]
    ) -> NSRect {
        guard !displays.isEmpty else { return frame }

        if let preferredDisplayUUID {
            let preferredConnected = displays.contains { $0.displayUUID == preferredDisplayUUID }
            if preferredConnected {
                // Preferred display is connected: keep the preferred frame
                // when it's visible; otherwise move it onto the preferred
                // display (clamped).
                if isVisible(frame, on: displays) {
                    return frame
                }
                if let display = displays.first(where: { $0.displayUUID == preferredDisplayUUID }) {
                    return clamp(frame, into: display.frame)
                }
            }
            // Preferred display disconnected (FR-034): try the fallback
            // frame; else center on the best remaining display.
            if let fallbackFrame, isVisible(fallbackFrame, on: displays) {
                return fallbackFrame
            }
        } else if isVisible(frame, on: displays) {
            return frame
        }

        let best = bestDisplay(for: frame, among: displays) ?? displays[0]
        return centeredFallback(on: best.frame, windowSize: frame.size)
    }

    /// Clamps a frame fully inside a display frame (FR-001a-style clamping
    /// for note windows).
    public static func clamp(_ frame: NSRect, into displayFrame: NSRect) -> NSRect {
        var f = frame
        f.origin.x = min(max(f.origin.x, displayFrame.minX), displayFrame.maxX - f.width)
        f.origin.y = min(max(f.origin.y, displayFrame.minY), displayFrame.maxY - f.height)
        // Size overflow safety: never exceed the display.
        if f.width > displayFrame.width {
            f.origin.x = displayFrame.minX
            f.size.width = displayFrame.width
        }
        if f.height > displayFrame.height {
            f.origin.y = displayFrame.minY
            f.size.height = displayFrame.height
        }
        return f
    }
}

// MARK: - Display observation (thin AppKit integration)

/// Observes display connect/disconnect. The App layer wires the callback to
/// re-apply corrected frames; the observation itself is passive (no AppKit
/// window manipulation here).
public enum DisplayObservation {
    /// The current display frames (in the main display's coordinate space),
    /// for frame correction. Testable via `DisplayFrame` inputs; this helper
    /// reads the live `NSScreen` list.
    @MainActor
    public static func currentDisplayFrames() -> [DisplayFrame] {
        NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            let uuid = number.map { String(describing: $0) } ?? "display-\(index)"
            return DisplayFrame(displayUUID: uuid, frame: screen.frame)
        }
    }
}
