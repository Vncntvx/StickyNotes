import Foundation
import ScreenCaptureKit
import CoreGraphics
import ImageIO
import Domain

// MARK: - WindowCapture (T089)
//
// Per tasks.md T089 and plan §Screenshot capture:
//
// - Application-window capture uses the system content-sharing picker
//   (SCContentSharingPicker — no custom picker).
// - ONE static frame per selection; the stream/config is released
//   immediately (no retained live stream; spec non-goal: no live
//   monitoring, constitution I).
// - Preserves app name/icon/title/capture time via SCContentFilter
//   metadata; the App layer reads those and stores them on the
//   ScreenshotAssociation.
// - Screen-recording permission is requested only on capture invocation
//   (the OS prompt); NO Accessibility permission for ordinary capture
//   (constitution VI; research.md R7).

/// Captures a single static frame of a chosen window or display.
public enum WindowCapture {

    /// Captures one frame with the given filter, returning PNG-encoded
    /// image data. Call with a filter from the system picker
    /// (SCContentSharingPicker) or SCShareableContent.
    ///
    /// - Throws: `.capture(.permissionDenied)` when screen-recording is not
    ///   granted; `.capture(.captureStreamFailed)` on capture errors or when
    ///   the SDK reports a nil image without an error.
    public static func captureSingleFrame(
        contentFilter: SCContentFilter,
        maxDimension: Int = 4096
    ) async throws -> Data {
        guard PermissionService.screenRecordingGranted else {
            throw StickyError.capture(.permissionDenied)
        }

        let config = SCStreamConfiguration()
        config.width = maxDimension
        config.height = maxDimension
        config.showsCursor = false

        return try await captureSingleFrame(imageProvider: {
            await Self.captureViaScreenCaptureKit(contentFilter: contentFilter, configuration: config)
        })
    }

    /// A frame provider returning the captured image, or nil when the
    /// capture produced no image (the fail-closed input — T303).
    public typealias FrameProvider = () async -> CGImage?

    /// The fail-closed capture core (T303): maps the provider outcome to the
    /// sanitized `.capture(.captureStreamFailed)` error. A nil image — with
    /// or without an error — MUST NOT crash the application (FR-011a/FR-092/
    /// FR-153): no partial asset or note is created, and the rest of the app
    /// stays fully usable.
    public static func captureSingleFrame(imageProvider: FrameProvider) async throws -> Data {
        guard let image = await imageProvider() else {
            throw StickyError.capture(.captureStreamFailed)
        }
        guard let png = Self.pngData(from: image) else {
            throw StickyError.capture(.captureStreamFailed)
        }
        return png
    }

    /// Wraps the ScreenCaptureKit completion-handler API with explicit
    /// nil-image/nil-error handling (T303).
    ///
    /// The SDK's Swift async `captureImage(contentFilter:configuration:)`
    /// bridge crashes with an implicitly-unwrapped-nil fatal error when the
    /// underlying completion reports a nil image WITH a nil error (observed
    /// on macOS 27 beta with screen-recording granted). Calling the block
    /// form directly and treating a nil image as a failed capture makes the
    /// path fail closed instead of crashing.
    public static func captureViaScreenCaptureKit(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async -> CGImage? {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// PNG-encodes a captured CGImage.
    public static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The filter metadata the app stores on the ScreenshotAssociation:
    /// application name and window title (may be nil).
    public static func metadata(from filter: SCContentFilter) -> (applicationName: String?, windowTitle: String?) {
        let appName = filter.includedApplications.first?.applicationName
        let title = filter.includedWindows.first?.title
        return (appName, title)
    }
}
