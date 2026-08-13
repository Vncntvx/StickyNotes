import SwiftUI
import AppKit

// MARK: - ContextualFormatOverlay (004, 2026-08-10 clickability fix)
//
// The contextual format row floats above the rich-text editor and must
// accept clicks. A SwiftUI `.overlay` on the editor cannot: AppKit hit
// testing resolves the deepest real NSView (the NSTextView) at those
// coordinates, so mouse events never reach SwiftUI-drawn overlay content.
// Hosting the row in a topmost NSHostingView on the window's contentView
// gives it a real NSView (hit-testable above the editor) while the row
// still renders via SwiftUI (glassEffect grouping, FR-022). Position
// follows the bridge's selection rect in window coordinates; FR-012
// deactivation semantics are inherited from `bridge.hasFocus` (row hidden
// while the window is inactive).

/// Hosts and positions the contextual format row at the AppKit level.
@MainActor
final class ContextualFormatOverlay: NSObject {
    private weak var contentView: NSView?
    private weak var bridge: EditorSelectionBridge?
    private var hostingView: NSHostingView<ContextualFormatBar>?
    private var resizeObserver: (any NSObjectProtocol)?
    private var observing = false
    /// Whether the row is currently shown (test-observable).
    private(set) var isVisible = false

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
        hostingView = hosting
        contentView = window.contentView
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateLayout() }
        }
        observe()
        updateLayout()
    }

    /// Removes the row and stops observing.
    func detach() {
        observing = false
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
        }
        resizeObserver = nil
        hostingView?.removeFromSuperview()
        hostingView = nil
        bridge = nil
        contentView = nil
        isVisible = false
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
            hosting.isHidden = true
            isVisible = false
            return
        }
        // The bridge reports the rect in window base coordinates; convert
        // into the content view's space (they differ by the titlebar on
        // non-fullSize windows; on this window they coincide — convert is
        // still the correct, robust step).
        let rect = contentView.convert(windowRect, from: nil)
        let size = barSize(in: hosting)
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
        hosting.isHidden = false
        isVisible = true
    }

    private func barSize(in hosting: NSHostingView<ContextualFormatBar>) -> CGSize {
        // The bar's logical size is deterministic (5 × 26 pt buttons,
        // spacing 2, horizontal padding 6, vertical padding 4 around a
        // 22 pt button) — NSHostingView.fittingSize proved unreliable
        // (reported 82 pt tall), so pin the frame to the design metrics.
        CGSize(width: 150, height: 30)
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

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        MainActor.assumeIsolated {
            coordinator.overlay?.detach()
            coordinator.overlay = nil
        }
    }
}
