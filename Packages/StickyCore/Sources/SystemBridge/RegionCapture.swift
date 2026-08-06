import Foundation
import ScreenCaptureKit
import AppKit
import Domain

// MARK: - RegionCapture (T090)
//
// Per tasks.md T090 and plan §Screenshot capture:
//
// - Single-frame capture + a lightweight transparent multi-display
//   selection overlay (drawn by the App layer over a borderless window).
// - Handles Retina, multi-display, rotated displays, and coordinate
//   conversion between screen/overlay/capture spaces.
// - Cancels cleanly WITHOUT creating a note/asset (regionSelectionCanceled
//   is a normal, non-error outcome).
//
// The overlay UI itself is App-owned; this file owns the geometry + capture
// logic so it is testable without a GUI.

/// Region selection geometry + single-frame capture.
public enum RegionCapture {

    /// Converts an AppKit drag (bottom-left origin, screen coordinates) into
    /// a ScreenCaptureKit capture rect (top-left origin, main-display based).
    ///
    /// - Parameters:
    ///   - start: Drag start in AppKit screen coordinates (bottom-left
    ///     origin; `NSEvent.mouseLocation`).
    ///   - end: Drag end in AppKit screen coordinates.
    ///   - screenFrame: The frame of the display being selected, in AppKit
    ///     coordinates.
    /// - Returns: A normalized rect in ScreenCaptureKit's global display
    ///   coordinate space (origin top-left of the main display).
    public static func normalizeSelection(
        start: CGPoint,
        end: CGPoint,
        screenFrame: NSRect
    ) -> CGRect {
        // AppKit Y is bottom-up; ScreenCaptureKit expects top-down relative
        // to the main display's top edge.
        let yStart = screenFrame.maxY - start.y
        let yEnd = screenFrame.maxY - end.y
        return CGRect(
            x: min(start.x, end.x),
            y: min(yStart, yEnd),
            width: abs(end.x - start.x),
            height: abs(yEnd - yStart)
        )
    }

    /// Whether a selection is too small to be meaningful (accidental click).
    public static func isMeaningfulSelection(_ rect: CGRect, minimumSide: CGFloat = 4) -> Bool {
        rect.width >= minimumSide && rect.height >= minimumSide
    }

    /// Captures a single static frame of the given region (ScreenCaptureKit
    /// coordinates — see `normalizeSelection`).
    ///
    /// - Throws: `.capture(.permissionDenied)` when screen-recording is not
    ///   granted.
    public static func capture(in rect: CGRect) async throws -> Data {
        guard PermissionService.screenRecordingGranted else {
            throw StickyError.capture(.permissionDenied)
        }
        do {
            let image = try await SCScreenshotManager.captureImage(in: rect)
            guard let png = WindowCapture.pngData(from: image) else {
                throw StickyError.capture(.captureStreamFailed)
            }
            return png
        } catch {
            throw StickyError.capture(.captureStreamFailed)
        }
    }

    /// The capture-space frame for a screen (accounts for Retina scale and
    /// rotation). The App layer passes `screen.frame` and `backingScaleFactor`.
    public static func captureFrame(forScreenFrame frame: NSRect, backingScaleFactor: CGFloat) -> CGRect {
        CGRect(
            x: frame.origin.x * backingScaleFactor,
            y: frame.origin.y * backingScaleFactor,
            width: frame.width * backingScaleFactor,
            height: frame.height * backingScaleFactor
        )
    }
}
