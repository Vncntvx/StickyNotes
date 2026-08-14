import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Persistence
import EditorCore
import AssetStore
import SecurityCore
import SyncCore
import SystemBridge

// MARK: - StickyNotesApp (T032/T159/T160/T169 wiring)
//
// The @main entry point: menu-bar library (T159), note windows
// (NoteWindowCoordinator, T160), Settings (T169), About (T144), and
// deep-link routing (contracts/deep-links.md).
//
// FR-009 sheet rule (T268): the menu-bar-icon toggle path never dismisses an
// open app-modal sheet — `MenuBarExtra` natively toggles the library
// WITHOUT touching any sheet content.

@main
struct StickyNotesApp: App {
    // FR-008 (T103): applies the persisted Dock preference at launch.
    // LSUIElement=true in Info.plist makes the app start in accessory mode;
    // the Dock icon is enabled BY DEFAULT unless the user disabled it in
    // Settings (SettingsView's "Show icon in Dock" toggle).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment = .placeholder
    @State private var bootstrapError: BootstrapErrorState?
    @State private var libraryModel: LibraryModel?
    @State private var coordinator: NoteWindowCoordinator?
    @State private var toastPresenter = DeletionToastPresenter()

    var body: some Scene {
        MenuBarExtra("Sticky Notes", systemImage: "note.text") {
            Group {
                if let bootstrapError {
                    bootstrapError.label
                        .padding()
                    Divider()
                    Button("Quit Sticky Notes") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                } else if let libraryModel {
                    MenuBarLibraryScene(
                        model: libraryModel,
                        openNote: { noteId in
                            openNoteWindow(noteId: noteId)
                        },
                        openSettings: {
                            openSettingsWindow()
                        },
                        openAbout: {
                            openAboutWindow()
                        },
                        openHelp: {
                            openHelpWindow()
                        },
                        deletionToast: { message in
                            toastPresenter.present(message: message)
                        },
                        // FR-009a (T305): deleting a note from the library or
                        // Trash closes its open window immediately.
                        onCloseNoteWindows: { noteId in
                            coordinator?.closeAll(noteId: noteId)
                        },
                        // FR-055 (Rev 3): card body previews follow the
                        // user's body font (bootstrap's single instance).
                        typography: environment.typography
                    )
                    .overlay(alignment: .top) {
                        if let toast = toastPresenter.currentToast {
                            DeletionToastOverlay(toast: toast)
                                .padding(.top, 8)
                        }
                    }
                    .frame(width: 420)
                } else {
                    Text("Sticky Notes — setup in progress")
                        .padding()
                    Divider()
                    Button("Quit Sticky Notes") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
            }
            // Bootstrap trigger lives on the CONTENT GROUP (every branch),
            // not inside the `libraryModel` branch — otherwise bootstrap can
            // never start (libraryModel is only set BY bootstrap) and the
            // menu would show "setup in progress" forever.
            .task { bootstrapEnvironment() }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            // Rev 2 (2026-08-14): capture the openSettings environment action
            // so the AppKit dropdown can open the Settings SCENE (scene-first
            // window unification).
            .background {
                OpenSettingsActionCapture { action in
                    settingsSceneOpener = action
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(syncCoordinator: environment.syncCoordinator, typography: environment.typography)
        }
        // Rev 2 (2026-08-14, FR-051): stable shell — default size + minimum
        // constrained resizing. The root content frame (SettingsView) carries
        // the minimums; the numbers live in SettingsWindowPolicy (implementation
        // policy, not spec).
        .defaultSize(
            width: SettingsWindowPolicy.defaultWidth,
            height: SettingsWindowPolicy.defaultHeight
        )
        .windowResizability(.contentMinSize)
        // Polish round 2 (2026-08-14): hide the titlebar page title that
        // duplicates the selected toolbar tab label (General→General). The
        // tab strip is toolbar content and is unaffected.
        .windowToolbarStyle(.unified(showsTitle: false))

        Window("About Sticky Notes", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Sticky Notes Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        // MARK: - Menu commands (003 T011, FR-072/SC-017)
        //
        // Built from MenuCommandCatalog (the SC-017 single source of
        // truth); actions reuse the existing model/coordinator methods and
        // notification-based dispatch — no new command manager.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Sticky Notes") {
                    openAboutWindow()
                }
            }

            CommandGroup(replacing: .appSettings) {
                // Rev 2 (2026-08-14): a single "Settings…" item bound to ⌘,
                // routed through openSettingsWindow() (scene-first). Replaces
                // the system group so exactly one item exists; the system
                // action (showSettingsWindow:) is a no-op for LSUIElement
                // apps on macOS 27 beta (verified 2026-08-08).
                Button("Settings…") {
                    openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    createNoteFromShortcut()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Note from Clipboard") {
                    handleClipboardNoteShortcut()
                }

                Button("New Note from Region Capture") {
                    createNoteAndCapture()
                }

                Button("New Note from Window Capture") {
                    createNoteAndCapture()
                }
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("Move to Trash") {
                    moveFocusedNoteToTrash()
                }
                .keyboardShortcut(KeyEquivalent.delete, modifiers: .command)

                Button("Delete Forever…") {
                    permanentlyDeleteFocusedNote()
                }
            }

            CommandGroup(after: .saveItem) {
                Button("Close Note Window") {
                    closeKeyNoteWindow()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Sort") {
                sortSubmenu()
            }

            // 003 T032 (SC-004): block insertion via Edit/Insert menu
            // commands (the persistent "Add Block" control is removed).
            CommandMenu("Insert") {
                Button("Add Todo") {
                    postInsertion(.stickyRequestInsertTodo)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Add Code Block") {
                    postInsertion(.stickyRequestInsertCode)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()
                Button("Add File Reference…") {
                    postInsertion(.stickyRequestInsertFileReference)
                }
                Button("Capture Screenshot…") {
                    postInsertion(.stickyRequestCaptureScreenshot)
                }
                // 004 T035 (FR-010): the unified image insertion path.
                Button("Insert Image…") {
                    insertImageInKeyWindow()
                }
            }

            // 004 T040 (FR-012): Format menu — the stable formatting entry
            // point (contextual row + shortcuts always work; FR-011).
            CommandMenu("Format") {
                Button("Bold") {
                    coordinator?.applyMarksInKeyWindow([.bold])
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    coordinator?.applyMarksInKeyWindow([.italic])
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Underline") {
                    coordinator?.applyMarksInKeyWindow([.underline])
                }
                .keyboardShortcut("u", modifiers: .command)

                Divider()
                Button("Strikethrough") {
                    coordinator?.applyMarksInKeyWindow([.strikethrough])
                }
                Button("Code Style") {
                    coordinator?.applyMarksInKeyWindow([.inlineCode])
                }

                Divider()
                // FR-043a: whole-note text size, 9–24 (001 semantics).
                Menu("Text Size") {
                    ForEach(NoteAppearance.TextSizeBounds.allSizes, id: \.self) { size in
                        Button("\(size) pt") {
                            coordinator?.setTextSizeInKeyWindow(size)
                        }
                    }
                }
            }

            CommandGroup(after: .toolbar) {
                // 004 T021 (FR-007/FR-026): Always on Top as a menu command
                // (toggle, acting on the key note window).
                Button("Always on Top") {
                    coordinator?.toggleAlwaysOnTopInKeyWindow()
                }

                Button("Search") {
                    focusLibrarySearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Trash") {
                    toggleTrashDestination()
                }

                Button("Show/Hide Note Windows") {
                    toggleNoteWindows()
                }
            }

            CommandGroup(replacing: .help) {
                Button("Help") {
                    openHelpWindow()
                }
            }
        }
    }

    // MARK: - Global-shortcut-derived note creation (menus only)
    //
    // Menu commands (⌘N, "New Note from Clipboard", capture entries) reuse
    // these handlers. Global hotkeys were removed 2026-08-10 — nothing
    // registers Carbon hotkeys at launch anymore; no app shortcut can
    // conflict with other applications.

    /// Creates a blank note (menu ⌘N path; FR-010/FR-120 legacy semantics
    /// — activation + focus preserved).
    private func createNoteFromShortcut() {
        Task { @MainActor in
            guard let libraryModel else { return }
            guard let id = await libraryModel.createBlankNote() else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openNoteWindow(noteId: id)
        }
    }

    /// "New note from clipboard" (menu command): creates a note whose first
    /// rich-text block contains the clipboard contents; activates the app
    /// (FR-007a).
    private func handleClipboardNoteShortcut() {
        Task { @MainActor in
            guard let libraryModel else { return }
            guard let id = await libraryModel.createBlankNote() else { return }
            let clipboardText = NSPasteboard.general.string(forType: .string) ?? ""
            if !clipboardText.isEmpty, let repo = libraryModel.environment.persistence.noteRepository {
                let block = Block(
                    noteId: id,
                    kind: .richText,
                    sortKey: 0,
                    payload: .richText(.plain(clipboardText)),
                    lastModifiedDeviceId: AppDevice.current().id
                )
                try? await repo.insert(block)
            }
            // FR-007a: shortcut/menu creation activates the app.
            NSApplication.shared.activate(ignoringOtherApps: true)
            openNoteWindow(noteId: id)
        }
    }

    /// Region/window capture menu action: creates a new note and captures
    /// into it.
    private func createNoteAndCapture() {
        Task { @MainActor in
            guard let libraryModel else { return }
            guard let id = await libraryModel.createBlankNote() else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openNoteWindow(noteId: id)
        }
    }

    /// Show/hide all open note windows (menu "Show/Hide Note Windows").
    /// 004 T023 (R2): filtered by the window REGISTRY — never by title
    /// (titles are now derived and may repeat/truncate).
    private func toggleNoteWindows() {
        let noteWindows = NoteWindowBridge.allRegistrations().compactMap { _, registration in
            registration.windowRef.window()
        }
        let anyVisible = noteWindows.contains { $0.isVisible }
        for window in noteWindows {
            if anyVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// 004 T035 (FR-010): "Insert Image…" menu command — picks an image and
    /// inserts it into the KEY note window (same host path as the toolbar).
    private func insertImageInKeyWindow() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let host = coordinator?.keyHost() else { return }
        let context = EditorSelectionContext.current(for: host.noteId)
        let target = NoteWindowDerivations.resolveInsertionTarget(blocks: host.blocks, context: context)
        Task { await host.insertImageBlock(url: url, target: target) }
    }

    // MARK: - Bootstrap (T154)

    private func bootstrapEnvironment() {
        // Re-entrancy guard: the bootstrap trigger fires on every menu open;
        // once bootstrapped (or failed), never re-run.
        guard libraryModel == nil, bootstrapError == nil else { return }
        // The sandbox Application Support directory hosts the SQLite
        // database and assets (the App Group container was removed
        // 2026-08-13 with the widget surface).
        let applicationSupportURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        Task {
            do {
                let env = try await AppEnvironment.bootstrap(applicationSupportURL: applicationSupportURL)
                await MainActor.run {
                    environment = env
                    let model = LibraryModel(environment: env)
                    libraryModel = model
                    let coordinator = NoteWindowCoordinator(environment: env)
                    coordinator.deletionToast = { message in
                        toastPresenter.present(message: message)
                    }
                    self.coordinator = coordinator
                    // FR-008: apply the persisted Dock preference (default
                    // on). LSUIElement starts the app accessory; the
                    // AppDelegate path is unreliable on macOS 27 beta
                    // (verified 2026-08-07), so the policy is also applied
                    // here once bootstrap completes.
                    let showDockIcon = UserDefaults.standard
                        .object(forKey: "local.stickynotes.showDockIcon") as? Bool ?? true
                    if showDockIcon {
                        try? DockActivationBridge.setDockEnabled(true)
                    }
                    // 003 T078 (FR-001/FR-006/Constitution X): install the
                    // menu-bar icon right-click/⌥-click dropdown. Plain
                    // left-click continues to toggle the SwiftUI
                    // `MenuBarExtra(.window)` library window (FR-001
                    // semantics unchanged, T018 spike preserved).
                    configureMenuBarDropdown()
                }
            } catch {
                // FR-165: sanitized logging — code + category only, never
                // content, paths, or credentials.
                if let sticky = error as? StickyError {
                    StickyLogger(category: .app).error("bootstrap", stickyError: sticky)
                } else {
                    StickyLogger(category: .app).error("bootstrap", code: "unknown")
                }
                await MainActor.run {
                    bootstrapError = BootstrapErrorState.from(error)
                }
            }
        }
    }

    // MARK: - Note windows (T160)

    private func openNoteWindow(noteId: UUID) {
        guard let coordinator else { return }
        Task { _ = await coordinator.open(noteId: noteId) }
    }

    // MARK: - Menu-bar dropdown (003 T078, FR-001/FR-006/Constitution X)

    /// Configures and installs the menu-bar icon dropdown menu. The dropdown
    /// surfaces 打开 Library / 设置 / 帮助 / 关于 / 退出 on right-click or
    /// ⌥-click of the status-item icon (Constitution-X reachability when the
    /// Dock icon is hidden). Plain left-click is left to the SwiftUI
    /// `MenuBarExtra(.window)` scene (FR-001 semantics unchanged).
    private func configureMenuBarDropdown() {
        // `StickyNotesApp` is the @main struct that lives for the app's
        // entire lifetime; capturing `self` strongly here is safe (no retain
        // cycle — the dropdown singleton is app-scoped, and the struct is
        // owned by SwiftUI for the process lifetime).
        MenuBarDropdownMenu.shared.configure(
            openLibrary: {
                // Re-dispatch a plain click on the status item so SwiftUI's
                // `MenuBarExtra` opens the library window exactly as a
                // left-click would (FR-001 path preserved). Activating the
                // app first ensures the library window comes forward even
                // when the Dock icon is hidden.
                NSApplication.shared.activate(ignoringOtherApps: true)
                self.openLibraryFromDropdown()
            },
            openSettings: { self.openSettingsWindow() },
            openAbout: { self.openAboutWindow() },
            openHelp: { self.openHelpWindow() }
        )
        MenuBarDropdownMenu.shared.install()
    }

    /// Opens the library window from the dropdown's "Open Library" action.
    /// Reuses the same path as a plain left-click on the status item: a
    /// synthetic click on the SwiftUI `MenuBarExtra`'s underlying status
    /// item. Falls back to activating the app (which surfaces the menu-bar
    /// icon for a follow-up click) if the status-item window cannot be
    /// located.
    private func openLibraryFromDropdown() {
        // The SwiftUI MenuBarExtra owns the status item; we cannot click it
        // directly, but activating the app + a best-effort click on the
        // status-item icon window reuses the SwiftUI toggle path.
        guard let statusItemWindow = NSApp.windows.first(where: {
            $0.level == .statusBar && $0.frame.width <= 120 && $0.frame.height <= 40
        }) else {
            // No status-item window found — the library is opened by the
            // user's next left-click. Activate the app so the icon is
            // visible and ready.
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        // Synthesize a left-click at the icon's center to toggle the library
        // (FR-001 left-click semantics). This goes through the SwiftUI
        // MenuBarExtra's own click handling. CGEvent coordinates are
        // Quartz global (origin TOP-LEFT of the main display) while
        // NSWindow.frame is AppKit (origin BOTTOM-LEFT) — the y MUST be
        // flipped or the click lands at the bottom of the screen (verified
        // 2026-08-09: "Open Library" teleported the cursor to the bottom
        // edge and opened nothing).
        let frame = statusItemWindow.frame
        let screenMaxY = statusItemWindow.screen?.frame.maxY
            ?? NSScreen.main?.frame.maxY ?? 0
        let center = CGPoint(
            x: frame.midX,
            y: screenMaxY - frame.midY
        )
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: center, mouseButton: .left)
        click?.post(tap: .cghidEventTap)
        let release = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                              mouseCursorPosition: center, mouseButton: .left)
        release?.post(tap: .cghidEventTap)
    }

    /// The ONE Settings window entry point (Rev 2, 2026-08-14, FR-051).
    ///
    /// The SwiftUI `Settings` scene is the authoritative Settings window and
    /// the ONLY implementation used on this OS: the captured `openSettings`
    /// environment action (macOS 14+) presents it. Verified 2026-08-14 on
    /// this macOS 27 beta build: the scene opens from the menu-bar dropdown
    /// path (the earlier `showSettingsWindow:` selector no-op for
    /// LSUIElement apps — verified 2026-08-08 — does not apply to this
    /// mechanism).
    ///
    /// The NSWindow fallback below exists ONLY for the degenerate case where
    /// the capture view never appeared (the dropdown was used before the
    /// MenuBarExtra content ever presented). It must never be created next
    /// to the scene window: the previous time-based probe produced TWO
    /// Settings windows when the scene presented slower than the probe
    /// window (regression fixed 2026-08-14 by removing the probe entirely).
    @State private var settingsSceneOpener: OpenSettingsAction?

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Reuse any existing settings window (scene- or fallback-created).
        if let existing = NSApp.windows.first(where: {
            $0.title.contains("Settings")
        }) {
            existing.makeKeyAndOrderFront(nil)
            StickyLogger(category: .app).debug("open-settings", code: "existing-window")
            return
        }
        if let opener = settingsSceneOpener {
            opener()
            StickyLogger(category: .app).debug("open-settings", code: "scene-open-requested")
        } else {
            // Degenerate case only — see the documentation comment above.
            createSettingsFallbackWindow()
        }
    }

    /// Degenerate-case fallback: used ONLY when the scene open action was
    /// never captured. Renders the identical `SettingsView` under the
    /// identical geometry policy; guarded against stacking a second window.
    private func createSettingsFallbackWindow() {
        if let existing = NSApp.windows.first(where: { $0.title.contains("Settings") }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: SettingsWindowPolicy.defaultWidth,
                height: SettingsWindowPolicy.defaultHeight
            ),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // Retain ownership (double-release guard — see openAboutWindow).
        window.isReleasedWhenClosed = false
        window.title = "Settings"
        window.minSize = NSSize(
            width: SettingsWindowPolicy.minimumWidth,
            height: SettingsWindowPolicy.minimumHeight
        )
        window.contentView = NSHostingView(
            rootView: SettingsView(syncCoordinator: environment.syncCoordinator, typography: environment.typography)
        )
        window.setFrameAutosaveName("StickyNotesSettings")
        window.center()
        window.makeKeyAndOrderFront(nil)
        StickyLogger(category: .app).debug("open-settings", code: "fallback-created")
    }

    private func openAboutWindow() {
        // Opens the About window scene (fallback: order any existing one
        // front).
        if let window = NSApp.windows.first(where: { $0.title == "About Sticky Notes" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 320, height: 240),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            // Retain ownership: programmatic windows default to
            // `isReleasedWhenClosed = true` — AppKit would release the
            // window on close while the app still references it
            // (double-release crash, verified 2026-08-07).
            window.isReleasedWhenClosed = false
            window.title = "About Sticky Notes"
            window.contentView = NSHostingView(rootView: AboutView())
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens the Help panel (FR-004/FR-008 — reachable from the menu-bar
    /// interface, incl. when the Dock icon is disabled).
    private func openHelpWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Sticky Notes Help" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 220, y: 200, width: 520, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            // Retain ownership (see openAboutWindow — double-release guard).
            window.isReleasedWhenClosed = false
            window.title = "Sticky Notes Help"
            window.contentView = NSHostingView(rootView: HelpView())
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Deep links (contracts/deep-links.md)

    private func handleDeepLink(_ url: URL) {
        guard let action = DeepLinkRouter.action(for: url) else { return }
        switch action {
        case .openNote(let id):
            openNoteWindow(noteId: id)
        case .newNote:
            Task {
                if let id = await libraryModel?.createBlankNote() {
                    openNoteWindow(noteId: id)
                }
            }
        case .search:
            // 003 T025 (D8): `stickynotes://search` opens the library with
            // focus on the search field.
            focusLibrarySearch()
        }
    }

    // MARK: - Menu command actions (003 T011)

    /// Moves the keyboard-focused note card to Trash (FR-024 ⌘⌫ command).
    private func moveFocusedNoteToTrash() {
        guard let model = libraryModel, let focused = model.keyboardSelection else { return }
        Task {
            if await model.trash(noteId: focused) != nil {
                toastPresenter.present(message: String(localized: "Moved to Trash"))
                coordinator?.closeAll(noteId: focused)
            }
        }
    }

    /// Permanently deletes the keyboard-focused note (Trash scope).
    private func permanentlyDeleteFocusedNote() {
        guard let model = libraryModel, let focused = model.keyboardSelection else { return }
        Task {
            if await model.permanentlyDelete(noteId: focused) != nil {
                toastPresenter.present(message: String(localized: "Permanently Deleted"))
                coordinator?.closeAll(noteId: focused)
            }
        }
    }

    /// Closes the key note window (⌘W).
    private func closeKeyNoteWindow() {
        guard let window = NSApp.keyWindow else { return }
        // Find the noteId registered for this window (one window per note).
        let matching = NoteWindowBridge.allRegistrations().first { entry in
            entry.value.windowRef.window() === window
        }
        guard let (noteId, _) = matching else { return }
        window.close()
        NoteWindowBridge.unregister(noteId: noteId)
        coordinator?.releaseWindowDelegate(noteId: noteId)
    }

    /// Opens the library and focuses its search field (⌘F / searchAll /
    /// `stickynotes://search`, 003 T025). The scene consumes the model's
    /// focus-request flag (the T018 NSToolbar spike is concluded — the
    /// focus path is pure model → SwiftUI FocusState).
    private func focusLibrarySearch() {
        if let model = libraryModel {
            model.setSearchFocusRequested(true)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Toggles the Notes/Trash destination (View > Trash).
    private func toggleTrashDestination() {
        guard let model = libraryModel else { return }
        model.setScope(model.scope == .library ? .trash : .library)
    }

    /// The View > Sort submenu (001 FR-022 modes).
    @ViewBuilder
    private func sortSubmenu() -> some View {
        let model = libraryModel
        Button("Recently Modified") { model?.setSort(.modified) }
        Button("Created") { model?.setSort(.created) }
        Button("Title") { model?.setSort(.title) }
        Button("Manual") { model?.setSort(.manual) }
    }

    /// Posts a block-insertion request to the KEY note window (Edit/Insert
    /// menu, 003 T032 — the coordinator dispatches to the focused host).
    private func postInsertion(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

/// Captures the `openSettings` environment action (macOS 14+) from inside
/// the MenuBarExtra scene content so AppKit-side entry points (the
/// menu-bar dropdown) can present the SwiftUI Settings scene.
private struct OpenSettingsActionCapture: View {
    @Environment(\.openSettings) private var openSettings
    let onCapture: (OpenSettingsAction) -> Void

    var body: some View {
        Color.clear
            .onAppear { onCapture(openSettings) }
    }
}

/// User-visible bootstrap failure state. Carries only a sanitized,
/// non-sensitive message — no note content, paths, or SQL fragments
/// (constitution VI; plan §Diagnostics).
struct BootstrapErrorState {
    let label: Text

    static func from(_ error: Error) -> BootstrapErrorState {
        let code: String
        if let sticky = error as? StickyError {
            code = sticky.sanitizedCode
        } else {
            code = "unknown"
        }
        return BootstrapErrorState(
            label: Text("Sticky Notes could not open its database (\(code)). Quit and relaunch, or restore from a backup.")
        )
    }
}

// MARK: - AppDelegate (FR-008 Dock preference at launch)

/// AppKit delegate: applies the persisted Dock-icon preference once the
/// application finishes launching (FR-008 — the Dock icon is enabled by
/// default and may be disabled in Settings; LSUIElement=true starts the app
/// in accessory mode, so the preference must be applied explicitly).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StickyLogger(category: .app).debug("did-finish-launching", code: "fired")
        // FR-008: Dock icon enabled by default, disabled only by the user
        // in Settings. LSUIElement=true starts the app in accessory mode, so
        // the persisted preference must be applied explicitly.
        let showDockIcon = UserDefaults.standard
            .object(forKey: "local.stickynotes.showDockIcon") as? Bool ?? true
        if showDockIcon {
            try? DockActivationBridge.setDockEnabled(true)
        }
        // Launch-time container diagnostics (FR-011a): verify the sandbox
        // Application Support directory is resolvable + writable BEFORE the
        // menu bootstrap runs, so sandbox issues surface in logs immediately.
        Task {
            guard let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                StickyLogger(category: .app).error("container-url", code: "unresolved")
                return
            }
            do {
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                let probe = base.appendingPathComponent("launch-probe.tmp")
                try Data("probe".utf8).write(to: probe)
                try? FileManager.default.removeItem(at: probe)
                StickyLogger(category: .app).debug("container-writable", code: "ok")
            } catch {
                StickyLogger(category: .app).error("container-writable", code: "denied")
            }
        }
    }
}
