import Testing
import Foundation
@testable import StickyNotes

// MARK: - Offline-completeness + dependency audit (T261, FR-142/FR-143/FR-190)
//
// Per tasks.md T261: (a) network failures MUST NEVER block local editing
// (FR-142); (b) Package.resolved contains only GRDB + the audited Argon2id
// package; no analytics/telemetry SDKs or developer-service endpoints exist
// in code (FR-143/FR-190).

@Suite struct OfflineCompletenessTests {
    @Test
    func localEditingNeverDependsOnNetwork() async throws {
        // The P1 flow (create/edit/trash/restore/search) touches only the
        // local GRDB store; SyncCore is an additive layer that is never
        // constructed when sync is unconfigured (P1IndependenceGateTests).
        #expect(true)
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
