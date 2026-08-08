# Migration fixtures

Historical schema-version SQLite databases (one per schema version, e.g.
`schema_v1.sqlite`) land here per Constitution IV / tasks.md T153. The
fixtures are built deterministically by the migration tests themselves
(`MigrationTests.swift` builds historical schemas in-memory); checked-in
binary fixtures are added only when a historical schema can no longer be
reconstructed from the migration chain.

NEVER contains real note content, credentials, or secrets (constitution VI).
