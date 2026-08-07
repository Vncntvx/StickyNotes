import Foundation
import AppKit
import QuartzCore
import SystemBridge

// MARK: - RegionSelectionOverlay (T293, FR-091)
//
// Per tasks.md T293: a transparent selection overlay for region capture.
// The user drags a rectangle; the resulting ScreenCaptureKit-space rect is
// returned for `RegionCapture.capture(in:)`. Cancellation (Escape / click
// without drag) returns a zero rect. Single main display in v1 (multi-
// display overlay is a follow-up).

@MainActor
public enum RegionSelectionOverlay {

    /// Presents the overlay and awaits the user's drag. Returns a normalized
    /// capture rect; `.zero` on cancel.
    public static func presentSelection() async -> CGRect {
        await withCheckedContinuation { continuation in
            let overlay = OverlayWindow { rect in
                continuation.resume(returning: rect)
            }
            overlay.show()
        }
    }
}

/// The borderless overlay window: dimmed screen + drag rectangle.
@MainActor
private final class OverlayWindow: NSWindow {
    private let onSelection: (CGRect) -> Void
    private var dragStart: NSPoint?
    private var dragCurrent: NSPoint?
    private let selectionLayer = CAShapeLayer()

    init(onSelection: @escaping (CGRect) -> Void) {
        self.onSelection = onSelection
        guard let screen = NSScreen.main else {
            // No display available — fail closed with a zero rect.
            super.init(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            hasNoDisplay = true
            return
        }
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        setupLayer(screen: screen)
    }

    private var hasNoDisplay = false

    private func setupLayer(screen: NSScreen) {
        guard let contentView = contentView else { return }
        let dim = CALayer()
        dim.frame = contentView.bounds
        dim.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        contentView.layer = CALayer()
        contentView.layer?.addSublayer(dim)

        selectionLayer.fillColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
        selectionLayer.strokeColor = NSColor.systemBlue.cgColor
        selectionLayer.lineWidth = 1.5
        contentView.layer?.addSublayer(selectionLayer)
        _ = screen
    }

    func show() {
        if hasNoDisplay {
            onSelection(.zero)
            return
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        // The overlay is its own window; it must not steal the app's
        // activation permanently — it ends on the first completed drag.
    }

    override func mouseDown(with event: NSEvent) {
        // AppKit screen coordinates (bottom-left origin) — exactly what
        // RegionCapture.normalizeSelection expects.
        dragStart = convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        dragCurrent = dragStart
        selectionLayer.path = nil
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        updateSelectionPath()
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        guard let start = dragStart, let current = dragCurrent else { return }
        close()
        guard let screen = NSScreen.main else {
            onSelection(.zero)
            return
        }
        let captureRect = RegionCapture.normalizeSelection(
            start: CGPoint(x: start.x, y: start.y),
            end: CGPoint(x: current.x, y: current.y),
            screenFrame: screen.frame
        )
        onSelection(captureRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
            onSelection(.zero)
            return
        }
        super.keyDown(with: event)
    }

    private func updateSelectionPath() {
        guard let start = dragStart, let current = dragCurrent else { return }
        // Visual path is drawn in the overlay's top-left-origin layer space.
        let topLeft = CGPoint(x: min(start.x, current.x), y: max(start.y, current.y))
        let size = CGSize(width: abs(current.x - start.x), height: abs(current.y - start.y))
        selectionLayer.path = CGPath(
            roundedRect: CGRect(origin: topLeft, size: size),
            cornerWidth: 2,
            cornerHeight: 2,
            transform: nil
        )
    }
}
