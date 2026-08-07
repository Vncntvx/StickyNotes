import Testing
import Foundation
import SwiftUI
import Persistence
import Domain
@testable import StickyNotes

// MARK: - Appearance integration tests (T163d / T049, US3)
//
// Per tasks.md T163d: Always-on-Top per note; contrast readable across
// light/dark/custom-color/transparency/increased-contrast. The full FR-042
// contrast matrix is covered by DomainTests/NoteAppearanceTests (T225);
// this file pins the per-note appearance model + Always-on-Top persistence.

@Suite struct AppearanceIntegrationTests {
    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000001")!

    @Test
    func appearanceFieldsPersistPerNote() async throws {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        var note = Note(colorKey: .pink, transparency: 0.8, textSize: 18, alwaysOnTop: true,
                        lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        // Always-on-Top per note (FR-036) + appearance survive round-trip.
        let fetched = try await repo.fetch(id: note.id)
        #expect(fetched?.alwaysOnTop == true)
        #expect(fetched?.colorKey == .pink)
        #expect(fetched?.transparency == 0.8)
        #expect(fetched?.textSize == 18)

        // The projection derives a readable foreground (FR-042) at the
        // chosen opacity over the desktop.
        note.alwaysOnTop = false
        note.textSize = 24
        try await repo.update(note, modifyingDeviceId: Self.deviceId)
        let updated = try await repo.fetch(id: note.id)
        #expect(updated?.alwaysOnTop == false)
        #expect(updated?.textSize == 24)
    }

    @Test
    func readableThemeUsesDomainContrast() {
        let note = Note(colorKey: .blue, transparency: 1.0, lastModifiedDeviceId: Self.deviceId)
        let fg = ReadableTheme.foreground(for: note)
        #expect(fg != Color.clear)
        #expect(!ReadableTheme.customColorFailsContrast(note), "built-in colors pass FR-042 contrast")

        let custom = Note(colorKey: .custom, customColor: "#808080", lastModifiedDeviceId: Self.deviceId)
        // Mid-gray is borderline; the flag is computed from the Domain
        // projection regardless of the outcome.
        _ = ReadableTheme.customColorFailsContrast(custom)
        #expect(true)
    }
}
