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
  drag usually changes only the moved row. Normalization: when the gap between
  two neighbors drops below a threshold (e.g., < 64), renumber the contiguous
  run by 1024 steps within a single transaction.
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
| colorKey | enum | yes | yellow/pink/purple/blue/green/gray/custom |
| customColor | TEXT (nullable) | yes | hex/rgb when colorKey=custom |
| transparency | REAL | yes | 0.0–1.0 background transparency |
| textSize | enum | yes | per-note text size |
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
| depth | INT | yes | nesting depth (validation bound, e.g. ≤ 6) |
| isComplete | INT (bool) | yes | completion state |
| versionId | UUID | yes | |
| parentVersionId | UUID (nullable) | yes | |
| lastModifiedDeviceId | UUID | yes | |
| createdAt | TEXT | yes | |
| modifiedAt | TEXT | yes | |

**Validation**: no cycles (parent chain must terminate); parent must be in the
same note; depth ≤ max; sort-key collisions normalize; deleting a parent does
not orphan children (children reparented to grandparent or flagged — see
*State Transitions*).

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

Asset *bytes* are synchronized as independent encrypted objects; the
`storagePath` is device-local only. `contentHash` enables dedup (two notes
pasting the same image share one asset object remotely and can share bytes
locally via reference counting).

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

### DeviceIdentity

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| id | UUID | yes | stable device identity |
| displayName | TEXT | local | user-facing name (NOT synced to remote as meaningful metadata) |
| createdAt | TEXT | yes | |

### VaultConfiguration (device-local reference)

Points at a configured vault + provider. **Secrets live in Keychain, not here.**

| Field | Type | Synced? | Notes |
|-------|------|---------|-------|
| vaultId | UUID | local | matches the bootstrap's vault ID |
| vaultLocator | TEXT (opaque) | local | random remote locator |
| providerType | enum | local | webdav/s3 |
| providerConfig | JSON (redacted) | local | endpoint/region/bucket/prefix |
| keychainCredentialRef | TEXT | local | Keychain account label (no secret value) |
| rememberedUnlock | INT (bool) | local | whether unlocked key material may be remembered |
| createdAt | TEXT | local | |

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

FTS5 table `notes_fts` is external-content or contentless-with-rowid mapped to
`Note.id`. Scope filter excludes trashed/permanently-deleted notes by default;
a separate Trash scope query is provided.

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
  `depth ≤ maxDepth`.
- `Note.coverScreenshotBlockId` → `Block.id` where `Block.kind = screenshot`;
  at most one `ScreenshotAssociation.isCover = true` per note (enforced in a
  transaction).
- `Asset.contentHash` unique among same `kind`+`contentType` for dedup.
- `FileLocator` is 1:1 with a `fileRef` block; bookmark bytes never appear in
  `FileReference` or canonical JSON.
- Sort keys: 1024-gap; normalize contiguous runs when gap < threshold.
- Lifecycle invariants: a `permanentlyDeleted` note retains a `Tombstone` until
  sync-safety allows purge.

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
  `Asset.syncFailureState`; retried without re-encrypting metadata.

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
  privacy-safe read-only placeholders (no migration, no crash).
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
  "transparency": 0.0,
  "textSize": "regular",
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
