import Testing
import Foundation
import Domain
import Persistence
@testable import StickyNotes

// MARK: - Offline-completeness + dependency audit (T261, FR-142/FR-143/FR-190)
//
// Per tasks.md T261: (a) network failures MUST NEVER block local editing
// (FR-142); (b) Package.resolved contains only GRDB + the audited Argon2id
// package; no analytics/telemetry SDKs or developer-service endpoints exist
// in code (FR-143/FR-190).

@Suite struct OfflineCompletenessTests {
    @MainActor
    @Test
    func localEditingNeverDependsOnNetwork() async throws {
        // FR-142 gate (R3.10): the P1 flow (create/edit/trash/restore)
        // must complete against the local store with NO sync layer at all
        // — a real behavioral run, not a by-construction claim. An
        // unconfigured environment constructs no SyncCore provider, so no
        // network dependency can be reached.
        let store = try DatabaseStore.inMemory()
        try InitialSchema.migrator().migrate(store.dbPool)
        let model = LibraryModel(environment: AppEnvironment(
            persistence: PersistenceServices(store: store),
            assets: AssetServices()
        ))
        #expect(model.syncCoordinator == nil, "no sync layer when unconfigured (FR-142)")
        guard let id = await model.createBlankNote() else {
            Issue.record("offline create must succeed (FR-142)")
            return
        }
        _ = await model.trash(noteId: id)
        await model.reload()
        #expect(model.cards.isEmpty, "trashed note leaves the library offline")
        await model.restore(noteId: id)
        await model.reload()
        #expect(model.cards.contains { $0.noteId == id }, "restore succeeds offline")
    }

    @Test
    func dependencyManifestIsMinimal() throws {
        // The package manifest + resolved file live in Packages/StickyCore
        // (AppTests/… → repo root, then Packages/StickyCore).
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/StickyCore")
        let resolved = packageRoot.appendingPathComponent("Package.resolved")
        guard let data = try? Data(contentsOf: resolved),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pins = (json["pins"] as? [[String: Any]]) ?? (json["object"] as? [String: Any])?["pins"] as? [[String: Any]] else {
            Issue.record("Package.resolved must exist and parse")
            return
        }
        let identities = pins.compactMap { $0["identity"] as? String }
        // FR-143/FR-190: only GRDB + SwiftArgon2 are approved dependencies.
        let allowed: Set<String> = ["grdb.swift", "argon2-swift"]
        for identity in identities {
            #expect(allowed.contains(identity), "unapproved dependency: \(identity)")
        }
        #expect(!identities.isEmpty)
    }
}
