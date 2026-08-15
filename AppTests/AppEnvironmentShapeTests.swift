import Testing
import Foundation
@testable import StickyNotes

// MARK: - R3.1 AppEnvironment shape tests (T004)
//
// Structure assertion (remediation roadmap 2026-08-15 R3.1, D-2/D-3): the
// composition root must expose ONLY slots that are actually consumed.
// Five empty service groupings (DomainServices/EditorServices/
// SecurityServices/SyncServices/SystemBridgeServices) and the unused
// localPreferences slot are dead weight — the environment claims "services"
// that hold nothing and are never dereferenced.

@Suite struct AppEnvironmentShapeTests {
    @Test
    func environmentExposesOnlyConsumedSlots() {
        let members = Mirror(reflecting: AppEnvironment.placeholder)
            .children
            .compactMap { $0.label }
        let actual = Set(members)
        // R3.1: only the genuinely consumed slots may remain — persistence
        // (repos/search), assets (asset store), syncCoordinator (status +
        // sync actions), typography (global font preference).
        let expected: Set<String> = [
            "persistence", "assets", "syncCoordinator", "typography",
        ]
        #expect(actual == expected,
                "AppEnvironment must expose only consumed slots; got \(members.sorted())")
    }
}
