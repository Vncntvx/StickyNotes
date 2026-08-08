import SwiftUI
import AppKit
import Domain
import SystemBridge

// MARK: - MenuBarLibraryScene (T159/T268/T269/T255)
//
// Per tasks.md T159/T268/T269/T255 and spec FR-001/FR-003/FR-004/FR-009/
// FR-009a/FR-011a/FR-014a/FR-031a:
// - Window-style MenuBarExtra library with search/sort/new/Trash/sync-
//   status/Settings/Help/Quit affordances.
// - FR-009 re-click behavior: MenuBarExtra natively toggles (focus if not
//   focused, dismiss if focused, never a second window). The toggle path
//   NEVER dismisses an open app-modal sheet (FR-009 sheet rule, T268).
// - FR-001a positioning (T255): left edge aligned with the icon's left
//   edge, clamped, 4 pt below the menu bar, NO animation — applied when the
//   window appears.
// - FR-011a (T269): library actions never crash; failures surface as a
//   non-blocking localized status message; the library stays usable and
//   permits retry.

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
    /// it is deleted from the library or Trash. Wired to
    /// `NoteWindowCoordinator.closeAll` by the App layer.
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
            header
            Divider()

            LibrarySearchView(model: model)
                .padding(10)

            Divider()

            LibraryCardGrid(model: model, openNote: openNote, onTrash: { noteId in
                Task {
                    if await model.trash(noteId: noteId) != nil {
                        deletionToast(String(localized: "Moved to Trash"))
                        // FR-009a: an open window closes immediately.
                        onCloseNoteWindows(noteId)
                    }
                }
            }, onRestore: { noteId in
                Task { await model.restore(noteId: noteId) }
            }, onPermanentlyDelete: { noteId in
                Task {
                    // FR-014: Delete Forever removes the note beyond Trash
                    // recovery (T305 — previously mis-routed to onTrash).
                    if await model.permanentlyDelete(noteId: noteId) != nil {
                        deletionToast(String(localized: "Permanently Deleted"))
                        // FR-009a: an open window closes immediately.
                        onCloseNoteWindows(noteId)
                    }
                }
            })
                .frame(minWidth: 340, minHeight: 320, idealHeight: 480)

            Divider()

            footer
        }
        .frame(width: 420)
        // FR-001a (T286): position the library window deterministically when
        // it appears — left-edge aligned with the icon, clamped, 4 pt below
        // the menu bar, no animation.
        .background(MenuBarLibraryWindowProbe())
        .task { await model.reload() }
    }

    // MARK: - Header (new note, Trash scope, sync status)

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    if let id = await model.createBlankNote() {
                        openNote(id)
                    }
                }
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Create a new note")

            Spacer()

            Picker("", selection: Binding(
                get: { model.scope },
                set: { model.setScope($0) }
            )) {
                Label("Notes", systemImage: "square.grid.2x2").tag(LibraryModel.Scope.library)
                Label("Trash", systemImage: "trash").tag(LibraryModel.Scope.trash)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Footer (sync status, Settings/Help/About/Quit)

    private var footer: some View {
        HStack(spacing: 6) {
            // FR-004/FR-014a (T284): real sync state from the coordinator —
            // "not configured" ONLY when sync is genuinely unconfigured;
            // status/error + manual sync when configured.
            let sync = model.syncCoordinator
            SyncStatusView(
                isConfigured: sync?.isConfigured ?? false,
                lastSuccessfulSyncAt: sync?.lastSuccessfulSyncAt,
                lastErrorCode: sync?.lastErrorCode,
                isInProgress: sync?.isInProgress ?? false,
                manualSync: {
                    Task { await sync?.manualSync() }
                }
            )

            Spacer()

            Button {
                openHelp()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .help("Help")
            .accessibilityLabel("Help")

            Button {
                openAbout()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .help("About Sticky Notes")
            .accessibilityLabel("About Sticky Notes")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - FR-001a window placement probe (T286)

/// Applies the FR-001a library-window frame as soon as the view gains its
/// hosting window (MenuBarExtra presentation): left edge aligned with the
/// status-item icon, clamped to the visible screen frame, 4 pt below the
/// menu bar, NO animation.
public struct MenuBarLibraryWindowProbe: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                MenuBarLibraryWindow.positionLibraryWindow(window)
            }
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
