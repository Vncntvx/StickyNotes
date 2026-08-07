import Testing
import Foundation
import os
import Domain
import Persistence
import WidgetKit
@testable import StickyNotes

// MARK: - Change-driven widget refresh tests (T294, FR-110a)
//
// Per tasks.md T294: every widget-affecting write (note created/edited/
// deleted/trashed/restored, todo toggled, widget-eligibility changed,
// conflict copy created) reloads EXACTLY the affected widget kinds; no
// fixed polling exists. The reload sink is overridden for observation.

@MainActor
@Suite struct WidgetRefreshTests {

    private static let deviceId = UUID(uuidString: "d0000000-0000-4000-8000-000000000013")!

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
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.widgets.\(UUID().uuidString)") ?? .standard)
        )
    }

    /// Thread-safe recorder for the reload override (Sendable).
    private final class ReloadSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [[WidgetRefreshCoordinator.Kind]] = []
        func record(_ kinds: [WidgetRefreshCoordinator.Kind]) {
            lock.lock(); defer { lock.unlock() }
            calls.append(kinds)
        }
        func snapshot() -> [[WidgetRefreshCoordinator.Kind]] {
            lock.lock(); defer { lock.unlock() }
            return calls
        }
    }

    /// Installs the spy as the reload sink for the duration of the body.
    private func withReloadSpy(_ body: (ReloadSpy) async throws -> Void) async throws {
        let spy = ReloadSpy()
        WidgetRefreshCoordinator.reloadOverride = { kinds in spy.record(kinds) }
        defer { WidgetRefreshCoordinator.reloadOverride = nil }
        try await body(spy)
    }

    @Test
    func noteCreationReloadsNoteAffectedKinds() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        try await withReloadSpy { spy in
            _ = await model.createBlankNote()
            let calls = spy.snapshot()
            #expect(!calls.isEmpty, "create triggers a reload (FR-110a)")
            if let first = calls.first {
                #expect(first == WidgetRefreshCoordinator.kindsAffectedByNoteChange())
                #expect(!first.contains(.smallSelected), "unaffected kinds are never reloaded (FR-110a)")
                #expect(!first.contains(.mediumTodo))
            }
        }
    }

    @Test
    func todoToggleReloadsTodoAffectedKinds() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("create failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        try await withReloadSpy { spy in
            guard let blockId = await host.insertTodoBlock() else {
                Issue.record("insert failed")
                return
            }
            await host.setTodoComplete(blockId: blockId, isComplete: true)
            let calls = spy.snapshot()
            let todoKinds = calls.filter { $0 == WidgetRefreshCoordinator.kindsAffectedByTodoToggle() }
            #expect(!todoKinds.isEmpty, "todo toggle reloads the todo kinds (FR-110a)")
        }
    }

    @Test
    func eligibilityChangeReloadsEligibilityKinds() async throws {
        let env = try makeEnvironment()
        let model = LibraryModel(environment: env)
        guard let noteId = await model.createBlankNote() else {
            Issue.record("create failed")
            return
        }
        let host = NoteWindowHostModel(noteId: noteId, environment: env)
        await host.load()
        try await withReloadSpy { spy in
            guard var note = host.note else {
                Issue.record("note missing")
                return
            }
            note.widgetEligible = false
            host.updateAppearance(note)
            try await Task.sleep(nanoseconds: 100_000_000)
            let calls = spy.snapshot()
            #expect(calls.contains { $0 == WidgetRefreshCoordinator.kindsAffectedByEligibilityChange() },
                    "eligibility change reloads the eligibility kinds (FR-112/FR-110a)")
        }
    }

    @Test
    func changeMappingIsExact() {
        // FR-110a: affected-kind mapping never reloads unaffected kinds.
        let noteKinds = WidgetRefreshCoordinator.kindsAffectedByNoteChange()
        #expect(noteKinds == [.smallRecent, .mediumMulti, .largeOverview, .quickCreate])
        let todoKinds = WidgetRefreshCoordinator.kindsAffectedByTodoToggle()
        #expect(todoKinds == [.mediumTodo, .mediumMulti, .largeOverview])
        let eligibilityKinds = WidgetRefreshCoordinator.kindsAffectedByEligibilityChange()
        #expect(eligibilityKinds == [.smallSelected, .mediumMulti, .largeOverview, .quickCreate])
        let conflictKinds = WidgetRefreshCoordinator.kindsAffectedByConflictCopy()
        #expect(conflictKinds == [.largeOverview, .mediumMulti])
    }
}
