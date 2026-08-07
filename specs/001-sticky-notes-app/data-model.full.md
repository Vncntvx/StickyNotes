# Data Model: macOS Sticky Notes

**Feature**: 001-sticky-notes-app | **Date**: 2026-08-06 | **Plan**: [plan.md](./plan.md)

This document defines the durable data model. It is the authoritative source for
`Persistence` migrations and for the canonical/encryption contracts in
`contracts/`. All durable entity identifiers are UUIDs. All timestamps are UTC
ISO 8601. The model separates **synchronized** data (replicated encrypted via
the canonical format) from **device-local** data (never leaves the device).

## Conventions

- **ID type**: UUID v4 strings (`xxxxxxxx-xxxx-4xxx-xxxx-xxxxxxxxxxxx`), stored
  as `TEXT` in SQLite and as JSON strings in canonical form.
- **Timestamps**: UTC, ISO 8601, stored as `TEXT` (SQLite) / ISO strings
  (canonical). Column names: `createdAt`, `modifiedAt`, etc.
- **Sort keys**: ordered integers with a 1024 gap (e.g., 0, 1024, 2048) so a
  drag usually changes only the moved row (FR-022a). Normalization: when the
  gap between two neighbors drops below 64, renumber the contiguous run by
  1024 steps within a single transaction (FR-022a). **Trash restore
  (FR-022a, clarified 2026-08-07)**: when a note is restored from Trash, its
  `manualSortKey` MUST be reset to (current maximum sort-key among active
  notes) + 1024, placing it at the end of Manual order. The pre-deletion
  sort-key MUST NOT be retained (notes may have been inserted or reordered
  during the note's absence, invalidating the original position). The new
  key is strictly greater than all existing keys, so restore alone never
  triggers renormalization.
- **Version lineage** (synced entities): `versionId` (UUID, per mutation),
  `parentVersionId` (UUID, previous version; nil for the initial version),
  `lastModifiedDeviceId` (UUID), `modifiedAt` (UTC).
- **Sync flags**: `isDirty` (local change not yet pushed), `lastSyncedVersionId`
  (last version confirmed remote).
- **Soft states**: lifecycle is explicit (see State Transitions), not inferred
  from deletion.

## Entities

### Note

The unit a user creates, edits, and retrieves.

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| id | UUID | yes | stable note identity |
| title | TEXT (nullable) | yes | optional manual title; nil ⇒ generated summary is display-only |
| colorKey | enum | yes | yellow/pink/purple/blue/green/gray/custom; built-ins have one canonical sRGB hex each (FR-040a): yellow #FFE08A, pink #F9A8C4, purple #C9A8E8, blue #A8CFF9, green #A8E8B8, gray #D8D8DC |
| customColor | TEXT (nullable) | yes | hex/rgb when colorKey=custom |
| transparency | REAL | yes | background opacity, 0.40–1.00 inclusive, 0.05 steps, default 1.00 (FR-041a; below 1.00 the FR-042 contrast logic validates against the composited background); field name retained from v1 — semantic is opacity (FR-041a), not transparency |
| textSize | INTEGER | yes | per-note text size in points, 9–24 inclusive, 1-pt steps, default 13 (FR-043a); text ≥18 pt is large text for the FR-042 contrast thresholds |
| alwaysOnTop | INT (bool) | yes | per-note floating |
| widgetEligible | INT (bool) | yes | per-note widget privacy gate |
| coverScreenshotBlockId | UUID (nullable) | yes | at most one cover; FK Block |
| manualSortKey | INT | yes | manual-order sort key |
| lifecycleState | enum | yes | active/trashed/permanentlyDeleted/conflictCopy |
| trashedAt | TEXT (nullable) | local+meta | set on trashing; drives 30-day expiry |
| conflictOriginNoteId | UUID (nullable) | yes | set on conflict copies |
| conflictLabel | TEXT (nullable) | yes | origin/time label |
| versionId | UUID | yes | per-mutation version |
| parentVersionId | UUID (nullable) | yes | lineage |
| lastModifiedDeviceId | UUID | yes | |
| createdAt | TEXT | yes | |
| modifiedAt | TEXT | yes | |

**State transitions**: see *State Transitions* below.

### Block

Ordered content within a note. Categories: richText, todo, code, fileRef,
image, screenshot.

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| id | UUID | yes | stable block identity |
| noteId | UUID | yes | FK Note |
| kind | enum | yes | block category |
| sortKey | INT | yes | 1024-gap ordering |
| payload | JSON (canonical) | yes | kind-specific canonical payload (see contracts) |
| versionId | UUID | yes | per-mutation |
| parentVersionId | UUID (nullable) | yes | |
| lastModifiedDeviceId | UUID | yes | |
| createdAt | TEXT | yes | |
| modifiedAt | TEXT | yes | |

The `payload` is the canonical block payload (rich-text document, code text,
file-ref metadata, image metadata, screenshot association). Device-local
locator data lives in a separate table (never in payload).

### TodoItem

A todo block's identity/hierarchy. (Todo text lives in the block's rich-text
payload; identity/hierarchy is separate for stability across reorders/edits.)

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| id | UUID | yes | stable todo identity, independent of text |
| noteId | UUID | yes | FK Note |
| blockId | UUID | yes | FK Block (the todo block) |
| parentTodoId | UUID (nullable) | yes | explicit hierarchy (subtask) |
| sortKey | INT | yes | 1024-gap ordering |
| depth | INT | yes | nesting depth; max 6 (FR-072a) |
| isComplete | INT (bool) | yes | completion state |
| versionId | UUID | yes | |
| parentVersionId | UUID (nullable) | yes | |
| lastModifiedDeviceId | UUID | yes | |
| createdAt | TEXT | yes | |
| modifiedAt | TEXT | yes | |

**Validation**: no cycles (parent chain must terminate); parent must be in the
same note; depth ≤ 6 (FR-072a); sort-key collisions normalize; deleting a
parent does not orphan children (children reparented to grandparent or flagged
— see *State Transitions*).

### Asset

A binary asset stored outside SQLite in the App Group container (originals,
thumbnails, app icons). Referenced by blocks.

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| id | UUID | yes | asset identity |
| kind | enum | yes | original/thumbnail/appIcon |
| contentHash | TEXT (SHA-256) | yes | dedup + corruption detection |
| byteSize | INT | yes | |
| contentType | TEXT | yes | UTType identifier |
| storagePath | TEXT (opaque) | local | relative path under App Group (device-local filename; not a user path) |
| isSynced | INT (bool) | local | whether asset bytes are confirmed remote |
| syncFailureState | enum (nullable) | local | partial-asset-sync-failure marker |
| createdAt | TEXT | yes | |

Asset *bytes* are synchronized as independent encrypted objects (FR-090a) —
never bundled inside an encrypted note envelope; the `storagePath` is
device-local only. Each asset object carries a SHA-256 `contentHash`
(Constitution IV) for dedup and corruption detection, and is independently
retried on partial upload/download failure (Constitution VIII). A failed
asset upload MUST NOT block synchronization of the referencing note's
metadata; the asset's `syncFailureState` is set to
`partialAssetSyncFailure` so it retries independently on the next sync run.
`contentHash` enables dedup (two notes pasting the same image share one asset
object remotely and can share bytes locally via reference counting).
Thumbnails use a 256px longest edge (FR-094a) — the single canonical
thumbnail size for card-grid and widget display.

### ScreenshotAssociation

Metadata linking a screenshot asset to a note block, plus origin context.

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| blockId | UUID | yes | FK Block (screenshot block) |
| noteId | UUID | yes | FK Note |
| originalAssetId | UUID | yes | FK Asset (original) |
| thumbnailAssetId | UUID | yes | FK Asset (thumbnail) |
| appIconAssetId | UUID (nullable) | yes | FK Asset (app icon snapshot) |
| applicationName | TEXT (nullable) | yes | captured-window app name |
| windowTitle | TEXT (nullable) | yes | captured-window title |
| caption | TEXT (nullable) | yes | user caption |
| capturedAt | TEXT | yes | capture date/time |
| isCover | INT (bool) | yes | at most one per note (transactional) |

### FileReference (synchronized metadata)

Generic, safe metadata for a file-reference block. **No bookmark bytes, no
absolute paths.**

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| blockId | UUID | yes | FK Block (fileRef block) |
| displayName | TEXT | yes | file name only |
| contentType | TEXT | yes | UTType |
| approximateSize | INT (nullable) | yes | bytes, best-effort |
| originDeviceId | UUID | yes | where the reference was created |
| addedAt | TEXT | yes | |
| caption | TEXT (nullable) | yes | |

### FileLocator (device-local)

Durable local access to a referenced file. **Never synchronized.**

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| blockId | UUID | local | FK Block (fileRef block) |
| bookmarkData | BLOB | local | security-scoped bookmark bytes |
| lastResolvedPath | TEXT | local | last known absolute path (display/stale check only) |
| availabilityStatus | enum | local | available/stale/missing/relinked |
| stale | INT (bool) | local | |
| verifiedAt | TEXT (nullable) | local | last successful access check |

### WindowState (device-local)

Per-note window geometry + display preferences. **Never synchronized.** Not
restored after relaunch is a *behavior* (FR-007); the geometry is still stored
so a reopened note returns to its frame.

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| noteId | UUID | local | FK Note |
| frame | TEXT (JSON) | local | {x,y,w,h} preferred frame |
| preferredDisplayUUID | TEXT (nullable) | local | display the note prefers |
| fallbackFrame | TEXT (nullable) | local | temp frame when preferred display disconnected |
| isOpen | INT (bool) | local | current open-window registry |
| lastOpenedAt | TEXT (nullable) | local | |

### Tombstone

Deletion record for synchronization. Retained 30 days (sync-safety-gated).

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| noteId | UUID | yes | the deleted note |
| deletedVersionId | UUID | yes | version at deletion |
| parentVersionId | UUID (nullable) | yes | lineage |
| deletingDeviceId | UUID | yes | |
| deletedAt | TEXT | yes | drives 30-day retention |
| purgedAt | TEXT (nullable) | local | when readable local content was removed |
| canPurgeRemote | INT (bool) | local | sync-safety check result |

### SyncState (device-local)

Per-vault synchronization scheduling/progress (vault-level run state; distinct from the per-entity `SyncVersionState` enum). **Never synchronized.**

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| vaultId | UUID | local | |
| providerType | enum | local | webdav/s3 |
| lastSuccessfulSyncAt | TEXT (nullable) | local | |
| lastError | TEXT (nullable) | local | sanitized error code |
| inProgress | INT (bool) | local | |
| pendingSince | TEXT (nullable) | local | |
| config | JSON (redacted) | local | endpoint/region/bucket/prefix; no secrets |

### DiagnosticSnapshot (device-local, never synchronized, never logged with content)

Aggregate, sanitized snapshot used to populate the user-exportable diagnostic
bundle (FR-191, clarified 2026-08-07). **All fields are positively enumerated;
any field not listed here is excluded by default.** No note content, titles,
summaries, captions, file names/paths, window titles, credentials, passwords,
key material, raw server responses, or remote object names appear here or in
the exported bundle.

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| appVersion | TEXT | local | bundle/marketing version |
| osVersion | TEXT | local | macOS version |
| schemaVersion | INT | local | local DB schema version |
| providerType | enum (nullable) | local | webdav/s3, or null if sync unconfigured (never endpoint/hostname/credentials) |
| recentErrorEvents | JSON array | local | last 30 days; each entry = {timestamp, normalizedErrorCategory}; never raw server responses/bodies |
| syncRunCounts | JSON | local | {last24h, last7d, last30d} counts + durations (no payloads/object names) |
| objectCounts | JSON | local | {notes, blocks, assets} aggregate counts (no titles/summaries/captions/content) |
| vaultState | enum | local | locked/unlocked/unconfigured (never password or derived key) |
| permissionStatuses | JSON | local | {screenRecording: bool, accessibility: bool} |

### DeviceIdentity

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| id | UUID | yes | stable device identity |
| displayName | TEXT | local | user-facing name (NOT synced to remote as meaningful metadata) |
| createdAt | TEXT | yes | |

### LocalPreferences (device-local, never synchronized)

Non-sensitive local preferences. Not a database table — stored in App Group
UserDefaults, never in SQLite, never in canonical JSON, never synchronized
(FR-014a, FR-191 boundary).

| Key | Type | Notes |
|-----|------|-------|
| `onboardingHintSeen` | bool | first-launch hint shown at least once (FR-014a) |
| `onboardingHintDismissed` | bool | user dismissed the hint (FR-014a) |
| `hasCreatedFirstNote` | bool | set when the first note is created; once true the hint is never shown again (FR-014a) |

These keys are app-side UI state; the Widget Extension does not read them.
They MUST NOT appear in exported diagnostics (FR-191).

### VaultConfiguration (device-local reference)

Points at a configured vault + provider. **Secrets live in Keychain, not here.**

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| vaultId | UUID | local | matches the bootstrap's vault ID |
| vaultLocator | TEXT (opaque) | local | random remote locator |
| providerType | enum | local | webdav/s3 |
| providerConfig | JSON (redacted) | local | endpoint/region/bucket/prefix |
| keychainCredentialRef | TEXT | local | Keychain account label (no secret value) |
| rememberedUnlock | enum | local | disabled / enabledUntilLockOrRestart (FR-162a) |
| rememberedUnlockKeychainRef | TEXT (nullable) | local | Keychain account label for remembered unwrapped key, only when rememberedUnlock ≠ disabled; cleared on explicit lock; not a login-item daemon (does not survive logout/restart) |
| rememberedUnlockBootTimestamp | INT (nullable) | local | System boot timestamp captured at remember-time, used to detect Mac restart (FR-162a, clarified 2026-08-07). On app launch, if the current boot timestamp differs, the remembered key is treated as stale and the password is required. |
| createdAt | TEXT | local | |
| replacedFromVaultLocator | TEXT (nullable) | local | when this vault replaced a prior one (FR-154), the prior locator is recorded here for user reference; the prior remote data is NOT auto-deleted |

**`rememberedUnlock` semantics (FR-162a, clarified 2026-08-07)**:

- `disabled` (default): password required on every sync-triggering app launch.
- `enabledUntilLockOrRestart`: the unwrapped vault key may be stored in a
  Keychain item (referenced by `rememberedUnlockKeychainRef`) so that ordinary
  app relaunches do not re-prompt for the password. The Keychain item MUST be
  cleared on explicit lock. The application MUST NOT behave as a login-item-
  bound daemon that keeps the vault unlocked across system logout or restart;
  after logout/restart, the password is required again. Forgetting the
  synchronization password remains unrecoverable regardless of this setting
  (FR-163).
- **App-launch unlock (FR-162a, clarified 2026-08-07)**: at application launch
  with auto-synchronization enabled, (a) if `rememberedUnlock =
  enabledUntilLockOrRestart` AND `rememberedUnlockBootTimestamp` equals the
  current system boot timestamp AND the user has not explicitly locked the
  vault, the application silently restores the unlocked vault state from
  Keychain and triggers startup synchronization per FR-152a without
  prompting; (b) otherwise (remember disabled, Mac restarted, or vault
  locked), the application prompts for the synchronization password before
  any synchronization occurs. The boot-timestamp comparison makes the
  "restart clears remember" rule objectively testable and eliminates reliance
  on login-item or daemon behavior.
- **Toggle-off while unlocked (FR-162a, clarified 2026-08-07)**: when the user
  toggles `rememberedUnlock` from `enabledUntilLockOrRestart` to `disabled`
  while the vault is currently unlocked, the application immediately removes
  the remembered key from Keychain (clearing `rememberedUnlockKeychainRef`
  and `rememberedUnlockBootTimestamp`) so future launches will not silently
  restore, but preserves the current unlocked vault state in memory until
  the user explicitly locks the vault or the application exits. The
  application MUST NOT force a re-prompt merely because the setting was
  toggled off — explicit lock remains a separate, intentional user action.

### SearchDocument (FTS5)

One searchable row per note. Rebuilt transactionally on note change.

| FTS column | Source |
|------------|--------|
| title | Note.title |
| summary | generated summary source text |
| body | concatenated rich-text plain text |
| todos | todo plain text |
| code | code-block text |
| fileNames | file-reference display names |
| captions | screenshot captions |
| ocr | (future OCR text; empty in v1) |

FTS5 table `notes_fts` is an **external-content table** backed by the
canonical note/block rows, with an explicit rowid-to-`Note.id` mapping
(FR-023a). The external-content design guarantees the index cannot drift from
canonical data: note deletion cascades to the FTS5 entry automatically. If
drift is detected, the index is rebuilt from canonical data without loss.
Scope filter excludes trashed/permanently-deleted notes by default; a separate
Trash scope query is provided.

## Relationships

```text
Note 1───* Block
Block 1───1 (todo)      TodoItem
Block 1───1 (screenshot) ScreenshotAssociation ──* Asset
Block 1───1 (image)     Asset (original+thumbnail)
Block 1───1 (fileRef)   FileReference (synced)  ──1 FileLocator (local)
Note 1───* Tombstone (lifecycle)
Note 1───1 WindowState (local)
Note 1───1 SearchDocument (FTS)
VaultConfiguration 1───1 SyncState
DeviceIdentity *───* (Note.lastModifiedDeviceId, Tombstone.deletingDeviceId, …)
```

## Constraints

- `Block.noteId` → `Note.id` (cascade on note permanent purge).
- `TodoItem.parentTodoId` → `TodoItem.id` within the same `noteId`; no cycles;
  `depth ≤ 6` (FR-072a).
- `Note.coverScreenshotBlockId` → `Block.id` where `Block.kind = screenshot`;
  at most one `ScreenshotAssociation.isCover = true` per note (enforced in a
  transaction).
- `Asset.contentHash` unique among same `kind`+`contentType` for dedup.
- `FileLocator` is 1:1 with a `fileRef` block; bookmark bytes never appear in
  `FileReference` or canonical JSON.
- Sort keys: 1024-gap; normalize contiguous runs when gap < 64 (FR-022a).
- **Sort-key sync reconciliation (FR-022b, clarified 2026-08-07)**: sort-key
  divergence across devices is reconciled per-note by last-writer-wins (most
  recently written sort key via the note's version timestamp/sequence); it
  never triggers a conflict copy. Content divergence is evaluated on content
  fields only. (Enforced in `SyncCore`, not as a DB constraint.)
- **Scale limits (FR-090b, clarified 2026-08-07)**: a single asset must be
  ≤ 50 MB raw and ≤ 16,384 px on the longest edge after capture/paste
  normalization; a single note's structured content (canonical envelope before
  asset payloads) must be ≤ 5 MB. Oversize insertions are rejected with no
  partial write; oversize content changes are refused while preserving the
  last valid saved state. Enforced at the persistence/asset-store boundary.
- Lifecycle invariants: a `permanentlyDeleted` note retains a `Tombstone` until
  sync-safety allows purge.
- **Wrong-vault detection (FR edge case, clarified 2026-08-07)**: the bootstrap
  object's `vaultId` is authoritative. If a configured or newly-chosen
  repository contains a bootstrap whose `vaultId` ≠ the locally-configured
  `vaultId` (or, for a brand-new vault, a bootstrap already exists under the
  chosen locator), the application MUST fail closed with a typed
  `Encryption.wrongVaultContext` / `Credentials.wrongVault` error, MUST NOT
  modify any local or remote data, and MUST prompt the user to choose a
  different repository or start a new empty vault under a fresh random locator
  (which bootstraps alongside the existing one without overwriting it). This is
  enforced in `SecurityCore` / `SyncCore`, not as a DB constraint, but the data
  model guarantees `VaultConfiguration.vaultId` is the single source of truth
  for the comparison.

## State Transitions

### Note lifecycle

```text
            create
              │
              ▼
          ┌────────┐  delete         ┌────────┐  30-day expiry / manual purge ┌──────────────┐
          │ active │ ───────────────▶│ trashed│ ────────────────────────────▶│ permanently  │
          └────────┘                 └────────┘                                │ deleted      │
              ▲  ▲  restore            │  restore                                │ (+tombstone) │
              │  └─────────────────────┘                                         └──────────────┘
              │                          │
              │                          │ sync delete-vs-edit
              │                          ▼
              │                     ┌──────────────┐
              │                     │ conflictCopy │ (recovered)
              └─────────────────────│  (active)    │
                                    └──────────────┘
```

- **active**: visible in library, editable.
- **trashed**: in Trash, recoverable 30 days; not in default search/library.
- **permanentlyDeleted**: readable local content removed when safe; tombstone
  retained for sync.
- **conflictCopy**: a new note UUID labeled as a conflict/recovered copy;
  behaves as active but is distinguishable.
- **restore (trashed → active)**: the note returns to the active library;
  its `manualSortKey` is reset to (max active sort-key) + 1024, placing it
  at the end of Manual order (FR-022a, clarified 2026-08-07). The
  pre-deletion sort-key is NOT retained.
- **Empty Trash (FR-014b, clarified 2026-08-07)**: a batch action transitions
  every `trashed` note to `permanentlyDeleted` in one transaction, following
  the same permanent-deletion path (readable local content removed when safe;
  tombstones retained for sync). Requires explicit user confirmation stating
  immediate permanent deletion and loss of the 30-day guarantee.

### File reference availability

```text
available ──stale (path moved externally)──▶ missing ──relink──▶ available
   ▲                                            │
   └────────── explicit move (verify ok) ───────┘
```

- **available**: bookmark resolves.
- **stale**: last resolved path no longer matches; offer relink.
- **missing**: cannot resolve; preserve card, offer relink, never auto-scan.
- **relinked**: new bookmark set after explicit relink/move.

### SyncVersionState (per synced entity)

```text
unsynchronizedLocalModification ──push──▶ synchronizedVersion
                  │
                  └── remote diverges ──▶ divergentVersion ──▶ conflictCopy created
```

- **unsynchronizedLocalModification**: `isDirty = true`, new `versionId`.
- **synchronizedVersion**: `isDirty = false`, `lastSyncedVersionId = versionId`.
- **divergentVersion**: local `versionId` and remote `versionId` share a common
  `parentVersionId` but differ → conflict copy.
- **partialAssetSyncFailure**: asset metadata synced but bytes failed; marked in
  `Asset.syncFailureState`; retried independently without re-encrypting or
  re-uploading note metadata (FR-090a).

## Indexes

- `Note(lifecycleState, modifiedAt DESC)` — active library default sort.
- `Note(lifecycleState, createdAt DESC)` — recently created.
- `Note(lifecycleState, title)` — title order.
- `Note(lifecycleState, manualSortKey)` — manual order.
- `Block(noteId, sortKey)`.
- `TodoItem(noteId, sortKey)`; `TodoItem(parentTodoId)`.
- `Asset(contentHash)`.
- `Tombstone(deletedAt)` — expiry scan.
- `Note(lastModifiedDeviceId)`.
- FTS5 `notes_fts` on the search columns above.

## Migration strategy

- Ordered, named migrations owned by the main app (`Persistence`).
- Each migration is a tested function `migrate_vN_vNplus1(_ db)`.
- A fixture database exists for every historical schema version
  (`Tests/PersistenceTests/Fixtures/schema_vN.sqlite`), and a migration test
  walks each fixture forward to current, asserting row integrity.
- High-risk migrations: back up the DB file before running; on failure, restore
  backup and report `SchemaCompatibility` error; never leave a half-migrated DB.
- Widget: on open, read schema version; if unsupported, fall back to
  privacy-safe read-only placeholders (no migration, no crash). Widget read
  transactions MUST be short enough to complete within the 5s bounded busy
  timeout (FR-140a); on timeout, report a sanitized "temporarily unavailable"
  status.
- Interrupted migration recovery: a `schema_migrations` table records applied
  migrations atomically; an incomplete migration is rolled back via the backup
  on next launch.
- Destructive schema replacement is prohibited (Principle IV). Any unavoidable
  structural change ships with an explicit export + migration + recovery plan.

## Asset lifecycle

```text
import/paste/capture
        │
        ▼
temp write (staging) ──SHA-256──▶ verify ──rename──▶ originals/<uuid>
        │                                          │
        │                              metadata txn (Asset row)
        ▼
thumbnail gen (async) ──▶ thumbnails/<uuid>
        │
        ▼
referenced by Block payload (originalAssetId/thumbnailAssetId)
        │
   note deleted/purged
        │
        ▼
reference-count check ──0 refs──▶ orphan cleanup queue ──▶ delete file (verify first)
```

- Atomic: temp file written, hashed, verified, then renamed; metadata row
  committed only after rename succeeds.
- Dedup: identical `contentHash` reuses an existing asset; reference counting
  delays cleanup until zero refs.
- Orphan cleanup is lazy and verified (never delete a file still referenced).

## Tombstone lifecycle

```text
note trashed (local) ──30 d / manual purge──▶ permanentlyDeleted + Tombstone(deletedAt)
                                                      │
                                            sync propagates tombstone
                                                      │
                                        remote retention 30 d (sync-safety-gated)
                                                      │
                                              canPurgeRemote ──▶ remove remote object + local tombstone
```

- A tombstone is never purged while any known device could still be offline
  within the retention window (sync-safety check).
- Delete-vs-edit: the edited side becomes a recovered conflict copy; the
  tombstone remains until retention expires.

### Long-offline device returning after remote tombstone purge (FR-174, clarified 2026-08-07)

```text
returning device syncs
        │
        ▼
reconcile remote deletion history BEFORE uploading local notes
        │
        ├── remote tombstone found for note ──▶ honor deletion (no resurrection)
        │
        └── no remote tombstone found (already purged >30 d)
                │
                ▼
        treat as "no remote deletion record found"
                │
                ├── note present locally & user did NOT delete it here
                │       └─▶ preserve locally; sync normally (may create conflict copy if diverged)
                │
                └── note locally deleted by user on this returning device
                        └─▶ do NOT re-upload; inform user some sync history aged out
```

- The returning device MUST NOT auto-delete any local content.
- Locally-deleted notes MUST NOT be re-uploaded unless the user explicitly
  restores them.
- The application MUST inform the user that some synchronization history has
  aged out.
- Not wall-clock "last modified wins."

## Version lineage

- Every synced mutation assigns a new `versionId` and sets `parentVersionId` to
  the prior `versionId`.
- `lastModifiedDeviceId` records the mutating device.
- Divergence = local and remote `versionId` differ but share a common ancestor
  in `parentVersionId` lineage (or one side's parent is the other's id).
- Conflict-copy dedup key: `(originalNoteId, localVersionId, remoteVersionId)`.

## Conflict-copy lifecycle

```text
divergence detected
        │
        ▼
dedup key exists? ──yes──▶ reuse existing conflictCopy
        │ no
        ▼
create new Note (new UUID, lifecycleState=conflictCopy, conflictOriginNoteId, conflictLabel)
copy blocks/todos/assets (safe duplication or ref-count) + FileReference metadata
assign versionId (parent = common ancestor)
        │
        ▼
sync conflictCopy normally (it is just another note)
```

- Asset references: shared via reference counting where content matches; only
  duplicated where a note truly needs its own copy.
- Conflict copy is independently editable/deletable.

## Example records

### Note (active, no manual title)

```json
{
  "schemaVersion": 1,
  "id": "8f3c...-4xxx-...-...",
  "title": null,
  "colorKey": "yellow",
  "customColor": null,
  "transparency": 1.0,
  "textSize": 13,
  "alwaysOnTop": false,
  "widgetEligible": true,
  "coverScreenshotBlockId": null,
  "manualSortKey": 1024,
  "lifecycleState": "active",
  "trashedAt": null,
  "conflictOriginNoteId": null,
  "conflictLabel": null,
  "versionId": "a1b2...-4xxx-...-...",
  "parentVersionId": null,
  "lastModifiedDeviceId": "d001...-4xxx-...-...",
  "createdAt": "2026-08-06T09:00:00Z",
  "modifiedAt": "2026-08-06T09:05:00Z"
}
```

### TodoItem

```json
{
  "schemaVersion": 1,
  "id": "t1c2...-4xxx-...-...",
  "noteId": "8f3c...-4xxx-...-...",
  "blockId": "b9d0...-4xxx-...-...",
  "parentTodoId": null,
  "sortKey": 1024,
  "depth": 0,
  "isComplete": false,
  "versionId": "v1...",
  "parentVersionId": null,
  "lastModifiedDeviceId": "d001...",
  "createdAt": "2026-08-06T09:00:00Z",
  "modifiedAt": "2026-08-06T09:00:00Z"
}
```

### FileReference (synced) + FileLocator (local, never synced)

Synced:
```json
{
  "schemaVersion": 1,
  "blockId": "f3a1...-4xxx-...-...",
  "displayName": "report.pdf",
  "contentType": "com.adobe.pdf",
  "approximateSize": 248320,
  "originDeviceId": "d001...",
  "addedAt": "2026-08-06T09:10:00Z",
  "caption": null
}
```
Local (never in canonical JSON / never synced):
```text
blockId: f3a1...-4xxx-...-...
bookmarkData: <security-scoped bookmark bytes>
lastResolvedPath: /Users/me/Docs/report.pdf
availabilityStatus: available
stale: false
verifiedAt: 2026-08-06T09:10:00Z
```

### Tombstone

```json
{
  "schemaVersion": 1,
  "noteId": "8f3c...-4xxx-...-...",
  "deletedVersionId": "a1b2...",
  "parentVersionId": null,
  "deletingDeviceId": "d001...",
  "deletedAt": "2026-08-06T09:30:00Z"
}
```
