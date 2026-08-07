import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - P1 independence gate tests (T135a, SC-009)
//
// Run all P1 acceptance scenarios (US1–US6) with sync disabled, no widgets
// configured, no screenshots captured, no screen-recording permission
// granted; assert each P1 story is independently demonstrable. Covered by
// AppLogicTests.p1FeaturesWorkWithoutP2P3Configuration (US1–US6 lifecycle
// with an unconfigured environment). File exists for task→file traceability.

@MainActor
@Suite struct P1IndependenceGateTests {
    @Test
    func p1LifecycleWithoutP2P3Configuration() async throws {
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let env = AppEnvironment(
            domain: DomainServices(),
            persistence: PersistenceServices(store: store),
            editor: EditorServices(),
            assets: AssetServices(),
            security: SecurityServices(),
            sync: SyncServices(),
            systemBridge: SystemBridgeServices(),
            localPreferences: LocalPreferences(defaults: UserDefaults(suiteName: "test.p1.\(UUID().uuidString)") ?? .standard)
        )
        let model = LibraryModel(environment: env)
        guard let id = await model.createBlankNote() else {
            Issue.record("P1 create must work with no P2/P3 configured")
            return
        }
        await model.reload()
        #expect(model.cards.contains { $0.noteId == id })
    }
}
