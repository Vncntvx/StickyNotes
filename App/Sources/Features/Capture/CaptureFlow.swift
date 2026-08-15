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
    /// (Sendable) is handed back. Capture errors propagate (R1.3,
    /// remediation-phase1 T014): a failed capture is a FAILURE, never an
    /// empty `Data` that would be stored as a corrupt screenshot.
    private static func presentWindowPicker() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let picker = SCContentSharingPicker.shared
            picker.isActive = true
            let observer = WindowPickerObserver { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            } onCancel: {
                continuation.resume(throwing: StickyError.capture(.regionSelectionCanceled))
            }
            picker.add(observer)
            picker.present()
            // The observer releases itself after the first callback; a hard
            // timeout keeps the caller from hanging if the picker stalls.
            Task {
                try? await Task.sleep(for: .seconds(300)) // 5 min
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
    private let onResult: @Sendable (Result<Data, Error>) -> Void
    private let onCancel: @Sendable () -> Void
    private let state = OSAllocatedUnfairLock(initialState: false)

    init(onResult: @escaping @Sendable (Result<Data, Error>) -> Void, onCancel: @escaping @Sendable () -> Void) {
        self.onResult = onResult
        self.onCancel = onCancel
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        guard claimOnce() else { return }
        picker.isActive = false
        picker.remove(self)
        let sink = onResult
        // SCContentFilter is not Sendable; box it so the async capture can
        // consume it without crossing an isolation boundary unsafely (the
        // picker callback is nonisolated; the box is consumed once here).
        let box = FilterBox(filter)
        Task {
            do {
                let png = try await WindowCapture.captureSingleFrame(contentFilter: box.filter)
                sink(.success(png))
            } catch {
                // R1.3 (T014): propagate the failure — the caller's
                // fail-closed path rejects it (no partial note/asset).
                sink(.failure(error))
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
