import Testing
import Foundation
import AppKit
@testable import StickyNotes

// MARK: - Region-selection overlay lifecycle regression tests (2026-08-09 crash)
//
// The 2026-08-09 manual-run crash repeats the 2026-08-07 signature EXACTLY:
// EXC_BAD_ACCESS in `objc_release` during the main-thread autorelease pool
// drain (freed-memory markers 0xA1A1A1A1/0xA3A3A3A3), while the app was
// idle in `-[NSApplication run]`. Root-cause candidate:
// `OverlayWindow` (RegionSelectionOverlay) is the ONLY programmatic window
// that still uses the default `isReleasedWhenClosed = true` — AppKit
// releases the window on `close()` (drag complete / Escape) while the
// selection continuation still references it (double release), and the
// stale autorelease entry releases the freed object at the next pool
// drain. The 2026-08-07 fix applied `isReleasedWhenClosed = false` to every
// OTHER programmatic window; the overlay was missed.
//
// These tests open/close overlay windows repeatedly and assert the
// ownership invariant, mirroring NoteWindowLifecycleTests.

@MainActor
@Suite(.serialized) struct RegionOverlayLifecycleTests {

    @Test
    func overlayWindowRetainsOwnership() throws {
        let window = OverlayWindow { _ in }
        #expect(window.isReleasedWhenClosed == false,
                "overlay must retain ownership (2026-08-09 double-release crash)")
    }

    @Test
    func openCloseCyclesDoNotDoubleRelease() async throws {
        for _ in 0..<5 {
            let window = OverlayWindow { _ in }
            window.close()
            // Drain the runloop so AppKit's close processing + autorelease
            // pools flush — this is where the 2026-08-09 crash surfaced.
            try await Task.sleep(for: .milliseconds(50))
            #expect(window.windowNumber == 0 || !window.isVisible,
                    "overlay must be closed after the drain")
        }
    }
}
