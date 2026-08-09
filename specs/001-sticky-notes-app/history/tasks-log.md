# Tasks Implementation Log — macOS Sticky Notes

> **本目录为历史记录**：后续 `speckit.plan` / `speckit-tasks` /
> `speckit-implement` 默认无需阅读本目录。此文件归档 tasks.md 中
> 已完成（[X]）任务的详细实施注记（audit 摘要、partial 说明、矛盾诊断），
> 以便追溯每个收敛任务的完成过程。tasks.md 当前版本中这些任务以
> 一行摘要保留（ID + 状态 + 文件路径），任务语义与本文件内容一致。

## Archived task details

- [X] T152 Enforce `Note.coverScreenshotBlockId → Block.id` foreign key in v1 schema per data-model.md:277 (partial) — the FK was dropped from `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` because GRDB's column-level `references("block")` queries the destination table's PK at CREATE time and `block` is created after `note` (circular dependency). Fix by either (a) creating the `note` table via raw SQL with `REFERENCES "block"("id") ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED` (verified to work — SQLite defers the FK target existence check), or (b) reordering table creation so `block` is created before `note` and the `block.noteId → note` FK is added via a subsequent table recreation. Add a migration test asserting the FK exists in `sqlite_master` and that deleting a cover screenshot block nulls `note.coverScreenshotBlockId`.

- [X] T153 Add migration-recovery tests covering `StickyMigrator` pre-migration backup creation, restore-on-migration-failure, `MigrationRecovery.recoverFromInterruptedMigration` (missing DB / corrupt DB / intact DB no-op / backup consumed after restore), and `currentSchemaVersion` fallback, in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift` per T022 and plan §Local storage (partial) — the recovery machinery in `Packages/StickyCore/Sources/Persistence/Migrations/Migrator.swift` is implemented but has zero test coverage and no call sites (Constitution XII mandates database migration tests; `MigrationTests.swift:21` claims "Interrupted-migration recovery restores the backup" but no such test exists)

- [X] T154 Wire `StickyMigrator` + `MigrationRecovery.recoverFromInterruptedMigration` into app startup so the migration framework is actually used (pre-migration backup + interrupted-migration recovery at launch) per plan §Local storage (partial) — currently only `InitialSchema.migrator()` is exercised by tests; `StickyMigrator`/`MigrationRecovery` are unreferenced outside `m0001_initial.swift` comments

- [X] T155 Complete the Milestone 0 prototype hard gate (T025a): build SwiftUI rich-text + Chinese IME, Markdown single-Undo, one-window-per-note, per-window floating, App Group GRDB widget access, ScreenCaptureKit single-frame, native global shortcut prototypes in `Prototypes/` (currently empty) and confirm feasibility per plan §Milestone 0 (contradicts) — user-story implementation tasks (T030, T031, T061, T073, T074) were marked complete while the hard gate remains unmet; gate must be satisfied and verified before further user-story implementation proceeds

- [X] T156 Review or justify `Packages/StickyCore/Sources/Persistence/TempDatabasePaths.swift` (unrequested) — a test-support temp-path registry not called for by any task; retain only if justified as CI test hygiene (used by `DatabaseStore.inMemory()`), otherwise remove

- [X] T157 Fix the stale FTS5 comment in `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` (contradicts) — the comment claims `synchronize(withTable:)` is NOT used and references "triggers below", but line 289 does use `t.synchronize(withTable: "note_fts_content")` and no triggers are defined in the migration; align the comment with the actual implementation

- [X] T173 Reconciled: T001 updated to reflect `project.yml` as source of truth; `StickyNotes.xcodeproj` generated at build time; CI bootstrap and quickstart.md updated per FR-008/US1/plan §Project Structure in `project.yml` + `.github/workflows/ci.yml` + `specs/001-sticky-notes-app/quickstart.md`

- [X] T176 [P] [US9] SecurityCore test: wrong-vault-selected fail-closed — bootstrap fetch returns a `vaultId` ≠ locally-configured `vaultId` (or a bootstrap already exists under the chosen locator for a new vault) → app returns a typed `Encryption.wrongVaultContext` / `Credentials.wrongVault` error (per `contracts/provider-errors.md` `wrongVault` category); no PUT/DELETE issued to the remote (verified via provider test double); no local config mutation; user-facing message is localized and actionable; starting a new empty vault on a repo that already contains a different vault's bootstrap bootstraps under a new random locator without overwriting the existing one in `Packages/StickyCore/Tests/SecurityCoreTests/WrongVaultDetectionTests.swift` per FR edge case (clarified 2026-08-07) / research R20 / Constitution VII/VIII

- [X] T177 [P] [US9] SecurityCore test: remember-unlock lifetime — remember-unlock enabled → relaunch app → vault still unlocked without password re-entry; logout or restart → vault locked, password required; explicit lock → Keychain item cleared (referenced by `VaultConfiguration.rememberedUnlockKeychainRef`); password forgotten → unrecoverable even with remember-unlock on (FR-163); the application MUST NOT behave as a login-item-bound daemon that keeps the vault unlocked across system restarts in `Packages/StickyCore/Tests/SecurityCoreTests/RememberUnlockLifetimeTests.swift` per FR-162a (clarified 2026-08-07) / research R21 / data-model §VaultConfiguration / Constitution VII

- [X] T178 [P] [US9] SyncCore test: repository replacement — after confirmed replace (WebDAV→S3 or different endpoint): local notes preserved (count + content unchanged); new vault bootstraps fresh (new `vaultId` + `vaultLocator`); prior remote data untouched (verified via provider test double that no DELETE was issued against the old locator); `VaultConfiguration.replacedFromVaultLocator` records the prior locator for user reference; wrong-vault detection still fires if the new repo already contains a different vault in `Packages/StickyCore/Tests/SyncCoreTests/RepositoryReplacementTests.swift` per FR-154 (clarified 2026-08-07) / research R19 / Constitution III/VIII

- [X] T180 [P] [US9] SyncCore/Diagnostics test: diagnostic-bundle field-boundary verification — generate a diagnostic bundle from a fixture vault with known note/asset content; assert the bundle contains EXACTLY the fields enumerated in `contracts/diagnostic-bundle.schema.json` (appVersion, osVersion, schemaVersionLocal, providerType, recentErrorEvents, syncRunCounts, objectCounts, vaultState, permissionStatuses, generatedAt) and NOTHING else; assert no note content, titles, summaries, captions, file names/paths, window titles, credentials, passwords, key material, raw server responses, or remote object names appear anywhere in the bundle; validate the bundle against the JSON Schema in `Packages/StickyCore/Tests/SyncCoreTests/DiagnosticBundleBoundaryTests.swift` (extends T109 `DiagnosticsPrivacyTests`) per FR-191 (clarified 2026-08-07) / research R22 / contracts/diagnostic-bundle.schema.json / Constitution VI/VII/SC-010

- [X] T181 [US9] Implement wrong-vault detection in VaultBootstrap — when fetching/bootstrap-checking a repository: compare the bootstrap object's `vaultId` against the locally-configured `VaultConfiguration.vaultId`; if mismatched (or a bootstrap already exists under the chosen locator for a new vault), return a typed `wrongVault` error per `contracts/provider-errors.md`; MUST NOT modify any local or remote data; MUST NOT issue PUT/DELETE to the remote; prompt user to choose a different repository or start a new empty vault under a fresh random locator (which bootstraps alongside the existing one without overwriting it) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` per FR edge case (clarified 2026-08-07) / research R20 / contracts/vault-bootstrap.schema.json / Constitution VII/VIII — VaultBootstrap exists (T112) but lacks the wrong-vault-id mismatch check and fail-closed path

- [X] T182 [US9] Implement remember-unlock lifetime in SecurityCore — add `rememberedUnlock` enum (disabled / enabledUntilLockOrRestart) + `rememberedUnlockKeychainRef` to `VaultConfiguration`; when enabled, store the unwrapped vault key in a Keychain item (referenced by `rememberedUnlockKeychainRef`) so ordinary app relaunches do not re-prompt; clear the Keychain item on explicit lock; MUST NOT survive logout/restart (not a login-item daemon); after logout/restart the password is required again; forgetting the sync password remains unrecoverable regardless of this setting (FR-163); exact "logout/restart detection" mechanism confirmed in M0 per research R21 in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` and `Packages/StickyCore/Sources/SecurityCore/KeychainAccess.swift` per FR-162a (clarified 2026-08-07) / research R21 / data-model §VaultConfiguration / Constitution VII

- [X] T183 [US9] Implement repository replacement flow in VaultBootstrap + SyncSettingsView — replacing an existing sync repository with a new one requires explicit user action with a clear warning and confirmation; upon confirmed replacement: local notes preserved; new vault bootstraps fresh (new `vaultId` + `vaultLocator`); the application MUST NOT automatically delete the prior repository's remote data (server-side cleanup of the old vault remains a manual user responsibility); record the prior locator in `VaultConfiguration.replacedFromVaultLocator` for user reference; wire the replacement UI (warning + confirmation + test-connection + bootstrap) into `SyncSettingsView` (extends T119) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` and `App/Sources/Features/Settings/SyncSettingsView.swift` per FR-154 (clarified 2026-08-07) / research R19 / data-model §VaultConfiguration / Constitution III/VIII

- [X] T185 [US9] Implement diagnostic-bundle export — generate the user-exportable diagnostic bundle from the `DiagnosticSnapshot` entity (data-model.md): collect app version, OS version, local schema version, sync provider type (WebDAV/S3 — never endpoint/hostname/credentials), normalized provider error categories + timestamps for the last 30 days (never raw server responses/bodies), sync run counts + durations (never payloads/object names), aggregate counts of notes/blocks/assets (never titles/summaries/captions/content), vault state (locked/unlocked/unconfigured — never password/derived key), permission statuses (screen-recording/accessibility booleans); any field not in the positive enumeration is excluded by default; validate the output against `contracts/diagnostic-bundle.schema.json` in `Packages/StickyCore/Sources/SyncCore/DiagnosticBundle.swift` (or `Packages/StickyCore/Sources/Domain/DiagnosticBundle.swift` if Domain-only) per FR-191 (clarified 2026-08-07) / research R22 / contracts/diagnostic-bundle.schema.json / data-model §DiagnosticSnapshot / Constitution VI/VII/SC-010

- [X] T187 [P] [US2] Domain/Persistence test: verify sort-key gap = 1024 and renormalization threshold = 64 per FR-022a — assert `VersionLineage.standardGap == 1024`, `VersionLineage.normalizationThreshold == 64`; assert inserting a note between two keys uses the midpoint; assert that when any adjacent gap in a contiguous run falls below 64, the run is renormalized with 1024 gaps within a single transaction (verify no intermediate ordering is observable) in `Packages/StickyCore/Tests/DomainTests/SortKeyBindingTests.swift` per FR-022a / data-model §Conventions / Constitution IV

- [X] T188 [P] [US2] Persistence test: verify FTS5 `notes_fts` is an external-content table backed by canonical note rows with an explicit rowid-to-Note.id mapping per FR-023a — assert the table uses external-content mode (not contentless); assert deleting a note cascades to remove its FTS5 entry automatically; assert a drift-detection + rebuild-from-canonical path exists; assert the rowid-to-Note.id mapping is deterministic and stable across migrations in `Packages/StickyCore/Tests/PersistenceTests/FTS5ExternalContentTests.swift` per FR-023a / data-model §SearchDocument / Constitution IV

- [X] T189 [P] [US4] Domain/EditorCore test: verify todo nesting max depth = 6 per FR-072/FR-072a — assert `TodoHierarchyMaxDepth == 6`; assert indent is disabled when the active todo is at depth 6; assert validation rejects any todo hierarchy deeper than 6 levels; assert depth is counted from a top-level todo at depth 1 in `Packages/StickyCore/Tests/EditorCoreTests/TodoDepthBindingTests.swift` per FR-072a / data-model §TodoItem / Constitution V

- [X] T190 [P] [US9] SyncCore test: verify assets are synchronized as independent encrypted objects per FR-090a — assert each asset (original, thumbnail, app icon) is uploaded as its own encrypted envelope (never bundled inside a note envelope); assert each asset object carries a SHA-256 integrity hash; assert a failed asset upload does NOT block synchronization of the referencing note's metadata; assert the asset's sync state is set to `partialAssetSyncFailure` and retried independently on a subsequent sync run without re-encrypting or re-uploading already-succeeded note metadata in `Packages/StickyCore/Tests/SyncCoreTests/IndependentAssetSyncTests.swift` per FR-090a / data-model §Asset / Constitution IV/VIII

- [X] T191 [P] [US7] AssetStore test: verify thumbnail longest edge = 256px per FR-094a — assert `ThumbnailGenerator.defaultLongestEdge == 256`; assert generated thumbnails have a longest edge of exactly 256 pixels preserving aspect ratio; assert full-resolution screenshots and embedded images are NOT decoded for card-grid or widget rendering; assert thumbnail generation is lazy, off the main actor, and produces a stable hash for dedup in `Packages/StickyCore/Tests/AssetStoreTests/Thumbnail256BindingTests.swift` per FR-094a / plan §Asset storage / Constitution XI/SC-008

- [X] T192 [P] Persistence test: verify bounded busy timeout = 5 seconds per FR-140/FR-140a — assert `DatabaseStore` default `busyTimeout == 5.0`; assert widget read transactions are short enough to complete within the timeout; assert that on timeout the widget reports a sanitized "temporarily unavailable" status (never a raw error or note content) and retries on next refresh in `Packages/StickyCore/Tests/PersistenceTests/BusyTimeoutBindingTests.swift` per FR-140a / research R26 / Constitution XI

- [X] T193 [P] [US9] SyncCore test: verify sync debounce window = 2-4 seconds after last local change per FR-152a — assert the sync engine does NOT fire while local edits are still arriving within the window; assert it fires once 2-4 seconds have elapsed since the most recent change; assert the chosen value is deterministic for a given build (no random jitter that could starve sync indefinitely); assert the debounce is cancelable by a manual-sync trigger, application shutdown, or network change; assert the debounce does NOT block local editing (FR-153) in `Packages/StickyCore/Tests/SyncCoreTests/SyncDebounceBindingTests.swift` per FR-152a / research R25 / Constitution VIII/XI

- [X] T194 [P] [US9] SecurityCore test: verify meaningful-metadata positive enumeration per FR-160a — assert every field in the FR-160a enumeration (user-content fields from FR-161, semantic object types, structural metadata, note appearance/behavior choices, version-lineage fields) is encrypted before upload; assert a negative test: no field outside the FR-160b observable-leakage bound is left unencrypted; assert any newly added synchronized field is evaluated against the enumeration in `Packages/StickyCore/Tests/SecurityCoreTests/MeaningfulMetadataEnumerationTests.swift` per FR-160a/FR-160b / research R23 / Constitution VII

- [X] T195 [P] [US9] SecurityCore test: verify Argon2id production minimums per FR-160c — assert production vault bootstrapping rejects parameter sets weaker than memory ≥ 19456 KiB (19 MiB), iterations ≥ 2, parallelism ≥ 1; assert the schema minimums (8/1/1) are accepted ONLY for test fixtures; assert parameter values used at vault creation are stored alongside the wrapped master key so future unlocks reproduce the derivation exactly in `Packages/StickyCore/Tests/SecurityCoreTests/Argon2idProductionMinimumTests.swift` per FR-160c / research R9-refined / contracts/vault-bootstrap.schema.json / Constitution VII

- [X] T196 [P] [US9] SecurityCore test: exhaustive fail-closed input vectors per FR-160d — assert each of the eight enumerated inputs triggers fail-closed: (a) wrong password; (b) modified ciphertext (bit-flip/truncation/extension); (c) invalid/mismatched AES-GCM auth tag; (d) mismatched object ID; (e) mismatched object type; (f) mismatched vault ID; (g) unsupported envelope schema version; (h) corrupted/truncated envelope structure. For each: assert the object is rejected without writing local data, without accepting the remote object, and without overwriting a local version. Assert the list is exhaustive for the initial release in `Packages/StickyCore/Tests/SecurityCoreTests/FailClosedVectorTests.swift` per FR-160d / research R24 / contracts/encrypted-envelope.schema.json / Constitution VII/XII

- [X] T197 [US7] Change `ThumbnailGenerator.defaultLongestEdge` from 512 to 256 per FR-094a — update the default longest-edge pixel size to 256 for both card and widget thumbnails; update any call sites that pass a custom value to use 256 unless they are app-icon generation (which remains 128); update `ThumbnailTests.swift` expected dimensions; verify no full-resolution decode occurs in card-grid or widget paths in `Packages/StickyCore/Sources/AssetStore/ThumbnailGenerator.swift` per FR-094a / plan §Asset storage / Constitution XI/SC-008 — **current value is 512; must change to 256**

- [X] T198 [US9] Implement sync debounce window (2-4 seconds) in SyncEngine per FR-152a — add a debounce mechanism that coalesces local-change notifications and fires the sync engine once 2-4 seconds have elapsed since the most recent change; the chosen value MUST be deterministic for a given build (no random jitter that could starve sync indefinitely); MUST be cancelable by manual-sync trigger, application shutdown, or network change; MUST NOT block local editing (FR-153); wire the debounce into the existing sync trigger list (replacing the current `~3s` placeholder if present) in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` per FR-152a / research R25 / plan §Synchronization engine / Constitution VIII/XI — **no debounce logic currently exists in SyncEngine.swift**

- [X] T199 [US9] Enforce Argon2id production-minimum rejection in KeyDerivation per FR-160c — add a validation function that rejects parameter sets weaker than memory ≥ 19456 KiB, iterations ≥ 2, parallelism ≥ 1 when called in a production (non-test-fixture) context; the current defaults (65536/3/4) already exceed the minimums, but the rejection guard MUST be explicit so a future caller cannot accidentally use weaker params; store the parameter values used at vault creation in the bootstrap object alongside the wrapped master key in `Packages/StickyCore/Sources/SecurityCore/KeyDerivation.swift` per FR-160c / research R9-refined / contracts/vault-bootstrap.schema.json / Constitution VII — **current defaults are stronger than minimums but no explicit rejection guard exists**

- [X] T200 [US9] Extend fail-closed test vectors to exhaustive FR-160d list in SecurityCore — verify that the existing fail-closed error categories in `Domain/Errors.swift` (wrongPassword, modifiedCiphertext, invalidTag, wrongObjectContext, unsupportedEnvelopeVersion) cover all eight FR-160d inputs; split `wrongObjectContext` into the distinct mismatch cases (object ID, object type, vault ID) if not already distinguished; add the corrupted/truncated-envelope-structure case if missing; ensure each input has a deterministic test vector (T196) that asserts fail-closed behavior in `Packages/StickyCore/Sources/SecurityCore/EncryptedEnvelope.swift` and `Packages/StickyCore/Sources/Domain/Errors.swift` per FR-160d / research R24 / contracts/encrypted-envelope.schema.json / Constitution VII/XII — **error categories partially exist but are not exhaustive against the FR-160d list; `wrongObjectContext` may need splitting into distinct cases**

- [X] T201 [P] [US9] Verify FTS5 external-content mode in Persistence — inspect the existing FTS5 migration in `m0001_initial.swift` to confirm `notes_fts` is created as an external-content table (using `synchronize(withTable:)` or contentless-with-external-content); if the current implementation is contentless-with-rowid rather than external-content, refactor to external-content backed by canonical note rows with an explicit rowid-to-Note.id mapping per FR-023a; ensure note deletion cascades to the FTS5 entry automatically; add a drift-detection + rebuild-from-canonical path if absent in `Packages/StickyCore/Sources/Persistence/FullTextSearch.swift` and `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` per FR-023a / research R25 / data-model §SearchDocument / Constitution IV — **T157 fixed a stale FTS5 comment referencing `synchronize(withTable:)`; verify the actual mode matches FR-023a**

- [X] T202 [P] [US9] Verify independent-asset sync granularity in SyncEngine — inspect the existing sync engine to confirm assets are uploaded as independent encrypted objects (not bundled in note envelopes); if assets are currently bundled, refactor to independent per-object upload with SHA-256 integrity hash and independent partial-failure retry; ensure the `partialAssetSyncFailure` sync state is set when an asset upload fails and the asset is retried independently without re-uploading note metadata in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` per FR-090a / research R27 / data-model §Asset / Constitution IV/VIII — **`partialAssetSyncFailure` enum exists; verify the sync engine actually uses independent asset objects**

- [X] T203 [P] [US1] Domain test: first-launch hint state machine per FR-014a — assert `FirstLaunchState` returns `shouldShowOnboardingHint == true` on a fresh state (seen=false, dismissed=false, hasCreatedFirstNote=false); returns `false` once `hasCreatedFirstNote` is set (never shown again after the first note is created); returns `false` once `dismissed` is set; returns `false` when dismissed even if `seen`; assert the state never carries sync/canonical-JSON exposure (pure value type, no UserDefaults dependency) in `Packages/StickyCore/Tests/DomainTests/FirstLaunchStateTests.swift` per FR-014a / research R28 / data-model §LocalPreferences / Constitution X/IV

- [X] T206 [US1] Implement `FirstLaunchState` value type in `Packages/StickyCore/Sources/Domain/Models/FirstLaunchState.swift` — pure Foundation-only state machine (seen/dismissed/hasCreatedFirstNote) with `shouldShowOnboardingHint` per FR-014a; no UserDefaults or App Group references in Domain (storage lives in the App layer, T207); satisfies T203 per FR-014a / research R28 / data-model §LocalPreferences / Constitution X/IV

- [X] T207 [US1] Implement device-local persistence of first-launch state in `App/Sources/Features/Library/LocalPreferences.swift` — store `onboardingHintSeen`, `onboardingHintDismissed`, `hasCreatedFirstNote` in App Group UserDefaults (device-local only; NEVER synchronized, NEVER in canonical JSON, NEVER in exported diagnostics per FR-191/data-model §LocalPreferences); set `hasCreatedFirstNote` on first-note creation; wire into `AppEnvironment` per FR-014a / research R28 / data-model §LocalPreferences / Constitution IV/VI

- [X] T210 [US1] Enforce no-permission-prompts-on-first-launch guard — verify `PermissionService` (T104) is invoked ONLY when the user invokes the feature requiring it (screen-recording on capture invocation, accessibility never on startup); assert the startup path (`AppEnvironment`/`StickyNotesApp.swift`) performs no permission request; any request during launch is a regression per FR-014a/FR-131 in `App/Sources/App/AppEnvironment.swift` and `Packages/StickyCore/Sources/SystemBridge/PermissionService.swift` per FR-014a / Constitution VI

- [X] T212 [P] [US6] Domain test: FR-012a meaningful-text boundary — assert a note is auto-removable on close ONLY when it has never contained meaningful content, where "meaningful content" = (a) at least one non-whitespace Unicode character in the title field, OR (b) at least one non-whitespace Unicode character in any rich-text block, OR (c) the presence of any todo/image/screenshot/code-block/file-reference block regardless of text length. Test matrix: whitespace-only title+body → auto-removable; single Latin letter in body → NOT auto-removable; single CJK character → NOT auto-removable; single emoji → NOT auto-removable; single punctuation char → NOT auto-removable; empty todo block present → NOT auto-removable (structural block); note that previously held content, now emptied → NOT auto-deleted (FR-013). Assert the rule is Unicode-whitespace-aware (spaces, tabs, newlines, U+3000 ideographic space, etc. do NOT qualify) in `Packages/StickyCore/Tests/DomainTests/MeaningfulTextBoundaryTests.swift` per FR-012a / research R30 / Constitution III/XII

- [X] T213 [P] [US9] SecurityCore test: FR-160e no-rate-limit on wrong-password unlock — assert any number of consecutive wrong-password unlock attempts yields the same fail-closed behavior (per FR-160d (a)) with NO state accumulation, NO increasing delay, NO lockout, NO attempt counter, and NO caching of the supplied password or derived key; assert a correct password succeeds immediately after N wrong attempts with no residual throttle; assert a single Argon2id derivation with FR-160c production minimums takes ≥100 ms on reference hardware (sanity bound confirming KDF-cost rate limiting) in `Packages/StickyCore/Tests/SecurityCoreTests/NoLockoutPolicyTests.swift` per FR-160e / research R31 / contracts/encrypted-envelope.schema.json / Constitution VII/VI

- [X] T214 [P] [US6] Persistence test: FR-022a Trash-restore sort-key reset — delete a note from the middle of Manual order (sort-key S_mid); insert a new note (which may reuse the freed position); restore the deleted note → assert the restored note's `manualSortKey` equals (max(active sort-key) + 1024), NOT S_mid; assert it appears at the end of Manual order; assert no renormalization is triggered by restore alone (the new key is strictly greater than all existing keys); assert ordering of other notes is unchanged in `Packages/StickyCore/Tests/PersistenceTests/TrashRestoreSortKeyTests.swift` per FR-022a (clarified 2026-08-07) / research R32 / data-model §Conventions/Note lifecycle / Constitution IV/XII/X

- [X] T215 [P] [US9] SecurityCore test: FR-162a app-launch unlock via boot timestamp — assert when `rememberedUnlock = enabledUntilLockOrRestart` AND `rememberedUnlockBootTimestamp` equals the current system boot timestamp AND vault not explicitly locked → app launch silently restores the unlocked vault state from Keychain and triggers startup sync per FR-152a without prompting; assert when boot timestamp differs (simulated restart) → launch prompts for password; assert when `rememberedUnlock = disabled` → launch prompts; assert when vault explicitly locked → launch prompts; assert the boot-timestamp comparison is the sole restart-detection mechanism (no login-item/daemon dependency) in `Packages/StickyCore/Tests/SecurityCoreTests/AppLaunchUnlockTests.swift` per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/XII

- [X] T216 [P] [US9] SecurityCore test: FR-162a toggle-off while unlocked — assert toggling `rememberedUnlock` from `enabledUntilLockOrRestart` to `disabled` while the vault is currently unlocked: (a) immediately removes the remembered key from Keychain (clears `rememberedUnlockKeychainRef` and `rememberedUnlockBootTimestamp`); (b) preserves the current unlocked vault state in memory (no re-prompt, no forced lock); (c) a subsequent app launch (without restart) prompts for the password (Keychain item gone); (d) explicit lock still works and clears the in-memory key. Assert the application MUST NOT force a re-prompt merely because the setting was toggled off in `Packages/StickyCore/Tests/SecurityCoreTests/RememberUnlockToggleTests.swift` per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/X

- [X] T217 [US6] Pin FR-012a meaningful-text threshold in auto-discard logic — define a `Note.hasMeaningfulContent(for autoDiscard:)` predicate (or equivalent) in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` (extends T079) that returns `true` when the title or any rich-text block contains ≥1 non-whitespace Unicode character OR any todo/image/screenshot/code-block/file-reference block is present; wire it into the empty-note auto-discard hook in `NoteWindowCoordinator` (T081/T167) so the auto-removal decision uses this exact rule; update `EmptyNoteDiscardTests.swift` (T077) expected cases to match FR-012a if they currently use a looser/stiffer threshold in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` per FR-012a / research R30 / Constitution III/XII — **T077/T081 cover the concept but do not pin the one-non-whitespace-character threshold; this task makes it exact**

- [X] T218 [US9] Enforce FR-160e no-lockout policy in SecurityCore — audit `Packages/StickyCore/Sources/SecurityCore/` (VaultBootstrap.swift, KeyDerivation.swift, and any unlock entry point) to confirm there is NO attempt counter, NO timed backoff, NO lockout state, and NO caching of the supplied wrong password or derived key; if any such mechanism exists, remove it; add an explicit invariant comment + guard that wrong-password unlock is stateless and relies solely on the Argon2id KDF cost (FR-160c) for rate limiting; verify the unlock path calls the Argon2id derivation on every attempt (no short-circuit) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` per FR-160e / research R31 / contracts/encrypted-envelope.schema.json / Constitution VII/VI — **audit + guard; remove any latent lockout logic if present**

- [X] T219 [US6] Implement FR-022a Trash-restore sort-key reset in NoteLifecycle/NoteRepository — when a note transitions trashed → active (restore), set its `manualSortKey` to (current maximum `manualSortKey` among active notes) + 1024 within the same restore transaction; do NOT retain the pre-deletion sort-key; verify the new key is strictly greater than all existing active keys so no renormalization is triggered by restore alone in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` (extends T079) and `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift` (extends T030) per FR-022a (clarified 2026-08-07) / research R32 / data-model §Conventions/Note lifecycle / Constitution IV/XII/X — **restore path exists (T079) but does not reset the sort-key; this task adds the reset**

- [X] T220 [US9] Implement FR-162a app-launch unlock + boot-timestamp detection in SecurityCore/VaultConfiguration — add `rememberedUnlockBootTimestamp: Int?` field to `VaultConfiguration` (device-local); at remember-time, capture the system boot timestamp (via `sysctl kern.boottime` or equivalent — exact API confirmed in M0 per research R33) and store it alongside the Keychain reference; at app launch with auto-sync enabled, compare the stored timestamp against the current boot timestamp: if `rememberedUnlock = enabledUntilLockOrRestart` AND timestamps match AND vault not explicitly locked → silently restore the unlocked vault state from Keychain and trigger startup sync per FR-152a without prompting; otherwise prompt for the password. Add a migration for the new `VaultConfiguration` column if the table already exists in `Packages/StickyCore/Sources/SecurityCore/VaultConfiguration.swift` (or Domain model per T011), `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` (extends T112), and `Packages/StickyCore/Sources/Persistence/Migrations/` per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/XII — **no boot-timestamp detection exists; this task implements it**

- [X] T221 [US9] Implement FR-162a toggle-off behavior in SecurityCore/Settings — when the user toggles `rememberedUnlock` from `enabledUntilLockOrRestart` to `disabled` while the vault is currently unlocked: immediately remove the remembered key from Keychain (clear `rememberedUnlockKeychainRef` and `rememberedUnlockBootTimestamp`); preserve the current unlocked vault state in memory until the user explicitly locks the vault or the application exits; do NOT force a re-prompt or forced lock; wire the toggle handler into the sync Settings UI (T119) in `Packages/StickyCore/Sources/SecurityCore/VaultConfiguration.swift` and `App/Sources/Features/Settings/SyncSettingsView.swift` (extends T119) per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/X — **no toggle-off-specific behavior exists; this task adds immediate Keychain clearance + session preservation**


## 2026-08-07 — /speckit.implement convergence run

Implemented the remaining convergence surface (Phases 3–25). Key outcomes:

- **Domain (T234/T257/T252/T225)**: FR-040a canonical sRGB hexes
  (#FFE08A/#F9A8C4/#C9A8E8/#A8CFF9/#A8E8B8/#D8D8DC); FR-041a opacity
  0.40–1.00 in 0.05 steps (field `transparency` retained, semantic =
  opacity); FR-043a textSize enum → integer 9–24 pt default 13 (Domain
  model, canonical JSON, v1 schema column, all tests). NoteAppearance now
  validates against the composited background below 100% opacity.
- **Domain additions (T142/T147, T233/T224, T247/T248, T274/T278,
  T279)**: FontPreference (CJK fallback selection); NoteDocumentSerializer
  (FR-031a export/import, fail-closed, asset sidecar); NoteMarkdownSerializer
  + NoteDuplicator (FR-031); FileAvailability gains `onAnotherDevice`
  (FR-100 four-state model); identical-summary collision acceptance
  (FR-021 — verified no disambiguation existed).
- **Persistence (T134/T172, T171/T128, T231/T222, T236/T227, T238/T229,
  T260)**: CardProjection (lazy bounded card projections + FR-072b progress
  strings); SQLiteTombstoneRepository (30-day sync-safety-gated retention);
  `emptyTrash` batch (FR-014b) with per-note tombstones; ScaleLimits
  (FR-090b) enforced at asset-store + repository boundaries; autosave 500 ms
  verified deterministic + crash-loss contract tests; cover-screenshot
  nullification tests (FR-094b). Migration v2 `conflictRecord` added.
- **EditorCore (T161, T235/T226, T259/T254, T143/T148, T205)**: RichTextAdapter;
  BlockMergeOperation (FR-050a empty-block removal, IME-safe, final-block
  preserved); CrossBlockSelectionCore (FR-054 plain+RTF copy, range delete);
  AutoLinkDetector (FR-050); keystroke-latency signpost tests (SC-004a).
- **SystemBridge (T160/T146, T165, T166, T255)**: NoteWindowBridge (registry,
  focus, FR-035 collectionBehavior), WindowLevelBridge, DisplayChangeBridge
  (FR-034 frame correction), SecurityScopedBookmarks + FileDragOutBridge
  (FR-100/FR-102/FR-103), MenuBarWindowFrame (FR-001a) — all with headless
  tests (T163c/T163e/T250/T151).
- **SyncCore (T171, T184, T232)**: SyncConflictResolver + ConflictCopyBuilder
  (deterministic dedup via v2 `conflictRecord`); OfflineReconciler with the
  FR-174 tombstone-purge refinement; sort-key last-writer-wins (FR-022b)
  wired into the engine; `applyRemoteTombstone` lineage fix (tombstones now
  carry the deleted version + parent; delete-vs-edit recovers the divergent
  local edit as a conflict copy). Tests: T163k–o, T179, T223, T242.
- **App layer (T159–T172, T208–T211, T237, T255–T259, T268–T273,
  T278–T280)**: full menu-bar library scene (search/sort/new/Trash/sync
  status/Settings/About/Quit + FR-001a positioning), NoteWindowCoordinator,
  editor block views (rich text/todo/code/file-ref/screenshot/image +
  FR-050b unified container), NoteControlsView (FR-031/FR-041a/FR-043a +
  contextual menu per FR-031/FR-112), TrashView (FR-014b/FR-014c),
  ScreenshotViewer (FR-095a bounded zoom), Settings/SyncSettings/About/
  FontPreference, DeepLinkRouter, DeletionToastPresenter (FR-009a),
  WidgetRefreshCoordinator (FR-110a), AccessibilityAdaptations (FR-180b).
- **WidgetExtension (T169, T280)**: 6 families + AppIntents + privacy-safe
  snapshots + FR-140a/FR-112 temporarily-unavailable fallback. Note: the
  Xcode-27-beta toolchain ICEs on `AppIntentConfiguration` with a custom
  AppEntity — the selected-note/todo widgets use StaticConfiguration with
  the intent surface preserved for actions (documented in code).
- **AppTests (T163a/b, T204, T228, T230, T245, T251, T266, T135a + trace-
  ability files)**: integration + logic tests all green.
- **Release/docs (T137, T136, T249, T239)**: release.yml (Developer ID +
  notarization, encrypted secrets only); architecture/privacy/security
  docs; xcodeproj reconciliation resolved (option b — committed project +
  CI drift check; quickstart + project.yml updated); Localizable.xcstrings
  extended to 145 keys, all zh-Hans + en (FR-180a).
- **T174 resolved (option b)**: T025a's GUI-verification deferral is now
  documented in the artifact itself; T158 stays open (needs a Mac with a
  display). **T175 resolved (option b)**: T096/T097 point at
  ShortcutDockTests.swift.

Schema note: v1 schema was changed in place (textSize TEXT→INTEGER) — the
v1 migration never shipped (single-commit pre-release repo; fixtures are
code-built). Migration v2 adds the `conflictRecord` table. Widget schema
support version bumped to v2.

## 2026-08-07 — /speckit.implement completion note (post-run audit)

- 166 tasks marked `[X]` in this run; the only remaining open task is
  **T158** (interactive verification of the Milestone 0 GUI prototypes),
  which requires a Mac with a display (documented deferral per T174).
- Verification: `swift test --package-path Packages/StickyCore` — 578 tests
  green across 7 suites (Domain/Persistence/EditorCore/AssetStore/
  SecurityCore/SyncCore/SystemBridge). `xcodebuild build-for-testing`
  (StickyNotes scheme, Debug, CODE_SIGNING_ALLOWED=NO) green; AppTests 25
  tests green (13 suites). UI-driven XCUITest journeys (AppUITests) compile
  and run on CI machines with a display.
- Local build note: with github.com unreachable, xcodebuild package
  resolution needs `-clonedSourcePackagesDirPath` pointed at a checkout
  mirror + `-skipPackageUpdates`; normal CI resolves from the network.

## 2026-08-09 — AppUITests click journeys cancelled (product decision)

- All synthetic-click XCUITest journeys in `AppUITests/CriticalFlowsUITests.swift`
  were **cancelled** per product decision: automated macOS click tests proved
  unreliable — 14 of 15 tests fail in headless sessions on macOS 27 beta
  (menu-bar hit-testing races, permission-gated overlay drags), so the suite
  never provided stable CI signal. Kept only `testMenuBarOpenAndDismiss`
  (launch smoke test, no clicks). Interactive flows (FR-009/FR-005/FR-006/
  FR-014/FR-095/FR-030/FR-050/FR-010/FR-070/SC-017/FR-072/FR-001 dropdown)
  remain covered by AppTests unit/integration suites + manual QA
  (quickstart.md §Manual testing).
- Removed with the journeys: the `-UITestSeedNote` app-side seeding hook
  (`StickyNotesApp.seedUITestNoteIfRequested`) — test-only, only used by the
  cancelled journeys.
- CI: `ui-smoke` job reduced to the unsigned launch smoke test (ad-hoc
  signing step removed); quickstart.md §Running the XCUITest critical flows
  rewritten accordingly.
