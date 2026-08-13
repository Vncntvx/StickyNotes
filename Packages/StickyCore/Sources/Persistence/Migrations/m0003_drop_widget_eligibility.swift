import Foundation
import GRDB
import Domain

// MARK: - Migration v3: drop widget eligibility (2026-08-13)
//
// The per-note widget-eligibility column existed solely as the widget
// privacy gate (FR-112). The entire widget surface and the App Group
// container were removed (user decision 2026-08-13 — see spec.md US8 note),
// so the column is dropped.
//
// Historical migrations v1/v2 are immutable (constitution IV): a fresh
// database creates the column in v1 and drops it here in v3 — the cost of
// never rewriting shipped migration bodies. `eraseDatabaseOnSchemaChange`
// (DEBUG) does not fire because only this NEW migration is added; existing
// v1/v2 bodies are untouched, so development databases migrate in place
// with rows preserved.

/// Extends the migrator with the v3 widget-eligibility column drop.
public enum WidgetEligibilityRemovalSchema {
    public static func migrateV3(_ db: Database) throws {
        // SQLite supports ALTER TABLE ... DROP COLUMN since 3.35 (2021);
        // GRDB bundles a recent SQLite, and the deployment floor is macOS 26.
        try db.execute(sql: "ALTER TABLE note DROP COLUMN widgetEligible")
    }
}
