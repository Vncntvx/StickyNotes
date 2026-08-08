# Data Model: Join Existing Vault

**Feature**: 002-join-existing-vault | **Date**: 2026-08-08 | **Plan**: [plan.md](./plan.md)

This document defines the durable data touched by the join-existing-vault
feature. 002 introduces **no new database tables and no migration**: it reuses
001's `vaultConfiguration` and `syncState` tables (single-configuration
replace semantics, FR-154) and 001's canonical contracts. What 002 adds is the
contract **version change** (sync-profile v2) and the **join flow's
verification inputs/outputs**.

## Conventions (inherited from 001)

- IDs: UUID v4 strings; timestamps UTC ISO 8601; all synced entities carry
  version lineage (versionId/parentVersionId/lastModifiedDeviceId/modifiedAt).
- Local DB (App Group SQLite, GRDB/WAL) is the source of truth (Constitution
  III); remote encrypted objects are a replication/exchange mechanism.
- Exactly one vault configuration per device (FR-150/FR-154).

## Entities

### VaultConfiguration (001, reused — join writes the same row)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | stable local config identity |
| providerType | enum (webdav/s3) | join mode sets from UI or imported profile |
| endpoint | TEXT | WebDAV base URL / S3 endpoint |
| containerPath / bucket / region / prefix / pathStyle | nullable | provider-specific |
| vaultId | UUID | **authoritative for wrong-vault detection** (join verifies remote bootstrap vaultId equals a retained local config's vaultId, else fail closed) |
| vaultLocator | TEXT | opaque remote locator; the join key |
| encryptionSuiteVersion | int | must match bootstrap |
| createdAt / updatedAt | datetime | |

**Join behavior**: `configStore.saveConfiguration` (001) replaces the single
row — local notes data is untouched (FR-007/CHK018). No new columns.

### SyncProfile (contract — schema v2, 001 file bumped)

Portable, device-agnostic description transferred between Macs. **Contains no
secrets** (credentials stay in Keychain on each device; password entered at
import/join time).

| Field | Type | v1 | v2 | Notes |
|-------|------|----|----|-------|
| schemaVersion | const | 1 | 2 | v2 adds optional originDeviceName; v1 files validate under v2 validator |
| vaultId | UUID | req | req | |
| vaultLocator | string | req | req | opaque |
| providerType | enum | req | req | webdav / s3 |
| providerConfig | object | req | req | redacted — endpoint/region/bucket/prefix/pathStyle/certificateFingerprint; NO credentials |
| encryptionSuiteVersion | int ≥1 | req | req | |
| originDeviceName | string, nullable | — | **new, optional** | user-readable display name of the exporting device (AppDevice displayName, ≤ ~100 chars) |
| createdAt | datetime, nullable | opt | opt | |

Validation rules (from requirements):

- Unsupported `schemaVersion` (0, 3, …) → fail closed, no local config written
  (FR-010, CHK021).
- Corrupt/undecodable file → fail closed (FR-010).
- `additionalProperties: false` preserved — unknown fields reject (schema
  strictness unchanged).
- Import accepts v1 and v2; v2 shows the origin device name (FR-010/US2/AC2).

### VaultBootstrap (001, reused — join fetches READ-ONLY)

001 `vault-bootstrap.schema.json`: schemaVersion 1, formatVersion, vaultId,
vaultLocator, argon2id parameters (production minimums FR-160c: memoryKiB ≥
19456, iterations ≥ 2, parallelism ≥ 1), wrappedMasterKey, keyConfirmation,
encryptionSuiteVersion, createdAt. Join reads it under the bootstrap object
name derived from the locator (`RemoteLayout.bootstrapObjectName(for:)`,
Domain module); `openRemoteBootstrap` verifies key confirmation (password)
and, when a local config exists, vaultId equality via `checkBootstrap`
(wrong-vault). No mutation ever (FR-003/CHK003/CHK025).

**ADDITIVE to 001 (plan.md §Bootstrap object name)**: 001 stores no remote
bootstrap today (createVault is in-memory; only the fixed-name `"manifest"`
object is uploaded). 002 adds (1) a CREATE-path bootstrap upload under
`bootstrapObjectName(locator)` before first sync, and (2) WebDAV locator
addressing — `containerPath = "<prefix>/<locator>"` (mirroring S3), so join
by locator reaches the same remote location on both providers. New vaults
created with 002 upload the bootstrap; vaults created by 001 (no remote
bootstrap) fail closed with "vault not found" on join — documented, acceptable.

## State transitions

**Join flow** (SyncCoordinator.joinExistingVault):

```
idle
  → (build provider, verify connectivity) → fetch-bootstrap
  → (parse OK) → verify (key-confirmation + optional vaultId check)
  → (verified) → persist-config (single-row replace) → wireEngine → syncing
  → (synced) → configured (status rows show provider + last sync, FR-008)

Any failure edge → failed(join) with distinguishable sanitized code:
  - notFound              → "vault not found at this location"
  - keyConfirmation       → "wrong synchronization password"
  - vaultId mismatch      → "this vault does not match your existing configuration"
  - parse/schema corrupt  → fail closed (sanitized)
```

Fail-closed invariant (FR-004/FR-005, CHK030/CHK035): every failure edge
leaves NO local configuration row written and NO remote object created or
modified. If a previous configuration exists, it is untouched.

## Contract artifacts

- **Changed** (001, bumped by this feature): `specs/001-sticky-notes-app/
  contracts/sync-profile-export.schema.json` → v2 (optional originDeviceName,
  v1 read-compat documented in description).
- **Unchanged, reused read-only**: `vault-bootstrap.schema.json`,
  `encrypted-envelope.schema.json`, `encrypted-manifest.schema.json`,
  `note-document.schema.json`, `tombstone.schema.json`.

## Migration implications

None — no DB schema change, no new tables, no new object layouts. The only
versioned-data change is the export contract bump (schema v2), covered by
backward-compatibility tests (T001: v1 file parses under v2 validator; T013:
export validates against v2; T014: v1+v2 import).
