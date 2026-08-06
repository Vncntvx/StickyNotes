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
    // framework). The actual composition lands with the foundational
    // services in Phase 2 and is wired into the scenes in Phase 3 (US1).
    @State private var environment: AppEnvironment = .placeholder

    var body: some Scene {
        // The menu-bar library scene (MenuBarLibraryScene) is added in T032.
        // Until then, a minimal MenuBarExtra keeps the app runnable for
        // foundation bring-up.
        MenuBarExtra("Sticky Notes", systemImage: "note.text") {
            Text("Sticky Notes — setup in progress")
                .padding()
            Divider()
            Button("Quit Sticky Notes") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)

        // Note-window scenes (NoteWindowCoordinator) are added in T034.
        // Settings UI (SettingsView) is added in T105.
        // Sync settings (SyncSettingsView) is added in T119.
    }
}
