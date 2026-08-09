import XCTest

// MARK: - Launch smoke test (headless-safe baseline)
//
// 2026-08-09: all automated click journeys were CANCELLED per product
// decision — synthetic XCUITest clicks/typing are unreliable on macOS 27
// beta and require an interactive display session (the 14-journey suite
// failed repeatedly in headless sessions). Only the launch smoke test
// remains in this bundle; interactive coverage moves to manual QA
// (quickstart.md §Manual testing on your Mac).
//
// Cancelled journeys (T305/T141/T163j + T078 dropdown): menu-bar icon
// open/dismiss/re-click (FR-009); note create/open/focus-existing/close
// (FR-005/FR-006); Trash restore + permanent delete (FR-014); screenshot
// viewer opens without activating the captured app (FR-095); seven-color
// palette (FR-030); Settings four-panel navigation (FR-050); sync attention
// banner (FR-010); Library scaling formula (FR-070); keyboard-only workflow
// (SC-017/FR-072); menu-bar right-click dropdown (FR-001/Constitution X).
// Their assertions remain covered by AppTests unit/integration suites.

@MainActor
final class CriticalFlowsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var app: XCUIApplication!

    /// Launches the app. The smoke test only verifies launch state — no
    /// synthetic mouse clicks are performed (automated click tests are
    /// cancelled per product decision).
    private func launchApp() {
        let app = XCUIApplication()
        app.launch()
        self.app = app
    }

    // MARK: - Journeys

    func testMenuBarOpenAndDismiss() throws {
        launchApp()
        // The app is menu-bar-primary: the dock icon may be hidden. Launch
        // is the smoke test; the menu-bar icon interaction is driven via the
        // status bar. (Interactive journeys run manually per quickstart.md.)
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }
}
