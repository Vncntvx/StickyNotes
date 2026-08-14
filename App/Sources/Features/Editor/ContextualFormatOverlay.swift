import SwiftUI
import AppKit

// MARK: - ContextualFormatOverlay (004, 2026-08-10 clickability fix; 2026-08-14 layer-composite fix)
//
// The contextual format row floats above the rich-text editor and must
// accept clicks. A SwiftUI `.overlay` on the editor cannot: AppKit hit
// testing resolves the deepest real NSView (the NSTextView) at those
// coordinates, so mouse events never reach SwiftUI-drawn overlay content.
// Hosting the row in a topmost NSHostingView subview of the window's
// contentView gives it a real NSView (hit-testable above the editor)
// while the row still renders via SwiftUI.
//
// 2026-08-14 (ROOT CAUSE, verified in a self-contained test): a SwiftUI
// NSHostingView used as the window contentView does NOT attach subview
// layers to its backing-layer tree — the subview's layer stays orphaned
// (superlayer == nil), so WindowServer never composites it (offscreen
// cacheDisplay works because it walks the view tree; the screen composite
// walks the layer tree). `attachLayerToComposite` mounts the bar's layer
// manually. An extra window (panel) was tried and rejected: on the Liquid
// Glass shell any extra window deactivates the LSUIElement app ~1-6 s
// after appearing (didResignKey + NSApp.isActive == false), so the bar
// stays IN-WINDOW.

/// Hosts and positions the contextual format row at the AppKit level.
@MainActor
final class ContextualFormatOverlay: NSObject {
    private weak var contentView: NSView?
    private weak var bridge: EditorSelectionBridge?
    private var hostingView: NSHostingView<ContextualFormatBar>?
    private var resizeObserver: (any NSObjectProtocol)?
    private var moveObserver: (any NSObjectProtocol)?
    private var observing = false
    /// Debounced hide (2026-08-14): a transient key/selection flutter must
    /// not flicker the bar; a genuinely inactive state hides after 1 s.
    private var hideTask: Task<Void, Never>?
    /// Whether the row is currently shown (test-observable).
    private(set) var isVisible = false

    /// The bar's logical size (5 × 26 pt buttons, 4 × 2 pt spacing,
    /// horizontal padding 6 — 2026-08-14: eraser added, inline code
    /// removed per user request).
    private static let barSize = NSSize(width: 150, height: 30)

    /// Installs the row above the window content (replacing any previous
    /// installation on the same window).
    func install(in window: NSWindow, bridge: EditorSelectionBridge) {
        detach()
        self.bridge = bridge
        let hosting = NSHostingView(rootView: ContextualFormatBar(bridge: bridge))
        hosting.wantsLayer = true
        hosting.isHidden = true
        // Keep the bar OUT of the window's autolayout: a constraint-free
        // autolayout subview on the content hosting view perturbs the
        // window layout (runaway window resizing observed 2026-08-10).
        // The frame is managed manually from the selection rect.
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = []
        window.contentView?.addSubview(hosting, positioned: .above, relativeTo: nil)
        attachLayerToComposite(of: window)
        hostingView = hosting
        contentView = window.contentView
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateLayout() }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateLayout() }
        }
        observe()
        updateLayout()
    }

    /// Removes the row and stops observing.
    func detach() {
        hideTask?.cancel()
        hideTask = nil
        observing = false
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        resizeObserver = nil
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
        }
        moveObserver = nil
        if let hosting = hostingView {
            hosting.layer?.removeFromSuperlayer()
            hosting.removeFromSuperview()
        }
        hostingView = nil
        bridge = nil
        contentView = nil
        isVisible = false
    }

    /// Attaches the overlay's layer to the window's content layer tree —
    /// the SwiftUI contentView hosting does NOT do this for subviews
    /// (2026-08-14, verified). Idempotent; re-attaches if AppKit moved it.
    private func attachLayerToComposite(of window: NSWindow) {
        guard let contentLayer = window.contentView?.layer,
              let layer = hostingView?.layer else { return }
        if layer.superlayer !== contentLayer {
            contentLayer.addSublayer(layer)
        }
        layer.zPosition = 1000
    }

    private func observe() {
        observing = true
        withObservationTracking { [weak self] in
            guard let bridge = self?.bridge else { return }
            MainActor.assumeIsolated {
                _ = bridge.isTextSelected
                _ = bridge.hasFocus
                _ = bridge.selectionRectInWindow
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.observing else { return }
                self.updateLayout()
                self.observe()
            }
        }
    }

    private func updateLayout() {
        guard let bridge, let hosting = hostingView, let contentView else {
            isVisible = false
            return
        }
        guard bridge.isTextSelected, bridge.hasFocus,
              let windowRect = bridge.selectionRectInWindow else {
            // Debounced hide: a transient key/selection flutter must not
            // flicker the bar; a genuinely inactive state hides after 1 s.
            scheduleHide(after: .milliseconds(1000))
            return
        }
        // A text view with uncommitted layout can answer `firstRect` with
        // a zero/invalid rect right after a drag selection — ignore it and
        // keep the last placement instead of hiding or teleporting. Never
        // intersect the LOCAL window rect against the SCREEN-space parent
        // frame (always false high on screen, 2026-08-14).
        let valid = windowRect.width > 0 && windowRect.height > 0
            && windowRect.origin.x.isFinite && windowRect.origin.y.isFinite
        guard valid else { return }
        hideTask?.cancel()
        // The bridge reports the rect in window base coordinates; convert
        // into the content view's space (they differ by the titlebar on
        // non-fullSize windows; on this window they coincide — convert is
        // still the correct, robust step).
        let rect = contentView.convert(windowRect, from: nil)
        let size = Self.barSize
        let minX = size.width / 2 + 8
        let maxX = max(contentView.bounds.width - size.width / 2 - 8, minX)
        let midX = min(max(rect.midX, minX), maxX)
        // Above the selection in y-up content coordinates: bar bottom sits
        // 6 pt clear of the selection's top edge.
        let proposedY = rect.maxY + 6
        let topBound = max(contentView.bounds.height - 44 - size.height, 8)
        let y = min(max(proposedY, 8), topBound)
        hosting.setFrameSize(size)
        hosting.setFrameOrigin(NSPoint(x: midX - size.width / 2, y: y))
        if hosting.isHidden {
            hosting.isHidden = false
        }
        // Defensive: keep the layer in the composite tree (AppKit may
        // re-parent it during layout) and force a redraw into the layer.
        if let window = hosting.window {
            attachLayerToComposite(of: window)
        }
        hosting.needsDisplay = true
        hosting.layer?.setNeedsDisplay()
        isVisible = true
    }

    /// Debounced hide: waits for transient state to settle, then re-checks
    /// the bridge — only hides if the row is still unwarranted.
    private func scheduleHide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            hideTask = nil
            guard let bridge, let hosting = hostingView else { return }
            guard !(bridge.isTextSelected && bridge.hasFocus && bridge.selectionRectInWindow != nil) else { return }
            hosting.isHidden = true
            isVisible = false
        }
    }
}

// MARK: - SwiftUI anchor

/// A zero-size, hit-test-transparent NSView used purely as a mount point:
/// it exists to learn the window and to tear the overlay down with the
/// view hierarchy. Clicks must never reach it (the body stays clickable).
private final class PassthroughMountView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A zero-size representable that installs the AppKit overlay once the
/// view is inside a window (the bridge only exists after the editor's
/// `.task` creates it).
struct ContextualFormatOverlayAnchor: NSViewRepresentable {
    let bridge: EditorSelectionBridge

    final class Coordinator {
        var overlay: ContextualFormatOverlay?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { PassthroughMountView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        // updateNSView can run before the mount view is attached to a
        // window (window == nil); retry asynchronously until it is — the
        // overlay must exist before the first selection can be made.
        Self.installWhenReady(coordinator: context.coordinator, view: nsView, bridge: bridge)
    }

    private static func installWhenReady(
        coordinator: Coordinator,
        view: NSView,
        bridge: EditorSelectionBridge
    ) {
        guard coordinator.overlay == nil else { return }
        if let window = view.window {
            let overlay = ContextualFormatOverlay()
            overlay.install(in: window, bridge: bridge)
            coordinator.overlay = overlay
        } else {
            DispatchQueue.main.async { [weak coordinator, weak view] in
                guard let coordinator, let view else { return }
                installWhenReady(coordinator: coordinator, view: view, bridge: bridge)
            }
        }
    }
}
