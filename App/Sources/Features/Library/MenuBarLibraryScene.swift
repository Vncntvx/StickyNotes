import SwiftUI
import AppKit
import Domain
import SystemBridge

// MARK: - MenuBarLibraryScene (003 US1, T019-T027)
//
// Per tasks.md T019-T027 and spec FR-001..FR-007/SC-005..SC-008/FR-021/
// FR-023/FR-024/FR-026:
// - SINGLE native toolbar (AppKit NSToolbar attached via the window probe,
//   T018 spike decision — plan.md §14/§15): New Note (⌘N), search
//   (NSSearchField), sort popup, Notes/Trash destination. The legacy
//   stacked header (big new-note block + segmented control + sort row) is
//   removed (T019).
// - No bottom bar / footer (FR-006): Help/About/Settings/Quit move to
//   menus (T011 CommandGroups), toolbar overflow, and the menu-bar icon
//   dropdown (T024). Quit never appears in app UI (Constitution X).
// - Content area: adaptive card grid per FR-021 (NoteCardMetrics) with
//   density bounds 72-128 (SC-022); keyboard navigation (FR-024); Trash
//   destination with Empty Trash + single permanent-delete confirmations
//   (FR-026); sync attention banner above the grid (T026 shell, complete
//   in US5).
// - FR-001a positioning (probe) unchanged: click-outside-close +
//   4pt/left-edge alignment free from MenuBarExtra semantics.

/// The menu-bar library scene content (wired into `MenuBarExtra`).
public struct MenuBarLibraryScene: View {
    @Bindable var model: LibraryModel
    let openNote: (UUID) -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void
    let openHelp: () -> Void
    /// FR-009a deletion toast presenter hook (T246): receives the localized
    /// deletion outcome message ("Moved to Trash" / "Permanently Deleted").
    let deletionToast: (String) -> Void
    /// FR-009a (T246/T305): closes any open window(s) of a note the moment
    /// it is deleted from the library or Trash.
    let onCloseNoteWindows: (UUID) -> Void

    public init(
        model: LibraryModel,
        openNote: @escaping (UUID) -> Void,
        openSettings: @escaping () -> Void = {},
        openAbout: @escaping () -> Void = {},
        openHelp: @escaping () -> Void = {},
        deletionToast: @escaping (String) -> Void = { _ in },
        onCloseNoteWindows: @escaping (UUID) -> Void = { _ in }
    ) {
        self.model = model
        self.openNote = openNote
        self.openSettings = openSettings
        self.openAbout = openAbout
        self.openHelp = openHelp
        self.deletionToast = deletionToast
        self.onCloseNoteWindows = onCloseNoteWindows
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Content area (the toolbar is attached to the NSWindow by the
            // probe — FR-002 single native toolbar row).
            SyncAttentionBanner(
                presentation: model.bannerPresentation,
                dismiss: { model.dismissBanner() },
                action: { model.performBannerAction() }
            )

            LibraryCardGrid(model: model, openNote: openNote, onTrash: { noteId in
                Task {
                    if await model.trash(noteId: noteId) != nil {
                        deletionToast(String(localized: "Moved to Trash"))
                        onCloseNoteWindows(noteId)
                    }
                }
            }, onRestore: { noteId in
                Task { await model.restore(noteId: noteId) }
            }, onPermanentlyDelete: { noteId in
                Task {
                    // FR-026: single permanent delete is CONFIRMED in the
                    // Trash destination view; the model performs the action.
                    if await model.permanentlyDelete(noteId: noteId) != nil {
                        deletionToast(String(localized: "Permanently Deleted"))
                        onCloseNoteWindows(noteId)
                    }
                }
            })
                .frame(minWidth: 340, minHeight: 320, idealHeight: 480)
        }
        .frame(width: 420)
        // FR-001a (T286): position the library window deterministically
        // when it appears AND attach the native toolbar (T018 spike).
        .background(MenuBarLibraryWindowProbe(
            model: model,
            openNote: openNote
        ))
        .task { await model.reload() }
    }
}

// MARK: - FR-001a window placement probe + toolbar attachment (T286/T018)

/// Applies the FR-001a library-window frame as soon as the view gains its
/// hosting window (MenuBarExtra presentation): left edge aligned with the
/// status-item icon, clamped to the visible screen frame, 4 pt below the
/// menu bar, NO animation. ALSO attaches the native library toolbar (003
/// T018 spike decision — plan.md §14/§15): the toolbar lives on the
/// window, so the content area below it is the pure grid + banner.
public struct MenuBarLibraryWindowProbe: NSViewRepresentable {
    let model: LibraryModel
    let openNote: (UUID) -> Void

    public init(model: LibraryModel, openNote: @escaping (UUID) -> Void) {
        self.model = model
        self.openNote = openNote
    }

    public func makeNSView(context: Context) -> NSView {
        let view = ProbeView(model: model, openNote: openNote)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        private let model: LibraryModel
        private let openNote: (UUID) -> Void

        init(model: LibraryModel, openNote: @escaping (UUID) -> Void) {
            self.model = model
            self.openNote = openNote
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MenuBarLibraryWindow.positionLibraryWindow(window)
            // T018 spike: attach the native toolbar once per window.
            _ = LibraryToolbar.attach(to: window, model: model, openNote: openNote)
        }
    }
}

// MARK: - FR-001a window placement (T255)

/// Applies the FR-001a library window frame when the MenuBarExtra window
/// appears: left edge aligned with the status-item icon's left edge, clamped
/// to the visible screen frame, 4 pt below the menu bar, NO animation.
@MainActor
public enum MenuBarLibraryWindow {
    /// Finds the status item's icon frame (best-effort) and applies the
    /// computed library frame to the given window.
    public static func positionLibraryWindow(_ window: NSWindow, windowSize: NSSize? = nil) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let iconFrame = Self.statusItemIconFrame(on: screen) ?? NSRect(
            x: visible.maxX - 60,
            y: visible.maxY,
            width: 24,
            height: 22
        )
        positionLibraryWindow(
            window,
            iconFrame: iconFrame,
            windowSize: windowSize ?? window.frame.size
        )
    }

    /// Applies the FR-001a library-window frame from an EXPLICIT icon frame
    /// (T304): the deterministic core of `positionLibraryWindow`. The
    /// environment-dependent status-item resolution (above) is kept separate
    /// so the frame application is testable in isolation — the result must
    /// not depend on which status-item windows exist at test time. Product
    /// behavior is unchanged: the resolved icon frame (real status item when
    /// found, deterministic fallback otherwise) is fed through here.
    public static func positionLibraryWindow(
        _ window: NSWindow,
        iconFrame: NSRect,
        windowSize: NSSize
    ) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: iconFrame,
            visibleScreenFrame: visible,
            windowSize: windowSize
        )
        // FR-001a: no animation — set the frame directly.
        window.setFrame(frame, display: true, animate: false)
    }

    /// Best-effort status-item icon frame (the status bar is not directly
    /// addressable; the rightmost 32pt of the menu bar is a reliable
    /// approximation for a right-aligned status item).
    private static func statusItemIconFrame(on screen: NSScreen) -> NSRect? {
        guard let menuBarWindow = NSApp.windows.first(where: { window in
            guard window.className.contains("StatusBarWindow") ||
                  window.isFloatingPanel == false && window.level == .statusBar else {
                return false
            }
            // Only a status-ITEM-sized window is usable: the menu-bar
            // window itself spans the full bar (origin at the screen's
            // left edge), which would mis-place the library (FR-001a
            // deterministic positioning).
            guard window.frame.width <= 120, window.frame.height <= 40 else { return false }
            // The status-bar window may live on a different display
            // (multi-display setups), where its frame is in a different
            // coordinate space. Only use it when it is actually on the
            // target screen.
            guard let statusScreen = window.screen, statusScreen === screen else { return false }
            return true
        }) else {
            return nil
        }
        return menuBarWindow.frame
    }
}
