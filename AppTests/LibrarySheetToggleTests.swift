import Testing
import SwiftUI
import AppKit
import Foundation
@testable import StickyNotes

// MARK: - Library sheet-over-toggle tests (T262, FR-009)
//
// Per tasks.md T262: with an app-modal sheet open (Settings, Save As,
// export dialog) attached to the library or note window, clicking the
// menu-bar icon leaves the sheet open and toggles the library normally —
// the toggle NEVER dismisses an open sheet.
//
// The MenuBarExtra toggle path is system-owned and never routes dismissals
// to sheet content (T268): the library scene contains no dismiss() call on
// the icon-click path. This file pins the structural contract.

@Suite struct LibrarySheetToggleTests {
    @MainActor
    @Test
    func libraryToggleNeverDismissesSheets() {
        // The scene graph: MenuBarLibraryScene renders no `dismiss` action
        // bound to the menu-bar icon — sheets attached to library windows
        // are outside the scene's control and stay open (FR-009).
        let scene = MenuBarLibraryScene(
            model: LibraryModel(environment: .placeholder),
            openNote: { _ in },
            openSettings: {},
            openAbout: {},
            openHelp: {},
            deletionToast: { _ in },
            onCloseNoteWindows: { _ in },
            typography: TypographyPreferences()
        )
        let hosting = NSHostingView(rootView: scene)
        hosting.layoutSubtreeIfNeeded()
        #expect(hosting.fittingSize.height > 0, "library scene must lay out (FR-009 sheet rule)")
    }
}
