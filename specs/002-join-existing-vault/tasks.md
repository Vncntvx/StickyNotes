# Tasks: Join Existing Vault (Cross-Device Sync)

**Input**: `/specs/002-join-existing-vault/` design docs.
**Prerequisites**: plan.md (required), spec.md (required), research.md (R0-R5), data-model.md, contracts/sync-profile-v2-delta.md, constitution.md.
**Tests**: MANDATORY (Constitution XII). Tests written FIRST, must FAIL before implementation.
**Organization**: Phases align with plan.md §Phases. Reuses feature 001's StickyCore modules (SyncCore, SecurityCore, Persistence), App sync surface (`SyncCoordinator`, `SyncSettingsView`), and test patterns (`InMemorySyncProvider`).

## Path Conventions

Repository layout (plan.md §Architecture — all paths repository-relative):

```text
App/Sources/App/SyncCoordinator.swift
App/Sources/Features/Settings/SyncSettingsView.swift
Packages/StickyCore/Sources/{SecurityCore/VaultBootstrap.swift, SyncCore/SyncEngine.swift, Domain/Models/RemoteManifest.swift, SyncCore/ProviderErrors.swift, Persistence/Repositories/VaultConfigurationStore.swift}
specs/001-sticky-notes-app/contracts/sync-profile-export.schema.json
AppTests/SyncCompositionTests.swift
Packages/StickyCore/Tests/{SecurityCoreTests,SyncCoreTests,DomainTests}/
```

> **NOTE (analyze remediation, approved)**: `RemoteLayout` lives in the DOMAIN
> module (`Domain/Models/RemoteManifest.swift`); its tests live in
> `DomainTests/RemoteLayoutTests.swift` (already exists — extend it). 001
> stores NO remote bootstrap today; 002 ADDS a create-path bootstrap upload +
> WebDAV locator addressing (plan.md §Bootstrap object name).

## Phase 1: Contract — sync-profile schema v2 + bootstrap object name

**Purpose**: Version the export contract (optional `originDeviceName`, v1 read-compat) and make the bootstrap object name explicit/shared so create and join address the same remote object.

- [X] T001 [P] Contract test: `sync-profile-export.schema.json` v1 file parses under the v2 validator (backward compatible); a v2 file with `originDeviceName` round-trips; a file with an unsupported `schemaVersion` (0 / 3) fails validation in `Packages/StickyCore/Tests/SyncCoreTests/SyncProfileSchemaTests.swift` per Constitution IV / plan §Sync-profile schema v2
- [X] T002 [P] Contract test: `RemoteLayout.bootstrapObjectName(for:)` is deterministic and identical for create and join — the object the create path uploads is exactly the object the join path fetches in `Packages/StickyCore/Tests/DomainTests/RemoteLayoutTests.swift` (extend the existing suite) per plan §Bootstrap object name
- [X] T003 Bump `sync-profile-export.schema.json` to v2: add optional `originDeviceName` (string) to `properties`, keep `additionalProperties: false`, keep `providerConfig` REQUIRED and redacted (endpoint/prefix are connection info, not secrets), document v1 read-compatibility in the description per FR-009 / plan §Sync-profile schema v2
- [X] T004 Implement `RemoteLayout.bootstrapObjectName(for locator:)` (explicit, shared) in `Packages/StickyCore/Sources/Domain/Models/RemoteManifest.swift` (where `RemoteLayout` lives) per plan §Bootstrap object name
- [X] T024 [P] Composition test: CREATE path uploads the bootstrap JSON under `RemoteLayout.bootstrapObjectName(for:)` — after `configure(...)`, provider state contains exactly that object (verified via in-memory provider) in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per plan §Bootstrap object name / FR-003 create-side prerequisite
- [X] T025 [P] Composition test: WebDAV + S3 create/join address the SAME remote location — WebDAV `containerPath` includes the locator (`<prefix>/<locator>`, mirroring S3); join fetches the bootstrap the create path uploaded in `AppTests/SyncCompositionTests.swift` per plan §Bootstrap object name (WebDAV locator addressing) / H2

## Phase 2: SecurityCore — join bootstrap verification

**Purpose**: Verify a fetched remote bootstrap BEFORE persisting anything: wrong password and wrong-vault context fail closed with distinguishable messages.

- [X] T005 [P] SecurityCore test: wrong password at join → key-confirmation mismatch → fail closed, no state accumulation (FR-160e), distinguishable from vault-not-found in `Packages/StickyCore/Tests/SecurityCoreTests/JoinBootstrapTests.swift` per FR-004/FR-011 / FR-160d(a) / CHK028
- [X] T006 [P] SecurityCore test: corrupt / truncated remote bootstrap → fail closed; bootstrap whose `vaultId` does not match a locally retained configuration (wrong-vault context, `checkBootstrap` reuse) → fail closed, no local/remote mutation in `Packages/StickyCore/Tests/SecurityCoreTests/JoinBootstrapTests.swift` per FR-004 / T181 reuse
- [X] T007 Implement `VaultBootstrapService.openRemoteBootstrap(remoteBootstrap:password:expectedVaultId:)` — parse + key-confirmation + optional vaultId context check via `checkBootstrap`, reusing existing `openVault` internals, in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` per plan §Join flow

## Phase 3: SyncCoordinator — joinExistingVault

**Purpose**: The end-to-end join: fetch bootstrap read-only → verify → persist single config → wire engine → immediate sync (local notes upload encrypted).

- [X] T008 [P] SyncCore/Persistence test: join flow with in-memory provider — provider has a remote bootstrap + objects; join fetches it, opens with the correct password, persists the configuration (single-row replace per FR-154), and first sync downloads remote notes + uploads local notes without deleting either side in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per FR-006/FR-007/US1/AC4,AC6
- [X] T009 [P] SyncCore test: join with a MISSING remote bootstrap → fail closed, no local configuration row written, no remote object created (verified via provider state) in `AppTests/SyncCompositionTests.swift` per FR-005/US1/AC3
- [X] T010 [P] SyncCore test: join with a WRONG password → fail closed, no configuration written, previous configuration (if any) untouched in `AppTests/SyncCompositionTests.swift` per FR-004/US1/AC2
- [X] T011 Implement `SyncCoordinator.joinExistingVault(providerType:endpoint:containerPath:bucket:region:vaultLocator:credentials:vaultPassword:)` — READ-ONLY connectivity probe (fetchMetadata/HEAD, NO MKCOL — FR-003/CHK003) → fetch bootstrap by `bootstrapObjectName(locator)` (READ-ONLY, FR-003) → `openRemoteBootstrap` → `configStore.saveConfiguration` (single-row) → `wireEngine` → `runSync()` immediately; local notes upload via the existing engine path; all fetch/decrypt off the main actor (FR-012) in `App/Sources/App/SyncCoordinator.swift` per plan §Join flow / FR-003/FR-012 / CHK003/CHK032
- [X] T026 Implement the create-path bootstrap upload + WebDAV locator addressing in `App/Sources/App/SyncCoordinator.swift`: after `createVault`, upload the bootstrap JSON under `RemoteLayout.bootstrapObjectName(for: locator)` BEFORE the first sync (fail closed: error leaves local config unwritten); `makeProvider` WebDAV containerPath = `<prefix>/<locator>` (mirroring S3) per plan §Bootstrap object name (depends on T024/T025)
- [X] T012 Implement the join error surface: `vault-not-found` (ProviderError.notFound) vs `wrong-password` (key confirmation) vs `wrong-vault` — sanitized, distinguishable codes surfaced through `lastErrorCode` per FR-004/FR-005/CHK028
- [X] T022 [P] SyncCore/Persistence test: join flow preserves 001 FR-174 long-offline semantics — a joining device whose local notes were last synced >30 days ago re-syncs without automatically deleting local content (US3/AC2, CHK023) in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per FR-011/CHK023
- [X] T023 [P] SyncCore test: join edge cases — remote bootstrap deleted mid-join → fail closed, no local configuration written (CHK026); two devices joining the same vault concurrently → read-only join, no write race, both succeed (CHK027) in `AppTests/SyncCompositionTests.swift` per spec §Edge Cases / CHK026/CHK027

## Phase 4: App UI — join mode + export/import

**Purpose**: The settings surface: mode picker, locator field, import-from-file (v1/v2, shows origin device name), export sync profile (schema v2, no secrets).

- [X] T013 [P] App test: sync-profile EXPORT content boundary — exported JSON validates against schema v2, contains `originDeviceName` from `AppDevice`, contains NO credentials/keys/note content (inspectable content-boundary test) in `AppTests/SyncProfileExportTests.swift` per FR-009/SC-004/CHK029
- [X] T014 [P] App test: sync-profile IMPORT validation — a v1 file and a v2 file both import (v2 shows the origin device name); a corrupted file and an unsupported schemaVersion fail closed with no local config written in `AppTests/SyncProfileExportTests.swift` per FR-010/US2/AC3
- [X] T015 Implement the join mode in `SyncConfigureSheet` — mode picker (Create new vault / Join existing vault), vault locator text field (join mode, format pre-check per CHK024), "Vault password" label (join) vs "Vault password (new)" (create), "Import from file…" (NSOpenPanel, fills protocol+locator, shows origin device name), wired to `SyncCoordinator.joinExistingVault`; after join the status rows show provider + last sync (FR-008) in `App/Sources/Features/Settings/SyncSettingsView.swift` per FR-001/FR-002/FR-008/US1/AC1 / CHK001/CHK002/CHK008/CHK024
- [X] T016 Implement "Export Sync Profile…" in the configured sync state — NSSavePanel writing schema v2 JSON (protocol, locator, origin device name, redacted provider config per 001 contract; NEVER credentials/keys/content) in `App/Sources/Features/Settings/SyncSettingsView.swift` per FR-009/US2/AC1

## Phase 5: Polish & validation

**Purpose**: Localization, accessibility, docs, full regression.

- [X] T017 [P] Localization: add zh-Hans + en catalog keys for all new strings (mode picker, locator field, import/export buttons, join error messages) and assert completeness in `AppTests/LocalizationCompletenessTests.swift` per FR-180a (001)
- [X] T018 [P] Accessibility: keyboard-accessible join/import/export actions + VoiceOver labels on the new controls in `App/Sources/Features/Settings/SyncSettingsView.swift` per FR-180b (001)
- [X] T019 Documentation: quickstart multi-Mac walkthrough (create on A → export → import on B → join → verify sync) — already drafted in `specs/002-join-existing-vault/quickstart.md`; validate it against the built app and update as needed per SC-001 / CHK033
- [X] T021 [P] Performance verification: join + first sync of <100 notes completes within 1 minute on a local loopback/in-memory provider (SC-002); assert no main-actor blocking during the join (FR-012) in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per SC-002 / FR-012 / CHK034
- [X] T020 Full regression: StickyCore suites + AppTests + AppUITests journeys (001) remain green with the join feature present

**Checkpoint**: All 002 tasks complete; join-existing-vault is testable end-to-end (device B joins device A's vault with manual locator OR imported profile).

---

## Dependencies & Execution Order

- Phase 1 (contract) → Phase 2 (verification) → Phase 3 (coordinator) → Phase 4 (UI) → Phase 5 (polish).
- T004 depends on T002; T026 on T024/T025; T007 on T005/T006; T011 on T007/T008-T010/T026; T022/T023 on T011 (join flow must exist before edge-case tests pass); T015/T016 on T011.
- Parallel: T001/T002; T005/T006; T008-T010; T013/T014; T022/T023; T024/T025.
- Tests FIRST per phase (Constitution XII); phases 1-4 must FAIL before their implementation tasks land. T024/T025 must FAIL before T026; T008-T010 before T011.
- Checklist mapping: requirements.md CHK001-CHK036 ↔ T001-T026 (CHK026/CHK027 → T023; CHK023 → T022); gate.md CHK001-CHK031 = spec/plan/contracts quality gate (mark [x] before implement).

---

## Phase 6: Convergence

**Purpose**: Close gaps found by `/speckit.converge` after the Phase 1-5 implement pass — join-with-existing-config UI reachability, WebDAV addressing test coverage, locator format feedback, FR-012 main-actor assertion, and export suite-version fidelity. Tests FIRST per Constitution XII.

- [X] T027 [P] App test: WebDAV create/join provider construction includes the vault locator in `containerPath` — `makeProvider` yields `containerPath = "<prefix>/<locator>"` (mirroring S3) for a WebDAV configuration in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per T025 / plan §Bootstrap object name (partial)
- [X] T028 [P] App test: join with an EXISTING configuration applies replace semantics — join succeeds, the new vault replaces the old single-row config, local notes preserved, prior remote data untouched in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per US1/AC6 / FR-007 / CHK018 (partial)
- [X] T029 Implement a "Join existing vault…" entry point in the CONFIGURED state of `SyncSettingsView` (alongside Replace/Remove) that opens `SyncConfigureSheet` with the mode picker available, wiring `joinExistingVault` with replace semantics per FR-007/US1/AC6/CHK018 (partial)
- [X] T030 Surface an inline locator format-error message when the join-mode locator is non-empty and fails the CHK024 pre-check (currently the Join button is silently disabled) in `App/Sources/Features/Settings/SyncSettingsView.swift` per CHK024 / spec §Edge Cases (partial)
- [X] T031 [P] Perf test: assert no main-actor blocking during the join (FR-012) — the join's fetch/decrypt do not run synchronously on the main actor in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per T021 / FR-012 (partial)
- [X] T032 Make "Export Sync Profile…" derive `encryptionSuiteVersion` from the configured vault instead of hardcoding 1, and make `SyncProfileCodec.encode` throw instead of silently returning empty `Data()` on serialization failure per FR-009 / T016 (partial)
- [X] T033 [P] App test: `discoverVaults` lists existing vaults from the repository WITHOUT any vault password — two seeded vaults (repo-layout provider, `<locator>/<bootstrap>` structure) are enumerated with correct locator + vaultId, sorted by creation date; an empty repository returns [] in `AppTests/SyncCompositionTests.swift` (JoinExistingVault suite) per FR-013 / US2/AC4 (missing)
- [X] T034 Implement `SyncCoordinator.discoverVaults(providerType:endpoint:containerPath:bucket:region:credentials:)` — repository-level `list()` → derive locators from first path segment → locator-scoped bootstrap fetch (READ-ONLY, no vault password) → `[DiscoveredVault]` sorted by createdAt; `remoteContainerPath` handles the empty-locator (repository) case in `App/Sources/App/SyncCoordinator.swift` per FR-013 / plan §Vault discovery (missing)
- [X] T035 Implement the scan-before-join UI: "Scan for Existing Vaults…" button in join mode → `discoverVaults` → vault list (creation date + locator prefix) → selection fills the locator + sets `expectedVaultId`; empty-repo and scan-error messages; zh-Hans/en catalog keys in `App/Sources/Features/Settings/SyncSettingsView.swift` + `App/Resources/Localizable.xcstrings` per FR-013 / US2/AC4 / CHK025 (missing)
