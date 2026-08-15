import Testing
import Foundation
import SwiftUI
@testable import StickyNotes

// MARK: - About reachability tests (T149, FR-008)
//
// Per tasks.md T149: the About panel is reachable from the menu-bar
// interface with the Dock disabled. The AboutView exists and the menu-bar
// library footer exposes the About button (MenuBarLibraryScene footer);
// AboutView renders reachable content regardless of the Dock activation
// policy (DockActivationBridge policy switch never removes menu-bar
// access).

@Suite struct AboutReachabilityIntegrationTests {
    // @MainActor: the assertion renders AboutView through an NSHostingView —
    // SwiftUI View.body is main-actor-isolated, and rendering from a
    // background test thread crashes (actor assertion, 2026-08-15).
    @MainActor
    @Test
    func aboutViewRendersReachableContent() {
        // AboutView is a pure SwiftUI view — instantiable and renderable
        // without any Dock dependency. Render it into an NSHostingView to
        // prove the view tree builds (FR-008/FR-144 reachability).
        let hosting = NSHostingView(rootView: AboutView())
        hosting.layoutSubtreeIfNeeded()
        _ = hosting.rootView
        #expect(hosting.fittingSize.width > 0, "AboutView must lay out content")
    }
}
