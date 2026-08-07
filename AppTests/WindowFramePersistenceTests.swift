import Testing
import Foundation
import AppKit
import Domain
import Persistence
import SystemBridge
@testable import StickyNotes

// MARK: - Window frame persistence tests (T289, FR-032/FR-033)
//
// Per tasks.md T289: each note's window size/position is remembered
// device-locally (FR-032) and corrected on display change with the
// disconnected-display preferred frame preserved (FR-033). The repository
// round-trip and the coordinator's restore path are exercised headless-safe
// (real NSWindows, in-memory DB).

@MainActor
@Suite struct WindowFramePersistenceTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000006")!

    private func makeEnvironment() throws -> AppEnvironment {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        return AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.window.\(UUID().uuidString)") ?? .standard)
        )
    }

    @Test
    func windowStateRoundTrips() async throws {
        let env = try makeEnvironment()
        let repo = env.persistence.windowStateRepository!
        // The windowState row references the note (FK cascade); create it.
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        let state = WindowState(
            noteId: noteId,
            frame: WindowFrame(x: 120, y: 300, width: 420, height: 480),
            preferredDisplayUUID: "display-1",
            isOpen: true,
            lastOpenedAt: Date()
        )
        try await repo.upsert(state)
        let fetched = try await repo.fetch(noteId: noteId)
        #expect(fetched != nil)
        #expect(fetched?.frame.x == 120)
        #expect(fetched?.frame.width == 420)
        #expect(fetched?.preferredDisplayUUID == "display-1")
    }

    @Test
    func coordinatorRestoresRememberedFrame() async throws {
        let env = try makeEnvironment()
        let repo = env.persistence.windowStateRepository!
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("createBlankNote failed")
            return
        }
        try await repo.upsert(WindowState(
            noteId: noteId,
            frame: WindowFrame(x: 60, y: 240, width: 360, height: 420),
            preferredDisplayUUID: nil,
            isOpen: false
        ))

        let coordinator = NoteWindowCoordinator(environment: env)
        let window = await coordinator.open(noteId: noteId)
        #expect(window != nil)
        // The remembered frame is applied (restoreFrame runs async; poll).
        var matched = false
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let window {
                let frame = window.frame
                if abs(frame.origin.x - 60) < 1, abs(frame.width - 360) < 1 {
                    matched = true
                    break
                }
            }
        }
        #expect(matched, "the remembered frame is restored on open (FR-032)")
        window?.close()
    }

    @Test
    func displayChangeCorrectsOffScreenFramePreservingPreferred() {
        // FR-033: the correction math keeps the preferred frame for a
        // connected display and falls back only when the display is gone.
        let displays = [
            DisplayFrame(displayUUID: "main", frame: NSRect(x: 0, y: 0, width: 1440, height: 900)),
        ]
        let visible = DisplayChangeBridge.correctedFrame(
            frame: NSRect(x: 3000, y: 3000, width: 400, height: 300),
            preferredDisplayUUID: "main",
            fallbackFrame: nil,
            displays: displays
        )
        #expect(visible.maxX <= 1440, "off-screen frame moved into the visible display")
        #expect(visible.maxY <= 900)
        #expect(visible.width == 400, "size preserved")

        // Disconnected preferred display: fallback frame is used when
        // visible; the preferred frame itself is never mutated.
        let fallback = DisplayChangeBridge.correctedFrame(
            frame: NSRect(x: 3000, y: 3000, width: 400, height: 300),
            preferredDisplayUUID: "gone",
            fallbackFrame: NSRect(x: 100, y: 100, width: 400, height: 300),
            displays: displays
        )
        #expect(fallback.origin == CGPoint(x: 100, y: 100), "fallback frame used for a disconnected display (FR-033)")
    }
}
