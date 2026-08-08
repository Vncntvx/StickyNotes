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

    /// A single-frame capture provider: returns the captured image, or nil
    /// when the capture produced no image (the fail-closed input — the SDK
    /// has been observed reporting nil image with nil error; see below).
    public typealias SingleFrameCapture = (CGRect) async throws -> CGImage?

    /// Captures a single static frame of the given region (ScreenCaptureKit
    /// coordinates — see `normalizeSelection`).
    ///
    /// - Throws: `.capture(.permissionDenied)` when screen-recording is not
    ///   granted; `.capture(.captureStreamFailed)` on capture errors or when
    ///   the SDK reports a nil image without an error.
    public static func capture(in rect: CGRect) async throws -> Data {
        guard PermissionService.screenRecordingGranted else {
            throw StickyError.capture(.permissionDenied)
        }
        return try await capture(in: rect, using: Self.captureViaScreenCaptureKit)
    }

    /// The fail-closed capture core (T303): maps the provider outcome to the
    /// sanitized `.capture(.captureStreamFailed)` error. A nil image — with
    /// or without an error — MUST NOT crash the application (FR-011a/FR-092/
    /// FR-153): no partial asset or note is created, and the rest of the app
    /// stays fully usable.
    public static func capture(in rect: CGRect, using provider: SingleFrameCapture) async throws -> Data {
        do {
            guard let image = try await provider(rect) else {
                throw StickyError.capture(.captureStreamFailed)
            }
            guard let png = WindowCapture.pngData(from: image) else {
                throw StickyError.capture(.captureStreamFailed)
            }
            return png
        } catch let StickyError.capture(code) {
            throw StickyError.capture(code)
        } catch {
            throw StickyError.capture(.captureStreamFailed)
        }
    }

    /// Wraps the ScreenCaptureKit completion-handler API with explicit
    /// nil-image/nil-error handling (T303).
    ///
    /// The SDK's Swift async `captureImage(in:)` bridge crashes with an
    /// implicitly-unwrapped-nil fatal error when the underlying completion
    /// reports a nil image WITH a nil error (observed on macOS 27 beta with
    /// screen-recording granted). Calling the block form directly and
    /// treating a nil image as a failed capture makes the path fail closed
    /// instead of crashing.
    public static func captureViaScreenCaptureKit(in rect: CGRect) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(in: rect) { image, _ in
                continuation.resume(returning: image)
            }
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
