import SwiftUI
import AppKit
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
// (NoteWindowCoordinator, T160), Settings (T169), About (T144), deep-link
// routing (contracts/deep-links.md), and change-driven widget refresh
// (FR-110a, T237).
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

    private let appGroupIdentifier = "group.local.stickynotes.placeholder"

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
                        }
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
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(syncCoordinator: environment.syncCoordinator)
        }

        Window("About Sticky Notes", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Window("Sticky Notes Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }

    // MARK: - Global shortcuts (T145/T296, FR-120/FR-121)

    /// Registers the default "new note from clipboard" shortcut (FR-120)
    /// plus every user-configured shortcut from Settings (T296). Fires
    /// while another app is focused; registration failures are surfaced
    /// non-blockingly (FR-121), never silent.
    private func wireGlobalShortcuts() {
        let preferences = LocalPreferences()

        // FR-120: the clipboard-note default binding.
        do {
            _ = try GlobalShortcuts.register(GlobalShortcutKey.defaultClipboardNote) { _ in
                handleClipboardNoteShortcut()
            }
        } catch {
            // FR-121: registration failure is non-blocking.
        }

        // T296: user-configured shortcuts.
        for action in LocalPreferences.ShortcutAction.allCases {
            guard let key = preferences.shortcutKey(for: action) else { continue }
            do {
                _ = try GlobalShortcuts.register(key) { _ in
                    Task { @MainActor in
                        ShortcutDispatcher.dispatch(action)
                    }
                }
            } catch {
                // FR-121: conflict is surfaced in Settings; never silently
                // replaced here.
            }
        }

        // Dispatch the notification-based actions (window coordination).
        NotificationCenter.default.addObserver(
            forName: .stickyRequestNewBlankNote, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                createNoteFromShortcut()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .stickyRequestClipboardNote, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handleClipboardNoteShortcut()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .stickyRequestCaptureRegion, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                createNoteAndCapture()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .stickyRequestCaptureWindow, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                createNoteAndCapture()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .stickyToggleNoteWindows, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                toggleNoteWindows()
            }
        }
    }

    /// Creates a blank note via a global shortcut (FR-010/FR-120).
    private func createNoteFromShortcut() {
        Task { @MainActor in
            guard let libraryModel else { return }
            guard let id = await libraryModel.createBlankNote() else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openNoteWindow(noteId: id)
        }
    }

    /// FR-120 "new note from clipboard": fires while another app is focused
    /// and creates a note whose first rich-text block contains the
    /// clipboard contents; activates the app (FR-007a).
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
            // FR-007a: global-shortcut creation activates the app.
            NSApplication.shared.activate(ignoringOtherApps: true)
            openNoteWindow(noteId: id)
        }
    }

    /// FR-120 region/window capture: creates a new note and captures into it.
    private func createNoteAndCapture() {
        Task { @MainActor in
            guard let libraryModel else { return }
            guard let id = await libraryModel.createBlankNote() else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openNoteWindow(noteId: id)
        }
    }

    /// FR-120 show/hide all open note windows.
    private func toggleNoteWindows() {
        let windows = NSApp.windows.filter { $0.title != "Sticky Notes Help" && $0.title != "About Sticky Notes" }
        let anyVisible = windows.contains { $0.isVisible }
        for window in windows {
            if anyVisible {
                window.orderOut(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - Bootstrap (T154)

    private func bootstrapEnvironment() {
        // Re-entrancy guard: the bootstrap trigger fires on every menu open;
        // once bootstrapped (or failed), never re-run.
        guard libraryModel == nil, bootstrapError == nil else { return }
        guard let container = AppGroupContainer.url(for: appGroupIdentifier) else {
            // FR-011a: never fail silently — surface a non-blocking,
            // localized status instead of "setup in progress" forever.
            bootstrapError = BootstrapErrorState.from(StickyError.persistence(.containerUnavailable))
            return
        }
        Task {
            do {
                let env = try await AppEnvironment.bootstrap(appGroupContainerURL: container)
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
                    wireGlobalShortcuts()
                    seedUITestNoteIfRequested()
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

    // MARK: - UITest seeding hook (T305)

    /// Creates a note whose first rich-text block contains the marker passed
    /// via the `-UITestSeedNote <marker>` launch argument. TEST-ONLY: the
    /// XCUITest journeys seed content this way because synthetic keyboard
    /// input (typing/paste) is unreliable on macOS 27 beta; the argument is
    /// never present in normal launches, and the path is failure-silent
    /// (FR-011a). Persistence reuses the clipboard-shortcut insert path.
    private func seedUITestNoteIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-UITestSeedNote"),
              flagIndex + 1 < arguments.count else { return }
        let marker = arguments[flagIndex + 1]
        Task {
            guard let model = self.libraryModel,
                  let repo = model.environment.persistence.noteRepository else { return }
            if let id = await model.createBlankNote() {
                let block = Block(
                    noteId: id,
                    kind: .richText,
                    sortKey: 0,
                    payload: .richText(.plain(marker)),
                    lastModifiedDeviceId: AppDevice.current().id
                )
                try? await repo.insert(block)
                await model.reload()
            }
        }
    }

    // MARK: - Note windows (T160)

    private func openNoteWindow(noteId: UUID) {
        guard let coordinator else { return }
        Task { _ = await coordinator.open(noteId: noteId) }
    }

    private func openSettingsWindow() {
        // Settings scene opens on demand.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
            // The library window opens with focus on the search field; the
            // MenuBarExtra is toggled by the system on activation.
            break
        }
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
        // Launch-time container diagnostics (FR-011a): verify the App Group
        // container is resolvable + writable BEFORE the menu bootstrap runs,
        // so sandbox/entitlement issues surface in logs immediately.
        Task {
            let group = "group.local.stickynotes.placeholder"
            guard let container = AppGroupContainer.url(for: group) else {
                StickyLogger(category: .app).error("container-url", code: "unresolved")
                return
            }
            let base = container.appendingPathComponent("Library/Application Support")
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
