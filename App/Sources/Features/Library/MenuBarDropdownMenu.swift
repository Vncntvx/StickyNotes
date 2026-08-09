import AppKit
import SwiftUI

// MARK: - MenuBarDropdownMenu (003 T078, FR-001/FR-006/US1-AC7/Constitution X)
//
// Per tasks.md T078 and spec FR-001/FR-006/US1-AC7/Constitution X:
// right-click (or ⌥-click) on the menu-bar status-item icon MUST present
// a dropdown menu with 打开 Library / 设置 / 帮助 / 关于 / 退出. Left-click
// keeps opening the Library window (FR-001 semantics unchanged — the
// SwiftUI `MenuBarExtra(.window)` scene continues to own left-click).
//
// Vehicle choice (T078 options, consistent with the T018 spike):
//   (1) secondary `NSStatusItem` menu  — would create a second menu-bar icon
//   (2) `rightMouseDown`/⌥-click handling on the MenuBarExtra icon  ← chosen
//   (3) SwiftUI `MenuBarExtra` dual-interaction pattern — not exposed by API
//
// Option (2) is the least invasive: an `NSEvent` local monitor detects
// right-mouse-down and ⌥-left-mouse-down whose location falls within the
// app's own status-item icon window. SwiftUI's `MenuBarExtra` continues to
// handle plain left-clicks (FR-001 library window toggle — T018 spike
// decision preserved). The dropdown is an `NSMenu` built from the five
// required items, each wired to the existing window-opening closures
// (`openSettings`/`openAbout`/`openHelp`) reused from `MenuBarLibraryScene`,
// plus a Quit action and an "Open Library" action that re-dispatches a
// plain click to the status item.
//
// Constitution X guarantee: when the Dock icon is hidden (LSUIElement),
// Settings/About/Help/Quit remain reachable via this dropdown — they are
// no longer in the removed Library footer (FR-006/T024) and the standard
// app-menu bar is unavailable to accessory apps.

/// Owns the menu-bar icon dropdown menu (T078). Install once at app launch;
/// uninstalls on deinit. Idempotent: calling `install()` twice is a no-op.
@MainActor
final class MenuBarDropdownMenu {
    /// Shared singleton — the dropdown is app-global (one status-item icon).
    static let shared = MenuBarDropdownMenu()

    private var monitor: Any?

    /// The closures invoked by the dropdown items. Set via `configure(...)`
    /// before `install()`; reconfigured whenever the app state changes (e.g.
    /// after bootstrap completes and `libraryModel` becomes available).
    private var openLibrary: () -> Void = {}
    private var openSettings: () -> Void = {}
    private var openAbout: () -> Void = {}
    private var openHelp: () -> Void = {}

    private init() {}

    /// Configures the action closures. Call before `install()` and whenever
    /// the underlying model/windows change (the closures are captured by the
    /// menu items at popup time, so a re-configure takes effect on the next
    /// right-click).
    func configure(
        openLibrary: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openAbout: @escaping () -> Void,
        openHelp: @escaping () -> Void
    ) {
        self.openLibrary = openLibrary
        self.openSettings = openSettings
        self.openAbout = openAbout
        self.openHelp = openHelp
    }

    /// Installs the event monitor (idempotent). The monitor watches for
    /// right-mouse-down and ⌥-left-mouse-down events whose window is the
    /// app's status-item icon window, and pops the dropdown menu.
    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    /// Removes the event monitor (idempotent).
    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    // MARK: - Event handling

    /// Returns the (possibly consumed) event. Returns `nil` to consume.
    private func handle(_ event: NSEvent) -> NSEvent? {
        // Right-click anywhere on the menu bar's status-item icon → dropdown.
        // ⌥-left-click on the status-item icon → dropdown (FR-001 alternative).
        let isRightClick = event.type == .rightMouseDown
        let isOptionLeftClick = event.type == .leftMouseDown
            && event.modifierFlags.contains(.option)
        guard isRightClick || isOptionLeftClick else { return event }

        // Only intercept clicks on the app's own status-item icon window
        // (a small window at `.statusBar` level). Other right-clicks (cards,
        // the library content area, edit fields) MUST pass through unchanged
        // — FR-024 card context menu, editor context menu, etc.
        guard let targetWindow = event.window,
              isStatusItemIconWindow(targetWindow) else {
            return event
        }

        // Pop the dropdown anchored to the status-item icon (FR-001a
        // positioning semantics: below the icon, left-aligned with it).
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: targetWindow.frame.midX,
                                                  y: targetWindow.frame.minY - 4),
                   in: nil)
        // Consume the right-click so the system does not also dismiss the
        // library or show a system menu. ⌥-left-click is also consumed to
        // prevent SwiftUI's `MenuBarExtra` from toggling the library window
        // (FR-001 left-click semantics preserved for plain left-clicks).
        return nil
    }

    /// Best-effort detection of the app's own status-item icon window. The
    /// SwiftUI `MenuBarExtra(.window)` scene creates a small `NSWindow` at
    /// `.statusBar` level for the icon (distinct from the library window
    /// itself, which is a popover-style window). The detection reuses the
    /// same heuristic as `MenuBarLibraryWindow.statusItemIconFrame` so the
    /// two paths agree on which window represents the icon.
    private func isStatusItemIconWindow(_ window: NSWindow) -> Bool {
        guard window.level == .statusBar else { return false }
        // The status-ITEM icon window is small (≤ 120×40 pt). The full menu
        // bar itself spans the screen and is excluded.
        guard window.frame.width <= 120, window.frame.height <= 40 else { return false }
        // The library popover window is much larger and at a different level;
        // it never matches the two filters above.
        return true
    }

    // MARK: - Menu construction

    /// Builds the five-item dropdown (FR-001/FR-006/Constitution X):
    /// 打开 Library / 设置 / 帮助 / 关于 / 退出.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem("Open Library", action: #selector(menuOpenLibrary)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeItem("Settings…", action: #selector(menuOpenSettings)))
        menu.addItem(makeItem("About Sticky Notes", action: #selector(menuOpenAbout)))
        menu.addItem(makeItem("Help", action: #selector(menuOpenHelp)))
        menu.addItem(NSMenuItem.separator())
        let quit = makeItem("Quit Sticky Notes", action: #selector(menuQuit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        // The items target a disposable proxy (the actions are forwarded to
        // the configured closures via `MenuBarDropdownDispatcher`). Using a
        // proxy avoids retaining `self` in the menu items and lets the menu
        // be built fresh on every popup (closures always reflect the latest
        // `configure(...)` state).
        let dispatcher = MenuBarDropdownDispatcher(owner: self)
        for item in menu.items where item.action != nil {
            item.target = dispatcher
        }
        // Retain the dispatcher for the lifetime of this menu; released when
        // the menu deallocates after dismissal.
        objc_setAssociatedObject(menu, &MenuBarDropdownMenu.dispatcherKey, dispatcher, .OBJC_ASSOCIATION_RETAIN)
        return menu
    }

    private func makeItem(_ title: String, action: Selector) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: "")
    }

    // MARK: - Menu actions (called via the dispatcher proxy)

    @objc fileprivate func menuOpenLibrary() {
        openLibrary()
    }

    @objc fileprivate func menuOpenSettings() {
        openSettings()
    }

    @objc fileprivate func menuOpenAbout() {
        openAbout()
    }

    @objc fileprivate func menuOpenHelp() {
        openHelp()
    }

    @objc fileprivate func menuQuit() {
        NSApplication.shared.terminate(nil)
    }

    // Associated-object storage key for the dispatcher (retained for the
    // menu's lifetime).
    private static var dispatcherKey: UInt8 = 0
}

/// Disposable target for the dropdown menu items. Forwards each action to
/// the owning `MenuBarDropdownMenu` (and thence to the configured closures).
@MainActor
private final class MenuBarDropdownDispatcher: NSObject {
    private weak var owner: MenuBarDropdownMenu?

    init(owner: MenuBarDropdownMenu) {
        self.owner = owner
        super.init()
    }

    @objc func menuOpenLibrary() { owner?.menuOpenLibrary() }
    @objc func menuOpenSettings() { owner?.menuOpenSettings() }
    @objc func menuOpenAbout() { owner?.menuOpenAbout() }
    @objc func menuOpenHelp() { owner?.menuOpenHelp() }
    @objc func menuQuit() { owner?.menuQuit() }
}
