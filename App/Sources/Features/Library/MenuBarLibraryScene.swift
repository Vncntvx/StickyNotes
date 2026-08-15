import SwiftUI
import AppKit
import Domain
import Persistence
import SystemBridge

// MARK: - MenuBarLibraryScene (003 US1, T019-T027)
//
// Per tasks.md T019-T027 and spec FR-001..FR-007/SC-005..SC-008/FR-021/
// FR-023/FR-024/FR-026:
// - SINGLE compact control row inside the panel (方案 B — T018 spike
//   concluded 2026-08-09): New Note (⌘N), search (FR-003 prompt updates),
//   sort popup, Notes/Trash destination. The spike's 方案 A (AppKit
//   NSToolbar attached via the window probe) was abandoned: on macOS 27
//   beta the SwiftUI `MenuBarExtraWindow` (borderless, private class)
//   reserves the toolbar strip but never draws items — verified with
//   items=5/isVisible=true under three variations (plain attach;
//   +toolbarStyle/titlebarAppearsTransparent/hidden title; +styleMask
//   `.titled`/-`.fullSizeContentView`). The SwiftUI row renders in the
//   panel's own content, the same path as the card grid, so controls are
//   guaranteed visible; FR-001a positioning / click-outside-close are
//   untouched (probe reverts to position-only).
// - No bottom bar / footer (FR-006): Help/About/Settings/Quit move to
//   menus (T011 CommandGroups), the toolbar overflow, and the menu-bar icon
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
    /// FR-055 (Rev 3): the global typography observable — threaded to the
    /// card grid so the card body preview follows the user's body font.
    let typography: TypographyPreferences

    public init(
        model: LibraryModel,
        openNote: @escaping (UUID) -> Void,
        openSettings: @escaping () -> Void = {},
        openAbout: @escaping () -> Void = {},
        openHelp: @escaping () -> Void = {},
        deletionToast: @escaping (String) -> Void = { _ in },
        onCloseNoteWindows: @escaping (UUID) -> Void = { _ in },
        typography: TypographyPreferences = TypographyPreferences()
    ) {
        self.model = model
        self.openNote = openNote
        self.openSettings = openSettings
        self.openAbout = openAbout
        self.openHelp = openHelp
        self.deletionToast = deletionToast
        self.onCloseNoteWindows = onCloseNoteWindows
        self.typography = typography
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Two compact control rows (方案 B — the NSToolbar spike
            // cannot render on the MenuBarExtra window, see header): the
            // four T019 items cannot share one 420 pt row — sort menu +
            // destination segmented alone need ~300 pt, starving the
            // search field. The pre-T019 two-row split (header / search
            // strip) is restored, proven to render in this window.
            headerRow
            SeparatorLine()

            searchRow
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

            SeparatorLine()

            // Sync attention banner above the grid (T026 shell, complete
            // in US5).
            SyncAttentionBanner(
                presentation: model.bannerPresentation,
                dismiss: { model.dismissBanner() },
                action: { model.performBannerAction() }
            )

            // R1.10 (remediation roadmap 2026-08-14): the FR-011a error
            // surface (statusMessage/isError) was written on every library
            // failure but never rendered — every failure was silently
            // swallowed. Non-blocking banner, dismissible like the sync
            // notice.
            if let message = model.statusMessage {
                errorBanner(message: message, dismiss: { model.dismissStatusMessage() })
            }

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
            }, typography: typography)
                .frame(minWidth: 340, minHeight: 320, idealHeight: 480)
        }
        .frame(width: 420)
        // FR-001a (T286): position the library window deterministically
        // when it appears.
        .background(MenuBarLibraryWindowProbe())
        .task {
            await model.reload()
            model.refreshBanner()
        }
    }

    /// A 1 pt hairline separator between the control rows and the content.
    /// `Divider()` is NOT used here: on macOS 27 beta it renders inside a
    /// borderless MenuBarExtra window as a thick accent-tinted bar (verified
    /// 2026-08-09 — a ~3.5 pt solid strip instead of a 1 pt line), a
    /// framework rendering quirk this window cannot opt out of. A neutral
    /// hairline keeps FR-080 separator semantics without fighting the
    /// system glass rim.
    /// R1.10 (remediation roadmap 2026-08-14): the FR-011a non-blocking
    /// library error banner. Mirrors the sync notice's geometry; errors
    /// are dismissible and never block the grid.
    private func errorBanner(message: String, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: AppMetrics.rowSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: AppMetrics.bannerTextSize))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss library error")
        }
        .padding(AppMetrics.contentInset)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: AppMetrics.surfaceRadius))
        .padding(.horizontal, AppMetrics.contentInset)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Library error: \(message)")
    }

    private struct SeparatorLine: View {
        var body: some View {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
        }
    }

    // MARK: - Control rows (T019/T020/T021, FR-002/FR-003/FR-022)

    /// Row 1 — New Note (⌘N) + Notes/Trash destination. Mirrors the T018
    /// spike's NSToolbar item set as plain SwiftUI inside the panel (the
    /// guaranteed-rendering fallback after the NSToolbar spike failed on
    /// the MenuBarExtra window, macOS 27 beta).
    private var headerRow: some View {
        HStack(spacing: 10) {
            Button {
                Task {
                    if let id = await model.createBlankNote() {
                        openNote(id)
                    }
                }
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Create a new note")
            .accessibilityLabel("New Note")

            Spacer(minLength: 0)

            Picker("", selection: Binding(
                get: { model.scope },
                set: { model.setScope($0) }
            )) {
                Text("Notes").tag(LibraryModel.Scope.library)
                Text("Trash").tag(LibraryModel.Scope.trash)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Notes / Trash destination")

            // FR-014b (003 T183 Rev 3): Empty Trash lives in a header "⋯"
            // menu, Trash scope only — the grid never shifts between Notes
            // and Trash. The destructive item requests the shared in-window
            // confirmation (FR-026); disabled while Trash is empty.
            if model.scope == .trash {
                Menu {
                    Button("Empty Trash…", role: .destructive) {
                        model.requestEmptyTrashConfirmation()
                    }
                    .disabled(model.cards.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .help("More trash actions")
                .accessibilityLabel("More trash actions")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Row 2 — native search field (FR-003/003a Rev 3: NSSearchField
    /// bridge; ⌘F focus via `model.searchFocusRequested`) + sort popup
    /// (001 FR-022 modes).
    private var searchRow: some View {
        HStack(spacing: 10) {
            searchField

            Picker("", selection: Binding(
                get: { model.sort },
                set: { model.setSort($0) }
            )) {
                Text("Recently Modified").tag(NoteSortKey.modified)
                Text("Created").tag(NoteSortKey.created)
                Text("Title").tag(NoteSortKey.title)
                Text("Manual").tag(NoteSortKey.manual)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Sort")
        }
    }

    /// The NATIVE search field (FR-003/003a Rev 3, T184) — NSSearchField
    /// bridged through NSViewRepresentable (system icon/clear/behaviors),
    /// replacing the hand-drawn TextField + quaternary background. The
    /// reload contract is unchanged: the binding writes `model.searchQuery`
    /// and the `.onChange` performs the debounce-free immediate reload
    /// (FR-024/024a). ⌘F / deep-link focus requests are consumed by the
    /// bridge (`focusRequested` → first responder → flag reset).
    private var searchField: some View {
        LibrarySearchField(
            text: $model.searchQuery,
            focusRequested: model.searchFocusRequested,
            onFocusConsumed: { model.setSearchFocusRequested(false) }
        )
        .onChange(of: model.searchQuery) { _, newValue in
            // FR-024a prompt updates: debounce-free immediate reload
            // (in-memory filter, well under 100 ms).
            model.setSearchQuery(newValue)
        }
        .frame(maxWidth: .infinity)
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
        // R3.6 (A-10): window identification is single-sourced in
        // `MenuBarWindowFrame.isStatusItemIconWindow`; the extra
        // className/floating-panel clauses were redundant (the level+size
        // predicate already excludes the full menu bar and the library
        // window). The on-screen display check stays (coordinate space).
        guard let menuBarWindow = NSApp.windows.first(where: { window in
            guard MenuBarWindowFrame.isStatusItemIconWindow(window) else { return false }
            guard let statusScreen = window.screen, statusScreen === screen else { return false }
            return true
        }) else {
            return nil
        }
        return menuBarWindow.frame
    }
}
