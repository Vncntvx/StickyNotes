import SwiftUI
import AppKit
import Domain

// MARK: - MediaPresenters (T292, FR-095/FR-095a/FR-090)
//
// Presents the FR-095a screenshot viewer and the FR-090 embedded-image
// larger view in independent note-style windows (borderless, FR-030a
// family). Several viewers MAY be open at once (FR-095a); the viewer never
// activates the captured application.

@MainActor
public enum MediaPresenters {

    /// Opens the screenshot viewer for a note's screenshots (FR-095a zoom
    /// 25–400%, arrow navigation, caption editing, drag-out; T297: real
    /// image via the injected provider + Copy/Drag-out/Save As/Delete
    /// Association).
    public static func presentScreenshotViewer(
        noteId: UUID,
        screenshots: [ScreenshotPayload],
        imageProvider: @escaping (UUID) async throws -> Data? = { _ in nil },
        onDeleteAssociation: @escaping (UUID) -> Void = { _ in }
    ) {
        guard !screenshots.isEmpty else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScreenshotViewer(
            noteId: noteId,
            screenshots: screenshots,
            imageProvider: imageProvider,
            onDeleteAssociation: onDeleteAssociation
        ))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens a larger view of an embedded image (FR-090 "view/larger").
    public static func presentImagePreview(title: String, image: NSImage) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = imageView
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
