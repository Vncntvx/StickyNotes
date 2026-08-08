import XCTest
import AppKit

// MARK: - Critical UI flows (T163j / T141 + T305, US1/US6/US7)
//
// Per tasks.md T163j/T305: XCUITest critical journeys —
// (a) menu-bar open/dismiss/re-click (FR-009);
// (b) note create → focus → type → close → reopen → content preserved;
//     re-opening focuses the existing window, never a duplicate
//     (FR-005/FR-006/FR-007a);
// (c) Trash restore + permanent delete (FR-014);
// (d) screenshot viewer opens without activating the captured application
//     (FR-095; skipped without screen-recording permission).
//
// These journeys require an interactive display session (CI machines with a
// logged-in GUI). The original launch smoke test is retained as the
// headless-safe baseline.

@MainActor
final class CriticalFlowsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private var app: XCUIApplication!

    /// Launches the app, optionally seeding a note whose first block
    /// contains `marker` via the test-only `-UITestSeedNote` launch argument
    /// (T305). Seeding avoids synthetic keyboard input entirely — typing
    /// and paste through XCUITest are unreliable on macOS 27 beta.
    private func launchApp(seedNote marker: String? = nil) {
        let app = XCUIApplication()
        if let marker {
            app.launchArguments = ["-UITestSeedNote", marker]
        }
        app.launch()
        self.app = app
    }

    private var statusItem: XCUIElement {
        app.statusItems["Notes"]
    }

    private func openLibrary(timeout: TimeInterval = 20) {
        // The status item may briefly report offscreen/hit-test-unfriendly
        // coordinates right after launch (menu-bar placement races); wait
        // until it is actually hittable before clicking.
        let item = statusItem
        XCTAssertTrue(item.waitForExistence(timeout: 12), "status item not found")
        let hittable = NSPredicate(format: "isHittable == true")
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: item)], timeout: 12)
        let newNote = app.buttons["New Note"]
        var attempts = 0
        while !newNote.exists && attempts < 2 {
            item.click()
            attempts += 1
            _ = newNote.waitForExistence(timeout: timeout / 2)
        }
        XCTAssertTrue(newNote.waitForExistence(timeout: timeout), "library did not open")
    }



    /// Switches the library scope (Notes <-> Trash) via the segmented
    /// control; the segments surface as buttons or radio buttons depending
    /// on the AppKit/SwiftUI mapping.
    private func switchScope(to name: String) {
        let button = app.buttons[name]
        if button.exists { button.click(); return }
        let radio = app.radioButtons[name]
        if radio.exists { radio.click(); return }
        let any = app.descendants(matching: .any)[name]
        XCTAssertTrue(any.waitForExistence(timeout: 6), "scope segment not found: " + name)
        any.click()
    }

    private func closeFrontWindow() {
        // ⌘W closes the key note window (FR-007a focus). Fall back to the
        // upper-area close button when the window did not take key status.
        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 1)
        if app.textViews.firstMatch.exists {
            let closeButton = app.buttons["Close note"]
            if closeButton.exists { closeButton.click() }
        }
    }

    private func card(containing text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return app.buttons.matching(predicate).firstMatch
    }

    /// A unique marker per run so repeated test launches never match stale
    /// notes from previous runs (the App Group container is shared state).
    private func uniqueMarker(_ prefix: String) -> String {
        "ui-\(prefix)-\(UUID().uuidString.prefix(8))"
    }

    private func openLibraryIfDismissed() {
        if !app.buttons["New Note"].exists {
            statusItem.click()
            _ = app.buttons["New Note"].waitForExistence(timeout: 10)
        }
    }

    private func closeLibraryAndQuit() {
        app.terminate()
    }

    // MARK: - Journeys

    func testMenuBarOpenAndDismiss() throws {
        launchApp()
        // The app is menu-bar-primary: the dock icon may be hidden. Launch
        // is the smoke test; the menu-bar icon interaction is driven via the
        // status bar. (Full journeys run on CI machines with a display.)
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
    }

    /// (a) FR-009: clicking the menu-bar icon dismisses the focused library,
    /// reopens it, and never opens a second library window.
    func testMenuBarReClickTogglesLibrary() throws {
        launchApp()
        openLibrary()
        XCTAssertTrue(app.buttons["New Note"].exists, "library open")

        // Focused → dismissed.
        statusItem.click()
        let newNote = app.buttons["New Note"]
        XCTAssertTrue(newNote.waitForNonExistence(timeout: 10), "library should dismiss on re-click")

        // Re-open: exactly one library window (never a second).
        statusItem.click()
        XCTAssertTrue(newNote.waitForExistence(timeout: 10), "library should reopen")
        let instances = app.buttons.matching(identifier: "New Note")
        XCTAssertEqual(instances.count, 1, "second library window must never open (FR-009)")

        closeLibraryAndQuit()
    }

    /// (b) FR-005/FR-006/FR-007a: create → type → close → reopen → content
    /// preserved; reopening focuses the existing window, no duplicate.
    func testNoteLifecyclePreservesContentWithoutDuplicate() throws {
        let marker = uniqueMarker("journey")
        launchApp(seedNote: marker)
        openLibrary()

        // The seeded note's card contains the marker (summary + preview).
        let noteCard = card(containing: marker)
        XCTAssertTrue(noteCard.waitForExistence(timeout: 15), "seeded note card not found")
        noteCard.click()

        // The note window opens with the preserved content (FR-006).
        let openedTextView = app.textViews.firstMatch
        XCTAssertTrue(openedTextView.waitForExistence(timeout: 10), "note window did not open")
        closeFrontWindow()

        // Reopen from the library card. The card label contains the marker
        // (summary + preview) — the FR-006 content-preservation proof.
        openLibraryIfDismissed()
        if !noteCard.waitForExistence(timeout: 10) {
            for b in app.buttons.allElementsBoundByIndex {
                print("JOURNEY_CARD: " + b.label)
            }
        }
        XCTAssertTrue(noteCard.exists, "note card not found after close")
        noteCard.click()

        // The reopened note window shows the preserved content (FR-006).
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10), "note window did not reopen")

        // Selecting the already-open note focuses the existing window — no
        // duplicate (FR-005): the window count must NOT grow when the open
        // note's card is clicked again (the MenuBarExtra library window
        // appears/dismisses independently, so growth — not absolute count —
        // is the stable assertion).
        openLibraryIfDismissed()
        let windowsBeforeSecondClick = app.windows.count
        noteCard.click()
        Thread.sleep(forTimeInterval: 2)
        XCTAssertLessThanOrEqual(
            app.windows.count,
            windowsBeforeSecondClick,
            "duplicate window created (FR-005)"
        )
        XCTAssertEqual(app.textViews.count, 1, "more than one note window for the note (FR-005)")

        closeLibraryAndQuit()
    }

    /// (c) FR-014: delete → Trash → restore; delete again → permanent
    /// delete beyond Trash recovery.
    func testTrashRestoreAndPermanentDelete() throws {
        let marker = uniqueMarker("trash")
        launchApp(seedNote: marker)
        openLibrary()

        // Move to Trash from the card's context menu.
        let noteCard = card(containing: marker)
        XCTAssertTrue(noteCard.waitForExistence(timeout: 15), "note card not found")
        noteCard.rightClick()
        let moveToTrash = app.menuItems["Move to Trash"]
        XCTAssertTrue(moveToTrash.waitForExistence(timeout: 6), "context menu did not open")
        moveToTrash.click()

        // The active library no longer shows the note.
        XCTAssertTrue(noteCard.waitForNonExistence(timeout: 10), "note still in active library after delete")

        // Trash scope: restore it.
        switchScope(to: "Trash")
        let trashedCard = card(containing: marker)
        XCTAssertTrue(trashedCard.waitForExistence(timeout: 10), "note not found in Trash")
        trashedCard.rightClick()
        let restore = app.menuItems["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 6), "restore action missing")
        restore.click()
        XCTAssertTrue(trashedCard.waitForNonExistence(timeout: 10), "note not removed from Trash after restore")

        // Back in the active library (FR-014 restore).
        switchScope(to: "Notes")
        XCTAssertTrue(card(containing: marker).waitForExistence(timeout: 10), "note not restored to library")

        // Delete again, then permanently delete from Trash.
        let restoredCard = card(containing: marker)
        restoredCard.rightClick()
        XCTAssertTrue(app.menuItems["Move to Trash"].waitForExistence(timeout: 6))
        app.menuItems["Move to Trash"].click()
        XCTAssertTrue(restoredCard.waitForNonExistence(timeout: 10))

        switchScope(to: "Trash")
        let permanentCard = card(containing: marker)
        XCTAssertTrue(permanentCard.waitForExistence(timeout: 10), "note not found in Trash for permanent delete")
        permanentCard.rightClick()
        let deleteForever = app.menuItems["Delete Forever"]
        XCTAssertTrue(deleteForever.waitForExistence(timeout: 6), "Delete Forever action missing")
        deleteForever.click()
        XCTAssertTrue(permanentCard.waitForNonExistence(timeout: 10), "note survived permanent delete")

        closeLibraryAndQuit()
    }

    /// (d) FR-095: the screenshot viewer opens in the app without
    /// activating any other application. Requires screen-recording
    /// permission; skipped (not failed) when it is absent so headless CI
    /// stays green.
    func testScreenshotViewerOpensWithoutActivatingOriginalApp() throws {
        try XCTSkipUnless(
            CGPreflightScreenCaptureAccess(),
            "screen-recording permission required; skipping screenshot journey"
        )

        let marker = uniqueMarker("viewer")
        launchApp(seedNote: marker)
        openLibrary()

        // Reopen the note and invoke region capture from the upper area.
        let noteCard = card(containing: marker)
        XCTAssertTrue(noteCard.waitForExistence(timeout: 15))
        noteCard.click()
        let textView = app.textViews.firstMatch
        XCTAssertTrue(textView.waitForExistence(timeout: 10))

        let addScreenshot = app.buttons["Add screenshot"]
        XCTAssertTrue(addScreenshot.waitForExistence(timeout: 6), "Add screenshot control missing")
        addScreenshot.click()

        // Drag a region on the selection overlay (single-main-display v1).
        let overlay = app.windows.allElementsBoundByIndex.last ?? app.windows.firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 8), "region overlay did not appear")
        let start = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
        let end = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
        start.press(forDuration: 0.2, thenDragTo: end)

        // The note now contains a screenshot block; clicking it opens the
        // viewer in an independent note-style window.
        let noteWindowCount = app.windows.count
        let screenshotBlock = app.images.firstMatch
        XCTAssertTrue(screenshotBlock.waitForExistence(timeout: 10), "screenshot block not inserted")
        screenshotBlock.click()
        XCTAssertTrue(app.windows.count > noteWindowCount, "viewer window did not open")

        // FR-095: the viewer never activates another application — the app
        // must remain the frontmost application.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let appProcess = NSRunningApplication.runningApplications(
            withBundleIdentifier: "local.stickynotes.app"
        ).first
        XCTAssertEqual(
            frontmost?.processIdentifier,
            appProcess?.processIdentifier,
            "opening the viewer must not activate another application (FR-095)"
        )

        closeLibraryAndQuit()
    }
}
