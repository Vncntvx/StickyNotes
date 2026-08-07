import SwiftUI
import Observation
import AppKit

// MARK: - DeletionToastPresenter (T246, FR-009a)
//
// Per tasks.md T246 and spec FR-009a (clarified 2026-08-07): when a note
// with an open window is deleted (to Trash or permanently), the window
// closes immediately and a ONE-TIME, non-blocking, auto-dismissing transient
// toast announces the localized outcome ("Moved to Trash" / "Permanently
// Deleted") without blocking interaction or requiring dismissal. The toast is
// VoiceOver-announceable and respects the active locale (FR-180a). Restoring
// from Trash never reopens the window (FR-007).

@MainActor
@Observable
public final class DeletionToastPresenter {
    public struct Toast: Identifiable, Equatable {
        public let id = UUID()
        public let message: String
    }

    public private(set) var currentToast: Toast?
    /// Auto-dismiss window (short, bounded — FR-009a).
    public static let autoDismissInterval: TimeInterval = 2.5

    private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Presents the deletion toast and schedules auto-dismiss. VoiceOver
    /// announcement happens via the view's accessibility announcement
    /// (FR-180b).
    public func present(message: String) {
        dismissTask?.cancel()
        currentToast = Toast(message: message)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.autoDismissInterval))
            guard !Task.isCancelled else { return }
            self?.currentToast = nil
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        currentToast = nil
    }
}

/// The overlay toast view (non-blocking; never intercepts interaction).
public struct DeletionToastOverlay: View {
    let toast: DeletionToastPresenter.Toast

    public var body: some View {
        Text(toast.message)
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(toast.message)
            .allowsHitTesting(false)
    }
}
