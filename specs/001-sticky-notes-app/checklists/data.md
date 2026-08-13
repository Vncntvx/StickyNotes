# Requirements Quality Checklist: Data Model & Persistence

**Purpose**: Validate the *quality of the written requirements* (not the
implementation) for the data-model, persistence, migration, canonical-format,
and local-versus-synchronized-data domain of the macOS Sticky Notes spec — the
area governed by constitutional principles IV (explicit, durable, versioned
data), VIII (correct and non-destructive synchronization), IX (file references
not cloud attachments), and XII (verification & testing). This is a "unit test
suite for the English": each item asks whether a requirement is complete, clear,
consistent, measurable, and traceable.
**Created**: 2026-08-07
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [data-model.md](../data-model.md) · [contracts/](../contracts/)
**Domain**: Data Model / Persistence / Migrations / Canonical Format
**Depth**: Standard (PR review gate)
**Traceability**: Strong — every item cites a FR/SC/contract/constitution/data-model anchor

## Requirement Completeness

- [X] CHK001 - Are all durable entities enumerated with their full field sets, types, and nullability in the data model (Note, Block, TodoItem, Asset, ScreenshotAssociation, FileReference, FileLocator, WindowState, Tombstone, SyncState, DeviceIdentity, VaultConfiguration, SearchDocument, DiagnosticSnapshot)? [Completeness, data-model §Entities]
- [X] CHK002 - Are synchronized versus device-local fields explicitly separated for every entity that has both (Note, Asset, FileReference/FileLocator, WindowState, Tombstone, SyncState, VaultConfiguration, DeviceIdentity)? [Completeness, Constitution IV/IX, data-model §Entities]
- [X] CHK003 - Are all foreign-key relationships and cascade rules specified (Block→Note, TodoItem→TodoItem parent, ScreenshotAssociation→Asset, FileLocator→Block, Note.coverScreenshotBlockId→Block)? [Completeness, data-model §Constraints]
- [X] CHK004 - Are all entity identifiers required to be UUIDs, and is the UUID version (v4) pinned rather than "any UUID"? [Completeness, Constitution IV, data-model §Conventions]
- [X] CHK005 - Are creation and modification timestamps required in UTC ISO 8601 for every durable entity (not just "timestamps exist")? [Completeness, Constitution IV, data-model §Conventions]
- [X] CHK006 - Are version-lineage fields (versionId, parentVersionId, lastModifiedDeviceId, modifiedAt) required on every synchronized entity, and is the set consistent across Note/Block/TodoItem? [Completeness, Constitution VIII, data-model §Conventions]
- [X] CHK007 - Are all six block categories' canonical payloads specified in contracts (rich-text, todo, code, fileRef, image, screenshot) with kind-specific schemas? [Completeness, Contracts §block-payloads.schema.json, Spec §FR-050]
- [X] CHK008 - Are the FTS5 search-document column sources enumerated for every searchable text category (title, summary, body, todos, code, fileNames, captions, future OCR)? [Completeness, data-model §SearchDocument, Spec §FR-023]
- [X] CHK009 - Are all required canonical/encryption/data contracts present (note-document, rich-text, block-payloads, asset-metadata, vault-bootstrap, encrypted-envelope, encrypted-manifest, tombstone, sync-profile-export, diagnostic-bundle, deep-links, provider-protocol, provider-errors)? [Completeness, plan §Project Structure]
- [X] CHK010 - Is a schemaVersion field required on every versioned canonical contract AND on the local DB, with explicit backward-compatibility behavior per version bump? [Completeness, Constitution IV, Contracts §*, data-model §Migration strategy]

## Requirement Clarity

- [X] CHK011 - Is the sort-key gap value (1024) and the normalization threshold (e.g. < 64) explicitly quantified as fixed numbers rather than "e.g."? [Clarity, data-model §Conventions]
- [X] CHK012 - Is the maximum todo nesting depth (`depth ≤ maxDepth`) given an explicit numeric bound rather than the illustrative "e.g. ≤ 6"? [Clarity, data-model §TodoItem]
- [X] CHK013 - Are the FTS5 table mode (external-content vs contentless-with-rowid) and the rowid-to-Note.id mapping unambiguously specified? [Clarity, data-model §SearchDocument]
- [X] CHK014 - Is the thumbnail "longest edge" pixel size for card display quantified rather than "appropriate for card display"? [Clarity, Gap, plan §Asset storage]
- [X] ~~CHK015~~ REMOVED 2026-08-13 (widget surface removal). [Clarity, Gap, plan §Local storage]
- [X] CHK016 - Is the bounded busy timeout value for the GRDB DatabasePool specified as a concrete duration? [Clarity, Gap, plan §Local storage]
- [X] CHK017 - Are the Argon2id parameters (memoryKiB, iterations, parallelism) given required minimum values rather than only the schema minimums (8/1/1)? [Clarity, Contracts §vault-bootstrap.schema.json]
- [X] CHK018 - Is the "approximately 3 seconds after local changes" sync-trigger delay expressed as a precise range or exact value? [Clarity, Spec §FR-152, plan §Sync engine]

## Requirement Consistency

- [X] CHK019 - Do the Note lifecycle states in spec.md (active/trashed/permanentlyDeleted/recoveredConflictCopy) align exactly with the data-model enum and the conflict-copy lifecycle diagram? [Consistency, Spec §Key Entities / data-model §Note lifecycle]
- [X] CHK020 - Does the FileReference "generic metadata" field set in spec.md (FR-104) match the FileReference entity in data-model.md and the block-payloads contract (no bookmark/path leakage)? [Consistency, Spec §FR-104 / data-model §FileReference / Contracts §block-payloads]
- [X] CHK021 - Do the SyncVersionState values in data-model.md (unsynchronizedLocalModification/synchronizedVersion/divergentVersion/partialAssetSyncFailure) match the per-entity sync lineage described in tasks.md and the encrypted-manifest contract? [Consistency, data-model §SyncVersionState / Contracts §encrypted-manifest]
- [X] CHK022 - Does the tombstone retention requirement (FR-174, 30 days, sync-safety-gated) align across spec, data-model (Tombstone.deletedAt), and the tombstone contract? [Consistency, Spec §FR-174 / data-model §Tombstone / Contracts §tombstone.schema.json]
- [X] CHK023 - Does the conflict-copy dedup key (originalNoteId, localVersionId, remoteVersionId) appear consistently in data-model.md, research.md R18, and the encrypted-manifest contract? [Consistency, data-model §Version lineage / research R18 / Contracts §encrypted-manifest]
- [X] CHK024 - Are device-local fields (WindowState, FileLocator, SyncState, VaultConfiguration, DiagnosticSnapshot) consistently marked "never synchronized" across data-model.md and the canonical contracts? [Consistency, Constitution IX, data-model §Entities]
- [X] CHK025 - Does the DiagnosticSnapshot field set in data-model.md match the diagnostic-bundle.schema.json contract exactly (no drift between model and schema)? [Consistency, data-model §DiagnosticSnapshot / Contracts §diagnostic-bundle.schema.json]

## Acceptance Criteria & Measurability

- [X] CHK026 - Can the "at most one cover screenshot per note" invariant be objectively verified as a transactional constraint (not just a prose statement)? [Measurability, data-model §Constraints, Spec §FR-094]
- [X] CHK027 - Are the todo-hierarchy validation rules (no cycles, depth bound, no orphaned children after parent deletion) stated as machine-checkable assertions rather than goals? [Measurability, data-model §TodoItem, Spec §FR-071]
- [X] CHK028 - Can "asset writes MUST be atomic" be verified via a testable sequence (temp-write → hash → verify → rename → metadata commit)? [Measurability, Constitution IV, data-model §Asset lifecycle]
- [X] CHK029 - Are migration-test requirements stated so that "a fixture DB exists for every historical schema version" is objectively verifiable as a deliverable? [Measurability, Constitution XII, data-model §Migration strategy]
- [X] ~~CHK030~~ REMOVED 2026-08-13 (widget surface removal). [Measurability, data-model §Migration strategy, Spec §FR-112]

## Scenario Coverage (Data Layer)

- [X] CHK031 - Are Primary scenario requirements complete for initial DB creation → first note → close → reopen → content preserved (no duplication)? [Coverage, Spec §US1, data-model §Note lifecycle]
- [X] CHK032 - Are Alternate scenario requirements defined for manual-sort reorder persistence and sort-key gap normalization on collision? [Coverage, Spec §FR-022, data-model §Conventions]
- [X] CHK033 - Are Exception/Error scenario requirements defined for interrupted migration, corrupt DB detection, and backup-restore-on-migration-failure? [Coverage, data-model §Migration strategy, plan §Local storage]
- [X] CHK034 - Are Recovery scenario requirements defined for partial-asset-sync-failure (metadata synced, bytes failed) retry without re-encrypting metadata? [Coverage, data-model §SyncVersionState, Spec §FR-090]
- [X] ~~CHK035~~ REMOVED 2026-08-13 (widget surface removal). [Coverage, research R6, plan §Local storage]
- [X] CHK036 - Are requirements defined for the delete-vs-edit data path (recovered conflict copy preserves blocks/assets/file-ref metadata via ref-count or safe duplication)? [Coverage, Spec §FR-173, data-model §Conflict-copy lifecycle]

## Edge Case Coverage

- [X] CHK037 - Is the edge case specified where two todo items have byte-identical text yet retain stable independent UUID identity? [Edge Case, Spec §Edge Cases, data-model §TodoItem]
- [X] CHK038 - Is the edge case specified where a note's text becomes empty after previously holding content (must NOT auto-delete)? [Edge Case, Spec §FR-013, data-model §Note lifecycle]
- [X] CHK039 - Is the edge case specified where multiple note cards reference the same file and an explicit move updates only the initiating card's bookmark (others report missing + relink)? [Edge Case, research R8, data-model §FileLocator]
- [X] CHK040 - Is the edge case specified where a cover screenshot block is deleted (Note.coverScreenshotBlockId must null transactionally)? [Edge Case, data-model §Constraints]
- [X] CHK041 - Is the edge case specified for sort-key gap exhaustion requiring contiguous-run renormalization within a single transaction? [Edge Case, data-model §Conventions]
- [X] ~~CHK042~~ REMOVED 2026-08-13 (widget surface removal). [Edge Case, Spec §FR-112, plan §Widgets]

## Non-Functional Requirements (Data Layer)

- [X] CHK043 - Are performance requirements specified for the card-grid compact projection (no full note body load, no full-res image decode in grid)? [Non-Functional, Constitution XI, Spec §SC-008, plan §Performance]
- [X] CHK044 - Are concurrency requirements specified so that SyncActor serializes vault mutations and AssetWriteActor serializes atomic writes (no overlapping corruption)? [Non-Functional, Constitution XI, plan §State management]
- [X] CHK045 - Are data-integrity requirements specified for SHA-256 content hashing enabling dedup AND corruption detection? [Non-Functional, Constitution IV, data-model §Asset]
- [X] CHK046 - Are requirements specified that the SQLite DB file is NEVER synchronized (only canonical per-object encrypted upload)? [Non-Functional, Constitution VIII, plan §Canonical note representation]
- [X] CHK047 - Are requirements specified that all cross-actor handoffs pass Sendable value-type repository snapshots, not mutable DB rows? [Non-Functional, Constitution XI, plan §State management]

## Dependencies & Assumptions

- [X] CHK048 - Is the assumption that GRDB.swift is the only approved persistence dependency documented with selection rationale and replacement strategy? [Dependency, Constitution XIII, plan §Dependencies]
- [X] ~~CHK049~~ REMOVED 2026-08-13 (App Group + widget removal). [Assumption, plan §Local storage]
- [X] CHK050 - Is the external dependency on FTS5 availability in the macOS 26 SQLite build documented, with a fallback if unavailable? [Dependency, Gap, plan §Search]
- [X] CHK051 - Is the assumption that the local DB is the source of truth and sync is additive documented as a product-level invariant (not just an implementation choice)? [Assumption, Constitution III, Spec §FR-140]
- [X] CHK052 - Is the dependency on a future OCR extension documented without implying OCR text enters the durable rich-text format (only the FTS column)? [Dependency, Spec §Non-goals, data-model §SearchDocument]

## Ambiguities & Conflicts

- [X] CHK053 - Is the ambiguity between "generated summary" (display-only) and "manual title" (persisted) resolved at the data-model field level so summary cannot silently write into Note.title? [Ambiguity, Spec §FR-021, data-model §Note]
- [X] CHK054 - Is the ambiguity between "no auto-restore of windows after relaunch" (FR-007) and "WindowState is stored" resolved — confirmed geometry persists but reopen is not auto-triggered? [Ambiguity, Spec §FR-007, data-model §WindowState]
- [X] CHK055 - Is the potential conflict between "permanent delete removes readable local content when safe" and "tombstone retained for sync" resolved by objectively defining "when safe"? [Conflict, data-model §Note lifecycle / §Tombstone lifecycle]
- [X] CHK056 - Is the ambiguity in DeviceIdentity.displayName ("local; NOT synced as meaningful metadata") resolved — is it synced at all, or only inside an encrypted object, or never? [Ambiguity, data-model §DeviceIdentity, Contracts §encrypted-manifest]

## Constitution Alignment (this domain)

- [X] CHK057 - Does every data-model entity/field/relationship trace to a constitutional principle (IV durable data, VIII non-destructive sync, IX file refs, XII testing)? [Traceability, Constitution IV/VIII/IX/XII, plan §Constitution Check]
- [X] CHK058 - Are the non-negotiable guarantees (no SQLite sync, no bookmark sync, no file-content sync, atomic asset writes, versioned canonical JSON, ordered migrations) each individually testable as requirements rather than merged? [Traceability, Constitution IV/VIII/IX]
- [X] CHK059 - Is it confirmed that no Complexity Tracking exception is used to bypass data-integrity, migration, conflict-preservation, or destructive-action safety in this domain? [Traceability, Constitution §Governance, plan §Complexity Tracking]
- [X] CHK060 - Are migration requirements (ordered, tested, fixture-per-version, backup-before-high-risk, interrupted-recovery) specified as mandatory rather than optional? [Traceability, Constitution IV/XII, data-model §Migration strategy]

## Notes

- This checklist tests the **quality of the written requirements**, not whether
  the implementation works. Items phrased as "Are X defined/specified…?" and
  "Is X quantified/clarified…?" validate completeness/clarity/consistency/
  measurability/coverage; they are NOT verification steps.
- Anchors: `[Spec §FR-xxx/SC-xxx]`, `[data-model §<entity>]`, `[Contracts §<file>]`,
  `[plan §<section>]`, `[research R<n>]`, `[Constitution §<principle>]`,
  `[Gap]` (missing requirement), `[Ambiguity]`, `[Conflict]`, `[Assumption]`,
  `[Dependency]`.
- Focus: data model / persistence / migrations / canonical format / local-vs-
  synced separation / file-reference data separation
  (constitutional IV/VIII/IX/XII). Depth: Standard (PR review gate). Strong
  traceability: every item carries ≥1 reference.
- Items flagged `[Gap]` indicate a requirement that should be added or made
  explicit before `/speckit-tasks`; they are not implementation TODOs.
- Overlap with `security.md` is intentional but scoped: this checklist probes
  the *data-shape* aspects of sync-safety/tombstones/file-refs; `security.md`
  probes the *encryption/privacy* aspects. Where an item could fit either,
  it is placed here only if it tests entity/field/state-transition quality.
