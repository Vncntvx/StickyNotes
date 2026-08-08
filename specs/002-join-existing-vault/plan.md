# Implementation Plan: Join Existing Vault (Cross-Device Sync)

**Branch**: `002-join-existing-vault` | **Date**: 2026-08-08 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-join-existing-vault/spec.md`

**Note**: This feature reuses the entire sync infrastructure built in feature 001
(StickyCore SyncCore/SecurityCore, WebDAV/S3 adapters, conflict handling,
tombstones, offline reconciliation). It adds ONLY: (a) a "join existing vault"
configuration mode (manual locator + sync-profile export/import), (b) the
sync-profile schema v2 with a readable origin-device name, (c) the
verify-join bootstrap path, and (d) — because 001 stores no remote bootstrap
today — an ADDITIVE create-path bootstrap upload + WebDAV locator addressing
(containerPath includes the locator, mirroring S3). No encryption format,
manifest, or conflict semantics change.

## Summary

Second-Mac onboarding for the 001 encrypted sync: device B joins the vault
created on device A by pointing at the same repository, providing the vault
locator (typed manually or imported from a sync-profile file) and the same
synchronization password. The join is fail-closed (wrong password / missing
bootstrap / wrong vault never writes local config or remote data), reuses the
existing SyncEngine for bidirectional sync, and uploads the joining device's
local notes encrypted into the vault on first sync. The sync-profile export
carries a readable origin-device name (schema v2, backward compatible with v1).

## Technical Context

**Language/Version**: Swift 6 (language mode 6, strict concurrency) — identical
to 001.

**Primary Dependencies**: Existing 001 stack only — GRDB (Persistence), the
audited Argon2id package (SecurityCore), CryptoKit, URLSession (SyncCore
WebDAV/S3 adapters). No new dependencies (Constitution XIII).

**Storage**: Existing App Group SQLite (vaultConfiguration / syncState tables,
001 m0001/m0002 schema). The join persists the SAME single-configuration row
(replace semantics per 001 FR-154). Keychain holds the receiving device's own
credentials (never imported).

**Testing**: Swift Testing (StickyCore) + AppTests — join-verify paths against
the in-memory provider (001 SyncCompositionTests pattern), schema v1/v2
round-trips, fail-closed vectors, import validation. Constitution XII: tests
FIRST.

**Target Platform**: macOS 26+ (unchanged from 001).

**Constraints**: Exactly one vault configuration per device (001 FR-150/154).
Bootstrap is READ-ONLY during join (no remote mutation). No developer-operated
services (FR-143). All Constitution VII/VIII guarantees (fail closed, wrong
password no lockout FR-160e, 30-day tombstones, long-offline reconciliation
FR-174) are inherited — the join path must not weaken them.

## Architecture

### Join flow (SyncCoordinator extension)

```
joinExistingVault(providerType, endpoint, containerPath/bucket/region,
                  vaultLocator, credentials, vaultPassword)
  1. Build provider (makeProvider, existing) — READ-ONLY connectivity probe
     (fetchMetadata on the manifest name / HEAD; NO MKCOL — FR-003 forbids
     remote writes during join; WebDAV verify() creates the container).
  2. FETCH remote bootstrap by vaultLocator (READ-ONLY):
       provider.fetch(objectName: bootstrapObjectName(locator))
     - notFound  → fail closed "vault not found" (no local/remote writes).
     - parse failure / wrongVault context → fail closed (checkBootstrap reuse).
  3. openRemoteBootstrap(bootstrap, password, expectedVaultId?) — existing
     SecurityCore openVault internals:
     - wrong password → key-confirmation mismatch → fail closed,
       distinguishable message (FR-160d(a)).
  4. Persist configuration (existing configStore.saveConfiguration —
     001-style single-row replace; local notes untouched).
  5. wireEngine + runSync() immediately (user decision: auto sync after join):
     local notes upload encrypted (existing uploadNote), remote notes download;
     conflicts → existing ConflictResolver; tombstones respected.
```

### Bootstrap object name

001 stores no remote bootstrap today: `createVault` produces the bootstrap
in-memory and only the manifest (fixed object name `"manifest"`) is uploaded
remotely. The manifest is encrypted with the vault MASTER key — recoverable
only from the bootstrap — so a second device cannot decrypt anything without
a remote bootstrap object.

002 therefore ADDS (additive remote object; Constitution IV-compliant):

1. `RemoteLayout.bootstrapObjectName(for locator:)` — deterministic name for
   the bootstrap object (e.g. `bootstrap` under the locator prefix), shared by
   create and join. Lives in Domain (`RemoteManifest.swift`), where
   `RemoteLayout` already lives.
2. **Create path bootstrap upload** (`SyncCoordinator.configure`): after
   `createVault`, upload the bootstrap JSON under
   `bootstrapObjectName(locator)` BEFORE the first sync, so the join path can
   fetch it. Fail closed: any error leaves local config unwritten.
3. **WebDAV locator addressing**: WebDAV's container path must include the
   locator (`containerPath = "<prefix>/<locator>"`, same scheme as S3), so a
   join by locator addresses the same remote location on both providers and
   vaults on one container path stay isolated (today WebDAV ignores the
   locator — two vaults would collide on the shared `"manifest"` object).
   Applied identically in create and join (makeProvider).

The join fetches the bootstrap under the SAME name the create path uploaded —
consistency is a compile-time guarantee via the shared function.

### Sync-profile schema v2 (contract change, backward compatible)

`specs/001-sticky-notes-app/contracts/sync-profile-export.schema.json`:
- `schemaVersion` stays numeric; NEW version 2 adds the OPTIONAL
  `originDeviceName` (string) field. v1 files remain readable (the field is
  optional; consumers treat absent as "unknown device").
- Required fields unchanged (vaultId, vaultLocator, providerType,
  providerConfig, encryptionSuiteVersion).
- Export writes v2 with `originDeviceName` from
  `AppDevice.current().displayName` (001 App/Sources/App/AppDevice.swift).
- Import accepts v1 and v2; unsupported versions fail closed (FR-010).
- Versioned JSON + compatibility tests per Constitution IV.

### UI (App layer)

- `SyncConfigureSheet` (001 SyncSettingsView.swift) gains a mode picker:
  **Create new vault** (existing) / **Join existing vault**.
- Join mode fields: provider config (same as create), vault locator text
  field, vault password (label "Vault password", NOT "(new)"), optional
  "Import from file…" button (NSOpenPanel) that fills provider type/locator
  from a sync-profile JSON and shows the origin device name.
- Export entry: in the configured state, "Export Sync Profile…" (NSSavePanel)
  writes schema v2 JSON — protocol, locator, origin device name, redacted
  provider config (per 001 contract); NO credentials/keys/content.
- On join success: status rows show provider + last sync (existing
  SyncSettingsView rows).

### Error surface

- `StickyError` / ProviderError reuse: `.notFound` → "vault not found at this
  location"; key-confirmation failure → "wrong synchronization password";
  schema/parse failures → fail closed with sanitized code. Distinguishable
  messages (FR-004/FR-005).

## Constitution Check

| # | Principle | Plan decision | Status |
|---|-----------|---------------|--------|
| I | Focused product | Join adds the promised multi-Mac sync; no new product scope. | PASS |
| II | Native macOS/SwiftUI | Join UI is SwiftUI within the existing Settings sheet; macOS 26 target unchanged. | PASS |
| III | Local-first | Join keeps local DB as source of truth; sync additive; local notes never blocked. | PASS |
| IV | Versioned data | sync-profile schema v2 with v1 read-compat + tests; no layout changes to stored objects. | PASS |
| VI | Privacy | Export contains no credentials/keys/content; device display name is non-sensitive; logs sanitized (no endpoint URL, locator is opaque). | PASS |
| VII | E2E encryption | Join decrypts only with the correct password (key-confirmation); bootstrap read-only. | PASS |
| VIII | Non-destructive sync | Join never overwrites local/remote; first sync uploads local notes (merge); conflicts via existing resolver. | PASS |
| X | Accessible UX | New controls (mode picker, locator field, import/export buttons) keyboard-accessible with VoiceOver labels; error text not color-only. | PASS |
| XI | Performance | Join network/decrypt off main actor; first sync <100 notes ≤1 min; large uploads chunked without UI freeze. | PASS |
| XII | Tests mandatory | Join-verify, fail-closed, schema round-trip, import-validation, content-boundary, perf, localization, accessibility tests FIRST. | PASS |
| XIII | Dependency discipline | Zero new dependencies. | PASS |
| XIV | Traceability | Spec FR-001..FR-012 map 1:1 to tasks; spec Scope/Data&Migration/Privacy&Permission/Accessibility/Performance/Failure&Recovery/Required-Tests sections all addressed in this plan. | PASS |

No violations. No Complexity Tracking entries.

## Phases

### Phase 1 — Contract: sync-profile schema v2 + bootstrap object name

- Bump `sync-profile-export.schema.json` to v2 (optional `originDeviceName`,
  v1 read-compat documented; providerConfig remains REQUIRED and redacted —
  endpoint/prefix are connection info, not secrets). Tests: v1 file parses,
  v2 round-trip, unsupported version fails closed.
- Add `RemoteLayout.bootstrapObjectName(for:)` (Domain, `RemoteManifest.swift`)
  shared by create + join.
- Add the **create-path bootstrap upload** + **WebDAV locator addressing**
  (containerPath = prefix + "/" + locator) so the join fetch targets the
  object the create path uploaded. Tests: create uploads the bootstrap under
  the deterministic name (verified via provider state).

### Phase 2 — SecurityCore: join bootstrap verification

- `VaultBootstrapService.openRemoteBootstrap(remoteBootstrap, password,
  expectedVaultId?)` (wrong-vault context reuse via checkBootstrap) +
  integration with `openVault` (existing).
- Tests: wrong password (key-confirmation), corrupt bootstrap, wrong vault
  context — all fail closed.

### Phase 3 — SyncCoordinator: joinExistingVault

- Full join flow (fetch bootstrap → verify → open → persist → wireEngine →
  immediate runSync). Local notes upload on first sync (existing engine).
- Tests (in-memory provider): join success + bidirectional sync; wrong
  password; missing bootstrap; local notes preserved + uploaded.

### Phase 4 — App UI: join mode + export/import

- SyncConfigureSheet mode picker + locator field + password label;
  import-from-file (v1/v2, shows origin device name); Export Sync Profile…
  (schema v2). Status rows show provider after join.
- AppTests: import validation, export content boundary (no secrets), join
  flow end-to-end with in-memory provider.

### Phase 5 — Polish & validation

- Localization of new strings (zh-Hans + en catalogs), accessibility labels,
  documentation (quickstart multi-Mac walkthrough), full regression.

## Key rules

- Tests FIRST per phase (Constitution XII); join-verify paths reuse 001's
  `InMemorySyncProvider` composition-test pattern.
- Additive remote object only: the bootstrap upload + WebDAV locator
  addressing are new objects/paths — 001 object encryption, manifest, and
  conflict formats are untouched.
- Join is READ-ONLY: no MKCOL, no remote object creation (FR-003).
- Export never contains credentials/keys/content (SC-004 enforced by tests);
  endpoint/prefix are connection info, not secrets.
- Single-configuration invariant preserved (001 FR-154).
