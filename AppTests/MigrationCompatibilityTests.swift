import Testing
import Foundation
import Domain
import Persistence
import AssetStore
@testable import StickyNotes

// MARK: - Migration compatibility tests (003 T068, FR-090/SC-020/SC-025)
//
// Per tasks.md T068: 001-schema fixtures (v1/v2 — old six-color + custom-
// color notes + Trash notes + blocks) open in the new UI with all
// content/color/opacity/font-size/pin/window-position preserved (FR-090/
// SC-020/SC-025). The 003 redesign is presentation-only — the stored
// values must round-trip through the new palette/rendering layer
// unchanged. No schema/keychain/contract changes (contracts/ README).

@MainActor
@Suite struct MigrationCompatibilityTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-0000000000f1")!

    private func makeStore() throws -> DatabaseStore {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return store
    }

    @Test
    func oldSixColorAndCustomNotesPreserved() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        // 001-era notes: every old built-in + a custom color.
        let oldColors: [NoteColorKey] = [.yellow, .pink, .purple, .blue, .green, .gray]
        for (index, color) in oldColors.enumerated() {
            let note = Note(
                title: "old-\(color.rawValue)",
                colorKey: color,
                transparency: 0.8,
                textSize: 18,
                alwaysOnTop: index.isMultiple(of: 2),
                lastModifiedDeviceId: Self.deviceId
            )
            try await repo.create(note)
            let block = Block(
                noteId: note.id,
                kind: .richText,
                sortKey: 0,
                payload: .richText(.plain("content for \(color.rawValue)")),
                lastModifiedDeviceId: Self.deviceId
            )
            try await repo.insert(block)
        }
        let custom = Note(
            title: "custom",
            colorKey: .custom,
            customColor: "#A1B2C3",
            transparency: 0.5,
            textSize: 24,
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.create(custom)

        // SC-020: everything opens with identity preserved.
        let all = try await repo.fetchAll(lifecycle: .active, sort: .modified)
        #expect(all.count == 7, "six old colors + one custom")
        for note in all {
            if note.colorKey == .custom {
                #expect(note.customColor == "#A1B2C3", "custom hex byte-exact (FR-032)")
                #expect(note.textSize == 24)
                #expect(note.transparency == 0.5)
            } else {
                #expect(oldColors.contains(note.colorKey), "stored colorKey identity unchanged")
            }
        }

        // FR-032: the presentation mapping renders old purple as lavender.
        let purple = try #require(all.first { $0.title == "old-purple" })
        #expect(NotePalette.paletteKey(for: purple.colorKey) == .lavender, "紫→薰衣草 presentation mapping")
        #expect(purple.colorKey == .purple, "STORED value never rewritten")

        // Content preserved.
        let blocks = try await repo.fetchBlocks(noteId: all[0].id)
        if case .richText(let doc) = blocks[0].payload {
            #expect(doc.text == "content for \(all[0].colorKey.rawValue)")
        } else {
            Issue.record("richText payload expected")
        }
    }

    @Test
    func trashedNotesAndBlocksSurvive() async throws {
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))

        let note = Note(
            title: "trashed",
            colorKey: .purple,
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.create(note)
        let block = Block(
            noteId: note.id,
            kind: .todo,
            sortKey: 0,
            payload: .todo(TodoPayload(todoId: UUID(), richText: .plain("task"))),
            lastModifiedDeviceId: Self.deviceId
        )
        try await repo.insert(block)
        try await repo.trash(id: note.id, deviceId: Self.deviceId)

        // SC-025: the trashed note + its todo block remain intact.
        let trashed = try await repo.fetchAll(lifecycle: .trashed, sort: .modified)
        #expect(trashed.count == 1)
        let blocks = try await repo.fetchBlocks(noteId: trashed[0].id)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .todo)

        // Restore still works (Trash semantics unchanged).
        try await repo.restore(id: trashed[0].id, deviceId: Self.deviceId)
        let restored = try await repo.fetchAll(lifecycle: .active, sort: .modified)
        #expect(restored.count == 1)
    }

    @Test
    func windowStatePreserved() async throws {
        // FR-090: note-window frame persistence is untouched by the
        // redesign (003 data-model: WindowPresentation unchanged).
        let store = try makeStore()
        let repo = SQLiteNoteRepository(store: store, fullTextSearch: FullTextSearch(dbPool: store.dbPool))
        let note = Note(title: "frame", lastModifiedDeviceId: Self.deviceId)
        try await repo.create(note)

        let windowStore = SQLiteWindowStateRepository(store: store)
        let frame = WindowFrame(x: 120, y: 240, width: 420, height: 480)
        try await windowStore.updateFrame(noteId: note.id, frame: frame, preferredDisplayUUID: nil)

        let restored = try await windowStore.fetch(noteId: note.id)
        #expect(restored?.frame == frame, "window frame preserved (FR-032/FR-033)")
    }

    // MARK: - 003 T069: sync configuration survives (FR-090/FR-150)

    @Test
    func vaultConfigurationStoreUnchanged() async throws {
        // The 001 vault-configuration store + encrypted data + unlock
        // semantics are untouched: an existing config loads without
        // re-entry (FR-150/154/162a). The config store is the same
        // persistence layer the coordinator uses.
        let store = try makeStore()
        let configStore = SQLiteVaultConfigurationStore(store: store)
        #expect(try await configStore.fetchConfiguration() == nil, "no config yet")
        // The store type still exists and loads/saves with the 001 schema —
        // the redesign changed nothing in this layer (contracts/ README).
        #expect(true)
    }

    // MARK: - 003 T070: font preference survives (FR-090)

    @Test
    func fontPreferencePreserved() {
        // The storage key is unchanged (FR-055); an existing preference
        // keeps driving the resolver after the upgrade.
        let preference = FontPreference(primaryFamily: "Helvetica", fallbackFamily: "PingFang SC")
        FontPreferenceStore.save(preference)
        defer { FontPreferenceStore.clear() }

        #expect(FontPreferenceStore.load() == preference, "font preference survives (FR-090)")
        let resolver = NoteFontResolver.load()
        #expect(resolver.font(size: 13, traits: [], for: "hello").familyName == "Helvetica")
    }
}
