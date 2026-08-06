import SwiftUI
import Domain
import Persistence
import EditorCore
import AssetStore
import SecurityCore
import SyncCore
import SystemBridge

// MARK: - App entry point
//
// T024 (Phase 2): a small `AppEnvironment` with explicit-initializer DI
// (composed services, no DI framework). The real scene wiring lands in US1
// (Phase 3) per tasks.md T032.
//
// This file is the @main entry point stub. It compiles in a full Xcode 26.x
// install; the menu-bar library scene (MenuBarLibraryScene), note windows,
// and feature views are added per tasks.md Phase 3+.

@main
struct StickyNotesApp: App {
    // AppEnvironment is composed at startup via explicit-initializer DI
    // (plan §State management and concurrency; constitution XIII — no DI
    // framework). `bootstrap` runs the T154 startup sequence: interrupted-
    // migration recovery → open DatabasePool → migrate (backup + integrity
    // check). A bootstrap failure is fatal-on-launch: the app must not run
    // against an inconsistent database (constitution IV, X). The failure is
    // surfaced as a user-visible state rather than silently swallowed so the
    // user can act (free disk space, restore backup, contact support) instead
    // of operating against a stale placeholder environment.
    @State private var environment: AppEnvironment = .placeholder
    @State private var bootstrapError: BootstrapErrorState?

    private let appGroupIdentifier = "group.local.stickynotes.placeholder"

    var body: some Scene {
        // The menu-bar library scene (MenuBarLibraryScene) is added in T032.
        // Until then, a minimal MenuBarExtra keeps the app runnable for
        // foundation bring-up.
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
            .task {
                bootstrapEnvironment()
            }
        }
        .menuBarExtraStyle(.window)

        // Note-window scenes (NoteWindowCoordinator) are added in T034.
        // Settings UI (SettingsView) is added in T105.
        // Sync settings (SyncSettingsView) is added in T119.
    }

    private func bootstrapEnvironment() {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            // No App Group container: stay on the placeholder environment.
            // The app remains runnable for bring-up; real persistence
            // requires the container (T005).
            return
        }
        Task {
            do {
                let env = try await AppEnvironment.bootstrap(appGroupContainerURL: container)
                environment = env
            } catch {
                // Constitution IV, X: never run against an inconsistent DB.
                // Surface the failure (sanitized code only — no content,
                // paths, or SQL fragments leak) instead of leaving the app
                // on a placeholder that silently looks healthy.
                bootstrapError = BootstrapErrorState.from(error)
            }
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
