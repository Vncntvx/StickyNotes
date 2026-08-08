# Research: Join Existing Vault (Cross-Device Sync)

**Feature**: 002-join-existing-vault | **Date**: 2026-08-08 | **Plan**: [plan.md](./plan.md)

Records the technical decisions for the join-existing-vault feature. Feature 001
already resolved the underlying platform research (encryption suite, Argon2id
parameters FR-160c, GRDB/WAL, provider adapters, conflict/tombstone semantics);
this document records only the NEW decisions 002 introduces and re-validates
the reused assumptions against the verified 001 implementation.

> Reuse baseline: 001 is implemented and green (StickyCore + AppTests + UI
> journeys). Every decision below is verified against the actual 001 code paths
> listed, not assumed from the plan.

## R0. Bootstrap object name — explicit shared derivation (ADDITIVE to 001)

- **Decision**: 001 stores NO remote bootstrap today (verified in code:
  `createVault` is in-memory; only the manifest at the FIXED name `"manifest"`
  is uploaded; the master key lives in Keychain only). 002 therefore ADDS:
  (1) `RemoteLayout.bootstrapObjectName(for locator: String) -> String` in the
  Domain module (where `RemoteLayout` already lives, `Domain/Models/
  RemoteManifest.swift`); (2) a CREATE-path bootstrap upload under that name
  in `SyncCoordinator.configure` (before first sync, fail closed); (3) WebDAV
  locator addressing — `containerPath = "<prefix>/<locator>"`, mirroring S3,
  so a join by locator reaches the same remote location on both providers
  (today WebDAV ignores the locator and two vaults on one container path
  collide on the shared `"manifest"` object).
- **Rationale**: without a remote bootstrap, a second device cannot derive the
  master key (argon2 params + wrapped key + key confirmation live only in the
  bootstrap) and therefore cannot decrypt the master-key-encrypted manifest —
  join is cryptographically impossible without it. A single shared function
  makes create/join consistency a compile-time guarantee. The upload is an
  ADDITIVE remote object (Constitution IV-compliant); no 001 encryption,
  manifest, or conflict format changes.
- **Alternatives considered**: (a) importing key material via the sync profile
  — rejected: FR-009/Constitution VI forbid secrets in the export;
  (b) deriving the manifest key from the password directly — rejected:
  changes 001's envelope/KEK design; (c) duplicating the name-building logic
  in the join path — rejected: drift risk.
- **Rejected alternatives**: changing the manifest object name scheme — would
  break every vault created by 001; bundling the bootstrap inside the manifest
  — the manifest is itself master-key-encrypted, circular.
- **Risks**: WebDAV addressing change alters the create-path container path
  for NEW vaults only (existing vaults keep their path — the locator was never
  in it; configs created before this change are unaffected since their
  providerConfig.prefix remains the full path). Any join against an old-format
  vault (no remote bootstrap) fails closed with "vault not found" — acceptable
  and documented.
- **Validation**: T002 (deterministic name, create == join), T024/T025
  (create uploads under the name; WebDAV/S3 address the same location),
  T026 implementation, T008-T010 round-trip via the fetch-by-name path.
- **Constitution impact**: Principle VII (remote object names opaque — the
  derived name stays a pure function of the already-opaque locator); Principle
  IV (additive versioned object, no format change). No violation.

## R1. Join bootstrap verification — wrong password vs wrong vault vs not found

- **Decision**: Reuse `VaultBootstrapService.openVault(bootstrap:password:)`
  internals in a new `openRemoteBootstrap(remoteBootstrap:password:
  expectedVaultId:)` that (a) parses the fetched bootstrap, (b) runs the
  existing key-confirmation check (wrong password → distinguishable failure,
  FR-160d(a)), and (c) when the caller has a retained local configuration,
  verifies `vaultId` equality via the existing `checkBootstrap` helper
  (wrong-vault context → fail closed, 001 T181-correct behavior from the
  vault-bootstrap schema contract).
- **Rationale**: The vault-bootstrap contract (001) already documents
  wrong-vault detection as authoritative (`vaultId` mismatch ⇒ fail closed,
  no local/remote mutation); key-confirmation already exists for password
  verification. Join composes these verified primitives instead of inventing
  a parallel verification path.
- **Alternatives considered**: Fetch-then-decrypt-first-object as the password
  check — rejected: requires a second object fetch and can conflate "wrong
  password" with "corrupt/missing object"; key-confirmation is cheaper and
  unambiguous.
- **Rejected alternatives**: Re-encrypting or rewriting the fetched bootstrap
  locally/remotely — violates FR-003 (read-only join) and Constitution VII.
- **Risks**: Wrong-password messages must stay distinguishable from
  vault-not-found (CHK028) without leaking whether a locator exists (oracle
  risk). Mitigated: both failures surface sanitized codes, never raw server
  data; the T005/T006 fail-closed tests assert no observable state change.
- **Validation**: JoinBootstrapTests (T005 wrong password, T006 corrupt/
  truncated + wrong vault); JoinExistingVault composition tests (T009
  missing bootstrap, T010 wrong password).
- **Constitution impact**: Principle VII (fail closed on incorrect password,
  modified ciphertext, invalid tags, unexpected contexts). No violation.

## R2. Sync-profile schema v2 — optional originDeviceName, v1 read-compat

- **Decision**: Bump `sync-profile-export.schema.json` to v2 (in 001's
  contracts dir, per tasks.md path conventions): `schemaVersion` const 2, add
  OPTIONAL `originDeviceName` (string, max ~100 chars, user-readable display
  name). Required fields unchanged. v1 files validate under the v2 validator
  (the added field is optional; `additionalProperties: false` preserved).
- **Rationale**: Constitution IV (versioned, backward-compatible formats);
  the field is display-only (device B shows "from <device A name>") — the
  authoritative identity remains the locator/vaultId. Making it optional keeps
  v1 read-compat trivial and avoids breaking export from devices that cannot
  supply a name.
- **Alternatives considered**: v2 with `originDeviceName` REQUIRED — rejected:
  breaks the "old file, new reader" guarantee (a v1 file could not validate).
- **Rejected alternatives**: A separate v2 file/id + content negotiation —
  over-engineering for a single optional field.
- **Risks**: Two schema versions must be tested (round-trip, reject unsupported
  versions 0/3). Mitigated by T001 contract tests + T013/T014 import/export
  tests.
- **Validation**: SyncProfileSchemaTests (T001); SyncProfileExportTests
  (T013/T014); quickstart multi-Mac walkthrough (T019).
- **Constitution impact**: Principle IV (version + backward compat + tests with
  previous-version fixtures — T001 explicitly validates a v1 file under the v2
  validator). No violation.

## R3. Join orchestration — SyncCoordinator extension, read-only fetch

- **Decision**: Extend `SyncCoordinator` with `joinExistingVault(...)`:
  provider build → READ-ONLY connectivity probe (fetchMetadata/HEAD on the
  manifest name; NO `verify()` MKCOL — WebDAV `verify()` CREATES the container,
  a remote write forbidden by FR-003/CHK003) → READ-ONLY fetch of the bootstrap
  by locator → `openRemoteBootstrap` → `configStore.saveConfiguration` (existing
  single-row replace, 001 FR-154) → `wireEngine` → immediate `runSync()`.
  Everything except UI state off the main actor (FR-012, Constitution XI).
- **Rationale**: Matches the 001 coordinator pattern exactly (create path
  shares provider build/engine wiring); single-configuration invariant is
  preserved by reusing the existing save path (replace semantics, local notes
  untouched). Immediate sync after join is the spec'd user decision (FR-006).
- **Alternatives considered**: Import config without joining (save-only mode)
  — rejected: out of scope (US2 always joins after import).
- **Rejected alternatives**: A separate join engine — would duplicate engine
  wiring and bypass 001's serialized-sync guarantees (Constitution XI).
- **Risks**: Concurrent sync already running when join triggers runSync —
  mitigated by the engine's existing mutation serialization (001 design).
- **Validation**: JoinExistingVault composition suite (T008 success +
  bidirectional first sync; T009 missing bootstrap; T010 wrong password);
  perf/off-main-actor assertion (T021).
- **Constitution impact**: Principles III (local-first, sync additive), VIII
  (non-destructive: no local/remote overwrite; first sync uploads local notes
  via merge), XI (no main-actor network/crypto). No violation.

## R4. Join error surface — distinguishable sanitized codes

- **Decision**: Surface three distinguishable, sanitized errors: `.notFound`
  → "vault not found at this location" (FR-005, ProviderError.notFound);
  key-confirmation mismatch → "wrong synchronization password" (FR-004);
  vaultId mismatch → "this vault does not match your existing configuration"
  (wrong-vault, FR-004 edge). All propagate through `lastErrorCode`
  (FR-004/FR-005/CHK028). No raw server data, no endpoint URL in messages or
  logs (FR-191, Constitution VI).
- **Rationale**: CHK028 requires distinguishability; Constitution VI requires
  sanitized logs. Reusing ProviderError keeps the 001 error taxonomy intact.
- **Alternatives considered**: A single generic "join failed" message —
  rejected: violates CHK028 and harms debuggability for users.
- **Validation**: T012 (error mapping), T005/T006/T009/T010 (distinguishable
  outcomes under test).
- **Constitution impact**: Principles VI (logs sanitized), VII (fail closed),
  X (error text, not color-only). No violation.

## R5. Import/export file flow — NSOpenPanel/NSSavePanel, no secrets

- **Decision**: Export writes schema v2 JSON via NSSavePanel (protocol,
  locator, redacted provider config — endpoint/prefix are connection info, not
  secrets, and are REQUIRED by the 001 contract for the receiving device to
  connect; originDeviceName from `AppDevice` displayName; NEVER credentials/
  keys/content — FR-009/SC-004/CHK029). Import reads via NSOpenPanel, validates
  schema v1/v2, fills provider+locator, shows origin device name, then requires
  only the password (FR-010/US2).
- **Rationale**: Reuses 001's AppDevice identity and the 001 contract;
  content-boundary is enforced by an inspectable test (T013) not by hope.
- **Alternatives considered**: Drag-and-drop of profile files onto the sheet
  — rejected: nice-to-have, scope creep; NSOpenPanel is the platform-native
  baseline (Constitution II).
- **Rejected alternatives**: Cloud-hosted profile discovery — violates
  FR-143/constitution (no developer-operated services) and the spec's
  out-of-scope list.
- **Validation**: SyncProfileExportTests (T013 content boundary, T014
  import validation); quickstart walkthrough (T019); UI journey regression
  (T020).
- **Constitution impact**: Principles VI (no secrets in export; file name
  sanitation FR-191), II (platform-native file panels). No violation.
