# Implementation Plan: macOS Sticky Notes

**Branch**: `001-sticky-notes-app` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-sticky-notes-app/spec.md`

**Note**: This is the authoritative technical plan; `tasks.md` is intentionally
NOT produced by this command. "macOS Sticky Notes" is a working title only; no
final brand name is invented here. Neutral placeholder target names are used.

## Summary

Build a native, menu-bar-primary sticky-notes application for macOS 26 and
later. The product is a modular monolith: one Xcode workspace with a macOS app
target, a Widget Extension target, and one local Swift package (`StickyCore`)
holding eight logically separated modules (Domain, Persistence, EditorCore,
AssetStore, SecurityCore, SyncCore, SystemBridge, plus the App/Widget UI
targets). The local SQLite database (via GRDB, WAL, FTS5) is the source of
truth; optional end-to-end-encrypted synchronization to exactly one WebDAV or
S3-compatible repository is an additive layer that never blocks local editing.
Delivery is split into five milestones (M0 prototypes → M1 local core → M2
system integration → M3 encrypted sync → M4 open-source release) while a single
coherent data model, migration strategy, canonical JSON format, encryption
envelope, and synchronization protocol span all milestones.

## Technical Context

**Language/Version**: Swift 6.3 (Swift language mode 6, strict concurrency).

**Primary Dependencies**: GRDB.swift (SQLite, migrations, WAL, FTS5); one small
audited Argon2id package (see research.md — final package selection deferred to
a networked environment with a full Xcode install; see Toolchain note). All
other capabilities use Apple frameworks and project-owned code (no AWS SDK, no
third-party UI/editor/state/DI/networking frameworks, no analytics SDK).

**Storage**: App Group container holding the SQLite database and binary assets
(originals, thumbnails, app icons, sync staging) outside SQLite; Keychain for
credentials and remembered unlocked key material. GRDB `DatabasePool` with WAL
mode for main-app + widget concurrent access.

**Testing**: Swift Testing for most unit/integration tests; XCTest where Apple
APIs/performance measurement require it; XCUITest for critical UI journeys.
Dedicated migration, security-vector, provider-contract, sync failure-injection,
and performance test suites.

**Target Platform**: macOS 26 and later (deployment target preserved even where
the local dev machine runs a newer OS — see Toolchain note).

**Project Type**: Native macOS desktop application with a Widget Extension and a
local Swift package for shared domain/infrastructure code. Modular monolith; no
server-side application.

**Performance Goals**: Warm menu-bar presentation ≤150 ms; initial card content
≤300 ms; new note window ≤200 ms; search across 10,000 textual notes ≤200 ms; no
sustained idle CPU; no high-frequency polling while sync inactive. See
Success Criteria in spec.md (SC-001..SC-011).

**Constraints**: App Sandbox enabled; local-first and offline-complete; no
analytics/telemetry; no developer-operated backend; end-to-end encryption of all
synced content and meaningful metadata; non-destructive conflict handling; file
references are references (not cloud attachments); fully accessible and
reversible; HTTPS only; credentials never in SQLite/UserDefaults/logs.

**Scale/Scope**: Personal use across one user's own Macs; designed for 10,000+
notes; one sync repository at a time; single-vault sync actor.

**Toolchain note (detected environment)**: The machine generating this plan has
only the Command Line Tools installed (`xcode-select` →
`/Library/Developer/CommandLineTools`); `xcodebuild` is unavailable, the bundled
Swift is 6.4, and the OS is macOS 27.0. This is **not** the project's intended
build environment. Effects: (1) the baseline Xcode 26.x / Swift 6.3 target is
declared as the plan's intent and must be confirmed in a networked environment
with a full Xcode install; (2) high-risk UI/Widget/capture assumptions cannot be
prototyped here and are explicitly assigned to Milestone 0; (3) external package
selection (Argon2id) and exact macOS-26 API names are recorded in research.md as
directions with validation criteria rather than verified facts. The macOS 26
minimum deployment target is preserved regardless.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Constitutional principle | Plan decision | Status |
|---|--------------------------|---------------|--------|
| I | Focused sticky-notes product | Plan implements only the spec's scope; no accounts/ads/analytics/collab/drawing/PM/backlinks/plugins. Non-goals explicitly carried into plan. | PASS |
| II | Native macOS & SwiftUI-first | SwiftUI-first; AppKit isolated in SystemBridge; macOS 26 minimum; no cross-platform UI framework. NSTextView fallback only if Phase 0 proves SwiftUI insufficient, behind a protocol. | PASS |
| III | Local-first & offline-complete | SQLite local DB is source of truth; all core features work offline; auto-save; sync never blocks local writes; no developer backend. | PASS |
| IV | Explicit, durable, versioned data | GRDB SQLite; UUID IDs; ordered migrations; versioned canonical JSON; project-owned rich-text format; no platform archives; atomic asset writes with SHA-256. | PASS |
| V | Structured editor integrity | Seamless block model (6 categories); stable todo UUIDs; Markdown as input convenience with single-Undo; title optional; no syntax highlighting/execution. | PASS |
| VI | Privacy & least privilege | No analytics/telemetry; OSLog with privacy annotations; permissions on-demand only; per-note widget privacy; privacy document in M4. | PASS |
| VII | E2E encryption by design | Argon2id KEK + random master key + HKDF object keys + AES-GCM + Keychain; no custom crypto; password re-wrap; contextual AAD; fail-closed; documented vectors. | PASS |
| VIII | Correct, non-destructive sync | One repo at a time; per-object encryption; idempotent/retry-safe/cancelable; conflict copies not overwrite; tombstones 30 days; HTTPS only; Keychain creds. | PASS |
| IX | File references not cloud attachments | References not copies; security-scoped bookmarks device-local; only generic metadata syncs; file content never syncs; explicit move with confirmation. | PASS |
| X | Consistent, accessible, reversible UX | Menu-bar primary; card grid; one window per note; close≠delete; 30-day Trash; keyboard-first; VoiceOver/Reduce Motion/Increased Contrast; per-note Always-on-Top. | PASS |
| XI | Performance is a product requirement | Off-main-actor work; structured concurrency + actors; lazy thumbnails; FTS search; performance tests with signposts; measured targets. | PASS |
| XII | Verification & testing mandatory | Tests part of implementation; migration/editor/security/provider/sync/UI/perf/regression suites; failure injection; no-credentials fixtures. | PASS |
| XIII | Dependency discipline | Only GRDB + one audited Argon2id approved; WebDAV/SigV4/sync/crypto-envelope in project-owned code; documented add-dependency decision process. | PASS |
| XIV | Spec-driven traceability | Plan derived from spec; Constitution Check here + post-design re-check; spec/contracts versioned; behavior changes update spec+tests together. | PASS |

No violations. No items require Complexity Tracking exceptions for privacy,
encryption, data integrity, conflict preservation, or destructive-action safety.

## Project Structure

### Documentation (this feature)

```text
specs/001-sticky-notes-app/
├── plan.md              # This file
├── research.md          # Phase 0 output (technical decisions + risks)
├── data-model.md        # Phase 1 output (entities, migrations, state machines)
├── quickstart.md        # Phase 1 output (build/run/test validation guide)
├── contracts/           # Phase 1 output (versioned JSON schemas + protocols)
│   ├── note-document.schema.json
│   ├── rich-text.schema.json
│   ├── block-payloads.schema.json
│   ├── asset-metadata.schema.json
│   ├── vault-bootstrap.schema.json
│   ├── encrypted-envelope.schema.json
│   ├── encrypted-manifest.schema.json
│   ├── tombstone.schema.json
│   ├── sync-profile-export.schema.json
│   ├── deep-links.md
│   ├── provider-protocol.md
│   └── provider-errors.md
└── tasks.md             # NOT created by /speckit-plan (later /speckit-tasks)
```

### Source Code (repository root)

```text
ProjectRoot/
├── App/                         # macOS application target (SwiftUI app, scenes, DI env)
│   ├── Sources/
│   │   ├── App/                 # @main, AppEnvironment, scene wiring
│   │   ├── Features/            # Library, NoteWindow, Editor, Capture, Trash,
│   │   │                        #   Search, Settings, SyncStatus, Permissions
│   │   └── Resources/           # Assets, String Catalogs (en, zh-Hans),
│   │                            #   PrivacyInfo.xcprivacy, entitlements
├── WidgetExtension/             # WidgetKit + AppIntents target
├── Packages/
│   └── StickyCore/              # Local Swift package: 8 modules + tests
│       ├── Package.swift
│       ├── Sources/
│       │   ├── Domain/          # Foundation-only models & rules
│       │   ├── Persistence/     # GRDB, migrations, FTS5, repositories
│       │   ├── EditorCore/      # Block ops, Markdown FSM, canonical conversion
│       │   ├── AssetStore/      # Atomic asset writes, thumbnails, hashing
│       │   ├── SecurityCore/    # Vault, KDF, key wrap, AES-GCM envelopes
│       │   ├── SyncCore/        # Provider protocol, WebDAV, S3-SigV4, engine
│       │   └── SystemBridge/    # NSWindow/Dock/shortcuts/bookmarks/permissions
│       └── Tests/
│           ├── DomainTests/
│           ├── PersistenceTests/
│           ├── EditorCoreTests/
│           ├── AssetStoreTests/
│           ├── SecurityCoreTests/
│           ├── SyncCoreTests/
│           └── SystemBridgeTests/
├── AppTests/                    # App-level integration tests
├── AppUITests/                  # XCUITest critical journeys
├── Documentation/               # Architecture, privacy, security, protocol docs
├── .github/workflows/           # CI (macOS runner, Xcode 26.x)
├── specs/                       # Spec Kit content
└── Package.resolved             # Pinned dependency revisions
```

**Structure Decision**: A single local package `StickyCore` with eight SwiftPM
targets is chosen over eight separate repos or one monolithic app target. The
eight modules map 1:1 to the constitution's required separable concerns (domain,
persistence, editor, asset, security, sync, system bridge, UI) and enforce the
dependency direction below at the compiler level. This avoids excessive
micro-modules (each module has a clear, broad responsibility) while keeping
AppKit, GRDB, URLSession, and Keychain out of Domain and out of each other's
internals. The App and WidgetExtension targets depend on the package; the Widget
target imports only the minimal Domain + Persistence surface and never links
SyncCore/SecurityCore.

## Architecture

### Module boundaries and dependency direction

```text
                        ┌───────────────┐
                        │   App (UI)    │
                        │ WidgetExt(UI) │
                        └───────┬───────┘
                                │
   ┌────────────┬───────────────┼────────────────┬──────────────┐
   ▼            ▼               ▼                ▼              ▼
SystemBridge  EditorCore    AssetStore       SecurityCore   SyncCore
   │            │               │                │              │
   │            └───────┬───────┘                │              │
   │                    ▼                        │              │
   │                 Domain  ◄───────────────────┴──────────────┘
   │                    ▲
   └────────────┬───────┴───────┬────────────────┘
                │               │
            Persistence  (GRDB) │
                                │
                          (SecurityCore used by SyncCore; SyncCore uses
                           Persistence abstractions + SecurityCore + Domain)
```

Enforced rules:

- **Domain** depends only on Foundation-compatible APIs. No SwiftUI, AppKit,
  GRDB, URLSession, Keychain, or provider types.
- **EditorCore** depends on Domain only.
- **Persistence** depends on Domain + GRDB. Exposes repository protocols;
  concrete DB rows are NOT exported as contracts.
- **AssetStore** depends on Domain + Apple image/file frameworks (ImageIO,
  CoreGraphics, UniformTypeIdentifiers, CoreTransferable).
- **SecurityCore** depends on Domain + CryptoKit + Security (Keychain).
- **SyncCore** depends on Domain + SecurityCore + Persistence abstractions +
  its own provider protocols. Provider adapters (WebDAV, S3-SigV4) live here
  but contain no conflict-resolution policy.
- **SystemBridge** depends on Domain + AppKit/Carbon/ScreenCaptureKit/Security
  (bookmarks). All AppKit/lower-level APIs are isolated here.
- **App UI** depends on package protocols, not concrete DB/provider types where
  practical. **WidgetExtension** depends only on minimal Domain + Persistence.
- No circular dependencies (enforced by SwiftPM target graph).

Dependency injection is via explicit initializers and a small `AppEnvironment`
(composed services). No DI framework.

### Application scenes and window architecture

- **Menu-bar library**: `MenuBarExtra` with window-style presentation. Contains
  search, card grid, sorting, new-note + screenshot actions, Trash, sync state,
  Settings/Help/Quit. Re-click behavior per FR-009: focus if not focused,
  dismiss if focused, never a second window.
- **Note windows**: SwiftUI multi-window scenes, one window per note UUID.
- **`NoteWindowCoordinator`** (lives in App, uses SystemBridge): opens by UUID;
  ensures one active window per note; focuses existing instead of duplicating;
  registers/unregisters the underlying `NSWindow`; applies per-note floating
  level; restores saved size + position; moves inaccessible windows onto a
  visible display while preserving the disconnected-display preferred frame;
  does NOT reopen windows after relaunch; flushes pending edits before close.
- **AppKit bridge** (SystemBridge): customizes hidden/minimized title-bar,
  movable background, window level, frame constraints, display-change handling,
  activation. A custom borderless panel is NOT used unless Phase 0 proves a
  normal SwiftUI window cannot meet accessibility/focus/resizing requirements.

### State management and concurrency

- Swift Observation with small `@Observable` feature models; no global mutable
  singleton holding all state.
- Main-actor isolation for UI-facing models.
- Actors for mutable serialized services: `SyncActor` (one sync transaction per
  vault at a time), `AssetWriteActor` (atomic asset mutations).
- Structured concurrency; cancellation-aware tasks; async sequences/observations
  for database-driven UI updates.
- **Never on Main Actor**: network requests, password derivation, large-asset
  encryption/decryption, thumbnail generation, full-resolution image decoding,
  large file copying, DB maintenance, remote manifest comparison.

Actor boundaries and `Sendable`: Domain entities are value types
(`struct`/`enum`) and `Sendable`. Repository protocols return `Sendable`
snapshots. `SyncActor` owns all vault mutation; UI reads via async projections.
`AssetWriteActor` serializes writes; reads use file URLs handed back to a
decoder actor. All cross-actor handoffs pass `Sendable` value types or
`isolated` references.

### Local storage

- **App Group container**: SQLite DB, asset originals, thumbnails, app-icon
  snapshots, sync staging, non-sensitive shared widget settings.
- **Keychain**: WebDAV password/token, S3 access/secret keys, optional session
  token, remembered unlocked vault key material, certificate trust records.
- Never in SQLite/UserDefaults/logs/exported diagnostics/source-controlled
  config.
- GRDB `DatabasePool`, WAL mode, bounded busy timeout, short write transactions.
  Main app owns migrations; widgets detect unsupported schema and fall back to
  privacy-safe placeholders read-only. Integrity checking, pre-migration backup,
  interrupted-migration recovery. A test fixture for every historical schema
  version.

### Canonical note representation

- The SQLite DB file is NEVER synchronized.
- Each note has a versioned canonical JSON representation: stable keys, ISO 8601
  UTC timestamps, UUID strings, explicit enum values, explicit schema version,
  no Swift type names, no platform archives, no local paths, no bookmark bytes.
- Rich text uses a project-owned run/paragraph model (paragraph style, ordered
  runs, supported marks, optional link, inline-code mark, explicit hard breaks),
  NOT archived `NSAttributedString`/`AttributedString` scopes. Only
  application-supported formatting is preserved. Unicode normalization and index
  stability are addressed in research.md and data-model.md.

### Editor architecture

- Seamless block editor around 6 block categories; looks like one continuous
  note, not a page-builder.
- Rich-text block: SwiftUI `TextEditor` + `AttributedString` on macOS 26. An
  isolated **RichTextAdapter** converts between SwiftUI attributed state ↔
  canonical rich-text document ↔ searchable plain text. No arbitrary platform
  attributes enter storage.
- Editor plan covers: selection, cross-block focus movement, insert before/after
  special blocks, keyboard deletion at block boundaries, drag + keyboard
  reordering, undo/redo, auto-save, IME composition, pasted rich text, pasted
  Markdown, pasted images, link detection, accessibility actions.
- **Fallback**: if Phase 0 proves SwiftUI `TextEditor` cannot reliably satisfy a
  required behavior, an isolated `NSViewRepresentable` around `NSTextView` for
  the rich-text block ONLY is permitted, documented as an architecture decision,
  behind a protocol, canonical format unchanged, AppKit types not leaking into
  Domain, with specific evidence of the SwiftUI blocker.

### Markdown transformation

- Implemented as an editor transformation state machine, not a Markdown document
  mode. Line-level (heading/bullet/todo/code-fence) and inline
  (bold/italic/strike/inline-code) categories per spec.
- Transformer: ignores unmatched delimiters; does NOT transform while an IME has
  active marked text; preserves Chinese/mixed composition; treats conversion +
  delimiter removal as ONE undo group (one Undo restores exact source
  delimiters); no conversion inside code blocks except closing fences; defines
  cursor placement after conversion; unit-testable without SwiftUI.
- Uses the environment `UndoManager` through an editor-specific command layer.

### Todo architecture

- Stable UUID per todo; hierarchy explicit (parent-child), not
  whitespace-inferred.
- Completion/incompletion, reorder, indent/outdent, child relationships, stable
  widget updates, sync conflict preservation. Completing a parent does NOT
  silently change children (spec does not require it).
- Validation prevents: cycles, invalid parent refs, unsupported nesting depth,
  unnormalizable sort-key collisions, orphaned children after deletion.
- Pointer + keyboard operations. Widget todo actions address items by UUID.

### Code blocks

- Dedicated view + canonical payload: plain text, optional language label,
  monospaced, preserved whitespace, copy action, wrap-or-scroll per spec,
  keyboard movement into/out of block. No syntax-highlighting deps; no code
  execution.

### Auto-save

- Local-first. In-memory draft per open note; debounce ordinary text persistence
  ~300 ms; save structural ops + todo completion immediately; flush on focus
  loss, before window close, before termination; never wait for remote sync to
  consider a local save complete.
- Stale-debounced-write protection via revision tokens / serialized note-edit
  sessions. Crash-consistency behavior documented in research.md.

### Search

- SQLite FTS5 via GRDB. One searchable document per note: manual title, generated
  summary source, normal text, todo text, code text, file display names,
  screenshot captions, future OCR text. Indexed transactionally with note
  changes. Active notes by default; separate Trash scope. Results never reveal
  privacy-excluded notes. Performance tests at 10,000 notes.

### Asset storage

- Binary assets outside SQLite in App Group container; opaque UUID filenames;
  separate originals/thumbnails/app-icons/temp-imports/sync-staging.
- Atomic temp-write + rename; SHA-256 hashes; metadata transactions; cleanup
  queues; verify before deleting source/temp.
- Pasted images: embedded original, privacy-normalized metadata, async
  thumbnail, no original decode in card grid.
- Screenshots: static original, thumbnail (longest edge sized for card/widget),
  lossless preferred for text-heavy window captures, independent thumbnail
  storage, multiple per note, at most one cover enforced transactionally. No OCR
  in first release; model extensible for later OCR text.

### Screenshot capture

- ScreenCaptureKit. Application-window capture uses the system content-sharing
  picker (no custom picker), single static frame, preserves app name/icon/title/
  capture time, no retained live stream. Region capture: single-frame capture +
  lightweight transparent multi-display selection overlay; handles Retina, multi
  display, rotation, coordinate conversion; cancels cleanly without creating a
  note/asset. Screen-recording permission requested only on capture invocation;
  no accessibility permission for ordinary capture. Opening a screenshot does
  not activate the original app.

### File-reference architecture

- Finder files are references, not uploaded attachments. Security-scoped
  bookmarks for durable local access.
- **Synchronized metadata**: block UUID, display name, content type, approx
  size, added date, origin device UUID, optional caption.
- **Device-local locator**: block UUID, security-scoped bookmark, last resolved
  path, stale status, availability status, verification timestamp. Bookmark
  bytes + absolute paths NEVER enter canonical JSON or sync.
- Balanced security-scoped access. Drag-out copies without deleting (explicit
  move requires command + destination picker + confirmation + verify-before-
  replace-bookmark). Relink failure preserves the card. No filesystem-wide scan.
  Multi-card-same-file-after-move behavior documented in research.md.

### Widgets

- One WidgetKit + SwiftUI extension; AppIntent configuration for user-selectable
  notes; AppIntents for toggle-todo/create-note/other lightweight actions; deep
  links to open a specific note. Widget families per spec.
- Data access: read App Group SQLite in short transactions; todo updates in small
  atomic writes; reload only relevant timelines; NEVER initialize the sync
  engine; never expose widget-ineligible notes; privacy-safe placeholders/
  snapshots; graceful handling of deleted/trashed/conflicted/unavailable
  configured notes; no crash on schema mismatch.
- URL routing: `stickynotes://note/<uuid>`, `stickynotes://new`,
  `stickynotes://search` (placeholder scheme until final bundle id chosen).

### Global shortcuts

- Thin native adapter. Prefer a system-level registration API that needs no
  Accessibility permission, detects registration failure, can
  unregister/re-register, supports user config, detects conflicts when possible.
  Direction: Carbon `RegisterEventHotKey` family (the long-standing macOS API
  for global hotkeys without Accessibility permission) — exact API + Swift 6
  strict-concurrency interop to be confirmed in Milestone 0 (see research.md).
  No global event tap for ordinary shortcuts. Shortcuts stored outside sync'd
  note data (local settings).

### Permissions

- Permission service exposes: current screen-recording status, current
  accessibility status, feature-specific explanation, request action,
  open-System-Settings action, denied-state recovery.
- Screen recording: requested only on capture invocation. Accessibility:
  reserved for future "identify active window"; not requested at startup or
  during ordinary window selection; advanced code behind a feature boundary.
  Denial affects only the related feature.

### Encryption architecture

- E2E encryption for all synced content + meaningful metadata.
- Audited Argon2id package → KEK from sync password; random vault master key;
  CryptoKit HKDF-SHA-256 for context-specific object keys; CryptoKit AES-GCM for
  authenticated encryption; Keychain for local secrets; secure random
  nonces/IDs. No hand-rolled crypto.
- **Vault bootstrap** (versioned): format version, random vault ID, random vault
  locator, Argon2id salt + params, wrapped master key, password-verification/
  key-confirmation material, encryption-suite version. Password protects master
  key (not every object). Password change re-wraps master key.
- **Object-key derivation**: per-object key from context = {vaultID, objectID,
  objectType, schemaVersion, encryptionSuiteVersion}; same immutable context is
  AES-GCM AAD. Reject wrong password, modified ciphertext/tag, mismatched
  object ID/type/vault, unsupported envelope version. Fail closed.
- **Encrypted envelope** (versioned): envelope version, opaque object ID, nonce,
  ciphertext, auth tag. Remote filenames random/opaque; no semantic type.
- **Key lifecycle**: minimize decrypted-key lifetime/duplication. Document when
  vault is unlocked, optional "remember unlocked vault on this Mac", how to
  lock, how remembered state is removed, Keychain-failure behavior,
  password-changed-elsewhere behavior, wrong-vault-selected behavior.
  Deterministic test vectors with no real secrets.

### Remote vault layout

- Provider sees only: random vault locator, opaque object names, sizes, mod
  times, network-level access metadata. Learns no titles/types/file names/app
  names/window titles/device display names/semantic classes.
- Layout: one discoverable bootstrap object under the random vault locator; one
  encrypted manifest/index; independently encrypted note objects; independently
  encrypted asset objects; independently encrypted tombstones. No uploaded
  SQLite DB, no bookmarks, no referenced-file content. Safe temp-upload + commit.

### Synchronization provider protocol

- Provider-neutral protocol: verify connectivity/credentials; ensure vault
  container exists; fetch object metadata; fetch object; upload conditionally;
  delete conditionally; list objects where required; fetch + conditionally
  replace manifest; return normalized provider errors. Adapters contain NO
  conflict-resolution policy (that lives in the engine).

### WebDAV adapter

- Direct over URLSession. Subset: PROPFIND, MKCOL, GET, PUT, HEAD, DELETE,
  ETag, If-Match, If-None-Match, Depth, XML multistatus parsing, auth
  challenges, redirect safety, server-capability differences. HTTPS only.
  Self-signed cert support as advanced option: never disable TLS globally;
  explicit confirmation; pin certificate/public-key fingerprint to the
  endpoint; detect changes; store trust decisions securely; clear warning.

### S3-compatible adapter

- Direct over URLSession; AWS SigV4 in project-owned code. Config: endpoint,
  region, bucket, prefix, access key, secret key, optional session token,
  path-style vs virtual-host, TLS behavior. Compatibility targets: AWS S3,
  Cloudflare R2, MinIO, Backblaze B2 S3 API, generic SigV4. Document canonical
  request, header normalization, URI/query encoding, payload hashing, clock
  skew, error XML parsing, conditional ops, ETag limitations, multipart
  thresholds. Avoid multipart in first impl unless required. No AWS SDK.

### Synchronization engine

- Single-vault `SyncActor` (one transaction per vault at a time). Triggers:
  ~3 s after local changes; periodic (~15 min); startup; network restoration;
  manual; bounded best-effort at termination (never blocks indefinitely).
- Steps: load dirty state → fetch+authenticate bootstrap+manifest → compare
  lineage+tombstones → download missing/newer → validate+decrypt each before
  accept → detect divergence → create conflict copies (not overwrite) → stage
  uploads → upload immutable objects → commit manifest via safe conditional op
  → retry comparison on manifest precondition failure → update local sync state
  transactionally → preserve partial failures for retry → report sanitized
  diagnostics. All ops idempotent/safely repeatable. Exponential backoff +
  jitter for transient failures. No continuous idle polling. Network-path
  change is a trigger, not proof of reachability.

### Conflict model

- Note-level conflicts. Each version: stable note UUID, version UUID, parent
  version UUID, modifying device UUID, mod time. On divergence: keep one
  version as original, create a new note UUID for the other labeled conflict
  copy, preserve all text/todos/code/images/screenshots/styles/synced file-ref
  metadata, preserve asset refs by safe duplication/reference counting, NO
  character/block auto-merge, sync the conflict copy normally. Deterministic
  dedup via a reconciliation record keyed by (originalNoteUUID, localVersionID,
  remoteVersionID) so retry does not create unbounded duplicates.

### Deletion and tombstones

- Local delete → Trash 30 days. Permanent delete removes readable local content
  when safe, retains minimum tombstone for sync. Tombstones carry enough version
  info to prevent resurrection. Behavior defined for: offline <30 d, offline
  >30 d, delete-vs-edit, deleted asset refs, device returning after remote
  cleanup, unknown devices, manual Trash empty. Returning long-offline device
  reconciles remote deletion history before uploading locally-deleted notes. Not
  wall-clock "last modified wins".

### Repository replacement and password changes

- User-safe workflows documented for: enabling sync on existing collection,
  joining existing vault, importing vault locator, wrong password, selecting
  repo with another vault, disabling sync (retain local notes), forgetting
  local creds/unlocked key material, replacing WebDAV↔S3, creating new empty
  vault, uploading existing notes to new vault, changing password, updating
  other Macs after password change, recovering from partial password-change
  propagation. Never silently delete remote data when local sync is disabled.

### Diagnostics and logging

- OSLog `Logger` with privacy annotations (dynamic values private by default).
  Logs never include content/titles/todo/code/file names/paths/window titles/
  captions/credentials/passwords/key material/complete responses/full object
  names where avoidable. Stable error domains + sanitized codes. Exportable
  diagnostic bundle: app version, macOS version, schema versions, provider
  type, sanitized codes, operation timing, object counts/sizes, redacted
  config, recent sanitized logs. OS signposts on measurable paths.

### Error model

- Typed categories: Persistence, EditorConversion, AssetStorage, FileRefAccess,
  Capture, Permission, Encryption, Credentials, WebDAV, S3, SyncConflict,
  RemoteCorruption, SchemaCompatibility. Mapped to: silent retry / non-blocking
  status / inline recovery / blocking confirmation (destructive only).
  User-facing messages localized, no sensitive technical detail; diagnostics
  sanitized.

### Accessibility

- VoiceOver labels/actions, keyboard navigation, focus order, menus/keyboard
  alternatives for hover controls, keyboard reordering of blocks/todos, keyboard
  indent/outdent, announcements for todo-state changes + failed file access +
  failed capture, Increased Contrast, Reduce Motion, light/dark, dynamic
  readable foreground colors, font fallback (Chinese/English), IME marked text,
  emoji, mixed-language editing. Custom colors failing contrast are adjusted
  for display or rejected with explanation. No essential command available only
  via hover.

### Localization

- String Catalogs; English + Simplified Chinese. Persisted enum values + sync
  schemas language-neutral; no localized strings as protocol identifiers.
  Locale-aware date/file-size formatters.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified

No constitutional violations. No Complexity Tracking entries. (Per constitution,
Complexity Tracking MUST NOT be used to bypass privacy, encryption, data
integrity, conflict preservation, or destructive-action safety — none are
bypassed.)

## Delivery Milestones

Each milestone preserves a buildable, testable repository. A single coherent
data model, migration strategy, canonical JSON format, encryption envelope, and
synchronization protocol span all milestones (designed in Phase 1; M1/M2 use the
sync-inert portions, M3 activates sync).

### Milestone 0 — Architecture prototypes

Validate highest-risk assumptions BEFORE broad feature work depends on them:

- SwiftUI rich-text editing with Chinese IME.
- Markdown conversion with single-step Undo.
- One-window-per-note behavior (NoteWindowCoordinator).
- Per-window floating level.
- App Group GRDB access from Widget Extension.
- ScreenCaptureKit single-frame capture + region overlay.
- Native global-shortcut registration (no Accessibility permission).
- Confirm Xcode 26.x / Swift 6.3 baseline + select + integrate Argon2id package.

### Milestone 1 — Local core

Menu-bar library; independent note windows; persistence + migrations; rich text;
todos; code blocks; file references; search; colors/transparency; Trash; window
placement; Dock preference. (SyncCore/SecurityCore present but inert.)

### Milestone 2 — System integration

Screenshot capture; embedded clipboard images; screenshot viewer; widgets; App
Intents; global shortcuts; permission UI; display restoration; accessibility
polish.

### Milestone 3 — Encrypted synchronization

Canonical schemas; encryption formats; vault onboarding; WebDAV; S3-compatible
provider; conflict copies; tombstones; diagnostics; multi-device validation.

### Milestone 4 — Open-source release

Documentation; privacy documentation; security policy; architecture docs;
protocol docs; license compliance; signing + notarization workflow; GitHub
release workflow.

## Constitution Check (re-evaluated after Phase 1 design)

After producing research.md, data-model.md, contracts/, and quickstart.md, the
plan was re-checked against all fourteen principles. The post-design state
introduces no violations:

- The data model separates synchronized vs device-local fields (IV, IX) and uses
  UUIDs + ordered migrations + version lineage (IV, VIII).
- Canonical contracts are versioned JSON with no platform archives/local paths/
  bookmark bytes (IV, VII, IX).
- The encryption envelope uses contextual AAD and fails closed (VII).
- Conflict + tombstone design is non-destructive with deterministic dedup (VIII).
- File-reference locator is device-local; only generic metadata syncs (IX).
- Widget access is minimal, privacy-safe, and never initializes sync (VI, XI).
- Test strategy covers failure injection across editor/persistence/security/
  provider/sync/UI/performance (XII).
- Only GRDB + one audited Argon2id are approved; WebDAV/SigV4/crypto-envelope
  are project-owned (XIII).
- All design traces to spec FRs and acceptance scenarios (XIV).

No Complexity Tracking exceptions are required. The plan is ready for
`/speckit-checklist` and `/speckit-tasks`.
