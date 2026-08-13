# Quickstart: Join Existing Vault (Cross-Device Sync)

**Feature**: 002-join-existing-vault | **Date**: 2026-08-08 | **Plan**: [plan.md](./plan.md)

Validation/run guide for the join-existing-vault feature. This is NOT an
implementation document; implementation details live in `tasks.md`.

## Required environment

Same as 001 (see `specs/001-sticky-notes-app/quickstart.md`): macOS 26+
target, Xcode 26.x (local dev machine uses Xcode-beta; every build/test MUST
be prefixed with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`),
Swift 6 language mode, strict concurrency.

## Build & test

```bash
# StickyCore package suites (all 7 module suites + join/schema tests):
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore

# App target + AppTests (SyncCompositionTests JoinExistingVault suite,
# SyncProfileExportTests, LocalizationCompletenessTests):
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'
```

Key suites for this feature:

- `Packages/StickyCore/Tests/SyncCoreTests/SyncProfileSchemaTests.swift` —
  schema v1/v2 compat, unsupported versions fail (T001).
- `Packages/StickyCore/Tests/SyncCoreTests/RemoteLayoutTests.swift` —
  deterministic bootstrap object name, create == join (T002).
- `Packages/StickyCore/Tests/SecurityCoreTests/JoinBootstrapTests.swift` —
  wrong password / corrupt / wrong vault fail closed (T005/T006).
- `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) — join
  success + bidirectional first sync, missing bootstrap, wrong password,
  no local/remote mutation on failure, off-main-actor, perf (T008-T010/T021).
- `AppTests/SyncProfileExportTests.swift` — export content boundary (no
  secrets), import v1/v2, corrupt/unsupported fail closed (T013/T014).

## Multi-Mac walkthrough (SC-001 / CHK033 — manual validation)

Two Macs (A = creates the vault, B = joins). Both run the app from the same
build above, configured with the same WebDAV or S3-compatible repository
(loopback/local server works for development).

1. **On A — create**: open Sync Settings → **Create new vault** → enter
   provider config + a new vault password → create. Wait for first sync to
   complete; status row shows the provider + last sync time. Note the vault
   locator (shown in settings).
2. **On A — export**: in the configured sync state, **Export Sync Profile…**
   → save the `.json` (schema v2) — verify the file contains protocol,
   locator, redacted connection info (endpoint/prefix) and A's device name,
   and NO password/credentials/keys (open in a text editor).
3. **Transfer**: AirDrop / shared drive / messenger — user's choice.
4. **On B — import**: open Sync Settings → **Join existing vault** →
   **Import from file…** → pick A's profile. Provider + locator fill
   automatically; B's device name shown ("from <A's name>"); enter the vault
   password (same as A's).
5. **On B — join**: submit. Join succeeds; status rows show provider + last
   sync; a new note created on B appears on A after sync (and vice versa).
6. **On B — failure paths** (each MUST fail closed): wrong password →
   "wrong synchronization password"; locator of a nonexistent vault →
   "vault not found"; no local config written (settings still show the
   pre-join state).

**Expected outcome**: device B joins A's vault with a manual locator OR an
imported profile in ≤3 minutes (SC-001); first sync of <100 notes converges
bidirectionally in ≤1 minute (SC-002); wrong password / wrong locator produce
no local or remote writes (SC-003); the exported file contains no secrets
(SC-004).

## Contract references

- Schema v2 delta: `contracts/sync-profile-v2-delta.md` (authoritative schema
  file: `../001-sticky-notes-app/contracts/sync-profile-export.schema.json`).
- Reused read-only: `../001-sticky-notes-app/contracts/vault-bootstrap.schema.json`
  (join fetch/verify), encrypted-envelope/manifest, note-document, tombstone.
- Data model: `data-model.md` (no DB schema change; single-config replace,
  fail-closed state transitions).
