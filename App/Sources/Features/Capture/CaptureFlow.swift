import Foundation
import os
import AppKit
import ScreenCaptureKit
import Domain
import SystemBridge

// MARK: - CaptureFlow (T293, US7/FR-091/FR-131)
//
// Per tasks.md T293 and spec FR-091/FR-131: the App-side capture entry
// points. Permission is requested ONLY when the user invokes a capture
// (the system picker / ScreenCaptureKit prompt — never at launch).
//
// - Window capture: presents the system content-sharing picker
//   (SCContentSharingPicker — no custom picker, no Accessibility), then
//   captures a single static frame (FR-092) of the chosen window.
// - Region capture: presents the region-selection overlay (single main
//   display in v1), then captures the dragged region.

@MainActor
public enum CaptureFlow {

    /// Captures a user-chosen application window as PNG. Presents the
    /// system picker; throws `.regionSelectionCanceled` on cancel.
    public static func captureWindowPNG() async throws -> Data {
        try await presentWindowPicker()
    }

    /// Captures a user-dragged screen region as PNG. Returns nil when the
    /// user cancels.
    public static func captureRegionPNG() async throws -> Data {
        let rect = await RegionSelectionOverlay.presentSelection()
        guard RegionCapture.isMeaningfulSelection(rect) else {
            throw StickyError.capture(.regionSelectionCanceled)
        }
        return try await RegionCapture.capture(in: rect)
    }

    // MARK: - System window picker (FR-091)

    /// Presents `SCContentSharingPicker` and captures ONE static frame of
    /// the chosen content (prototype-verified pattern: active + observer +
    /// present). The `SCContentFilter` never crosses the continuation —
    /// the capture happens inside the observer, only the PNG `Data`
    /// (Sendable) is handed back.
    private static func presentWindowPicker() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let picker = SCContentSharingPicker.shared
            picker.isActive = true
            let observer = WindowPickerObserver { data in
                continuation.resume(returning: data)
            } onCancel: {
                continuation.resume(throwing: StickyError.capture(.regionSelectionCanceled))
            }
            picker.add(observer)
            picker.present()
            // The observer releases itself after the first callback; a hard
            // timeout keeps the caller from hanging if the picker stalls.
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 min
                observer.timeoutIfPending()
            }
        }
    }
}

/// Picker observer: captures a single static frame of the chosen content,
/// resolves the continuation once with the PNG data, then removes itself
/// (no retained stream, FR-092). Nonisolated conformance (the picker
/// callback thread); the filter never crosses actor boundaries.
private final class WindowPickerObserver: NSObject, SCContentSharingPickerObserver {
    private let onData: @Sendable (Data) -> Void
    private let onCancel: @Sendable () -> Void
    private let state = OSAllocatedUnfairLock(initialState: false)

    init(onData: @escaping @Sendable (Data) -> Void, onCancel: @escaping @Sendable () -> Void) {
        self.onData = onData
        self.onCancel = onCancel
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard claimOnce() else { return }
        picker.isActive = false
        picker.remove(self)
        let sink = onData
        // SCContentFilter is not Sendable; box it so the async capture can
        // consume it without crossing an isolation boundary unsafely (the
        // picker callback is nonisolated; the box is consumed once here).
        let box = FilterBox(filter)
        Task {
            do {
                let png = try await WindowCapture.captureSingleFrame(contentFilter: box.filter)
                sink(png)
            } catch {
                sink(Data())
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        guard claimOnce() else { return }
        picker.isActive = false
        picker.remove(self)
        onCancel()
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        guard claimOnce() else { return }
        SCContentSharingPicker.shared.isActive = false
        SCContentSharingPicker.shared.remove(self)
        onCancel()
    }

    func timeoutIfPending() {
        guard claimOnce() else { return }
        SCContentSharingPicker.shared.isActive = false
        SCContentSharingPicker.shared.remove(self)
        onCancel()
    }

    private func claimOnce() -> Bool {
        let first = state.withLock { resolved -> Bool in
            if resolved { return false }
            resolved = true
            return true
        }
        return first
    }
}

/// Sendable box for the non-Sendable `SCContentFilter` (consumed exactly
/// once by the single-frame capture inside the observer).
private final class FilterBox: @unchecked Sendable {
    let filter: SCContentFilter
    init(_ filter: SCContentFilter) {
        self.filter = filter
    }
}
