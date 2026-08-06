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
    ///   granted; `.capture(.captureStreamFailed)` on capture errors.
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

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: config
            )
            guard let png = Self.pngData(from: image) else {
                throw StickyError.capture(.captureStreamFailed)
            }
            return png
        } catch {
            throw StickyError.capture(.captureStreamFailed)
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
