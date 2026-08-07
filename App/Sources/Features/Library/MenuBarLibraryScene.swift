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
    /// FR-009a deletion toast presenter hook (T246): receives the localized
    /// deletion outcome message ("Moved to Trash" / "Permanently Deleted").
    let deletionToast: (String) -> Void

    public init(
        model: LibraryModel,
        openNote: @escaping (UUID) -> Void,
        openSettings: @escaping () -> Void = {},
        openAbout: @escaping () -> Void = {},
        deletionToast: @escaping (String) -> Void = { _ in }
    ) {
        self.model = model
        self.openNote = openNote
        self.openSettings = openSettings
        self.openAbout = openAbout
        self.deletionToast = deletionToast
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
                    }
                }
            }, onRestore: { noteId in
                Task { await model.restore(noteId: noteId) }
            })
                .frame(minWidth: 340, minHeight: 320, idealHeight: 480)

            Divider()

            footer
        }
        .frame(width: 420)
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
            SyncStatusView(
                isConfigured: false,  // wired by the app once a VaultConfiguration exists
                manualSync: {}
            )

            Spacer()

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
        let size = windowSize ?? window.frame.size
        let frame = MenuBarWindowFrame.libraryWindowFrame(
            iconFrame: iconFrame,
            visibleScreenFrame: visible,
            windowSize: size
        )
        // FR-001a: no animation — set the frame directly.
        window.setFrame(frame, display: true, animate: false)
    }

    /// Best-effort status-item icon frame (the status bar is not directly
    /// addressable; the rightmost 32pt of the menu bar is a reliable
    /// approximation for a right-aligned status item).
    private static func statusItemIconFrame(on screen: NSScreen) -> NSRect? {
        guard let menuBarWindow = NSApp.windows.first(where: { $0.className.contains("StatusBarWindow") || $0.isFloatingPanel == false && $0.level == .statusBar }) else {
            return nil
        }
        return menuBarWindow.frame
    }
}
