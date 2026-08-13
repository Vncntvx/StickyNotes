# Implementation Plan: macOS Sticky Notes

**Branch**: `001-sticky-notes-app` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Note**: "macOS Sticky Notes" is a working title only; no final brand name is
invented here. Neutral placeholder target names are used. `tasks.md` is
generated separately by `/speckit-tasks`.

## Summary

Build a native, menu-bar-primary sticky-notes application for macOS 26 and
later. The product is a modular monolith: one Xcode workspace with a macOS app
target and one local Swift package (`StickyCore`)
holding seven library modules (Domain, Persistence, EditorCore,
AssetStore, SecurityCore, SyncCore, SystemBridge, plus the App UI
target). The local SQLite database (via GRDB, WAL, FTS5) is the source of
truth; optional end-to-end-encrypted synchronization to exactly one WebDAV or
S3-compatible repository is an additive layer that never blocks local editing.
Delivery is split into five milestones (M0 prototypes → M1 local core → M2
system integration → M3 encrypted sync → M4 open-source release) while a single
coherent data model, migration strategy, canonical JSON format, encryption
envelope, and synchronization protocol span all milestones.

## Technical Context

**Language/Version**: Swift 6.3 (Swift language mode 6, strict concurrency).

**Primary Dependencies**: GRDB.swift (SQLite, migrations, WAL, FTS5); one small
audited Argon2id package (see research.md — final package selection deferred;
see Toolchain note). All
other capabilities use Apple frameworks and project-owned code (no AWS SDK, no
third-party UI/editor/state/DI/networking frameworks, no analytics SDK).

**Storage**: the app sandbox `Application Support` directory holding the
SQLite database and binary assets (originals, thumbnails, app icons, sync
staging) outside SQLite; Keychain for credentials and remembered unlocked
key material. GRDB `DatabasePool` with WAL mode.

**Testing**: Swift Testing for most unit/integration tests; XCTest where Apple
APIs/performance measurement require it; XCUITest for critical UI journeys.
Dedicated migration, security-vector, provider-contract, sync failure-injection,
and performance test suites.

**Target Platform**: macOS 26 and later (see Toolchain note).

**Project Type**: Native macOS desktop application with a local Swift package
for shared domain/infrastructure code. Modular monolith; no
server-side application.

**Performance Goals**: Warm menu-bar presentation ≤150 ms; initial card content
≤300 ms; new note window ≤200 ms; search across 10,000 textual notes ≤200 ms;
keystroke-to-glyph latency <16 ms (one frame at 60 Hz) during normal editing
including with Chinese IME composition active (SC-004a); no sustained idle CPU;
no high-frequency polling while sync inactive. See Success Criteria in spec.md
(SC-001..SC-011).

**Constraints**: App Sandbox enabled; local-first and offline-complete; no
analytics/telemetry; no developer-operated backend; end-to-end encryption of all
synced content and meaningful metadata; non-destructive conflict handling; file
references are references (not cloud attachments); fully accessible and
reversible; HTTPS only; credentials never in SQLite/UserDefaults/logs. Bounded
scale (FR-090b): single asset ≤ 50 MB / ≤ 16,384 px longest edge; single-note
structured content ≤ 5 MB. UI localized zh-Hans + en (FR-180a). Single-note
JSON export/import reusing the canonical note envelope (FR-031a); whole-library
bulk export/import is a non-goal.

**Scale/Scope**: Personal use across one user's own Macs; designed for 10,000+
notes; one sync repository at a time; single-vault sync actor.

**Toolchain note (detected environment)**: This plan was generated on a machine
with only Command Line Tools (no full Xcode install); the baseline Xcode 26.x /
Swift 6.3 target is the declared intent, and external package selection
(Argon2id) + exact macOS-26 API names are recorded in research.md as directions
with validation criteria rather than verified facts. Milestone 0 prototypes
validate the high-risk assumptions (see history/plan-superseded.md for the
original environment snapshot). The macOS 26 minimum deployment target is
preserved regardless.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Constitutional principle | Plan decision | Status |
|---|--------------------------|---------------|--------|
| I | Focused sticky-notes product | Plan implements only the spec's scope; no accounts/ads/analytics/collab/drawing/PM/backlinks/plugins. Non-goals explicitly carried into plan. | PASS |
| II | Native macOS & SwiftUI-first | SwiftUI-first; AppKit isolated in SystemBridge; macOS 26 minimum; no cross-platform UI framework. NSTextView fallback only if Phase 0 proves SwiftUI insufficient, behind a protocol. | PASS |
| III | Local-first & offline-complete | SQLite local DB is source of truth; all core features work offline; auto-save; sync never blocks local writes; no developer backend. | PASS |
| IV | Explicit, durable, versioned data | GRDB SQLite; UUID IDs; ordered migrations; versioned canonical JSON; project-owned rich-text format; no platform archives; atomic asset writes with SHA-256. | PASS |
| V | Structured editor integrity | Seamless block model (6 categories); stable todo UUIDs; Markdown as input convenience with single-Undo; title optional; no syntax highlighting/execution. | PASS |
| VI | Privacy & least privilege | No analytics/telemetry; OSLog with privacy annotations; permissions on-demand only; privacy document in M4. | PASS |
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

> **2026-08-07 clarification propagation**: The 26 product clarifications from
> six `/speckit-clarify` sessions (FR-001a/FR-012a/FR-014a/FR-014b/FR-020a/
> FR-022a/FR-022b/FR-031a/FR-040a/FR-041a/FR-043a/FR-050a/FR-054/FR-090a/
> FR-090b/FR-094a/FR-094b/FR-095a/FR-140a/FR-141a/FR-152a/FR-160a–e/
> FR-162a/FR-174/FR-180a/FR-191 + wrong-vault edge case) are encoded in
> spec.md and reflected in the corresponding sections below. None alter the
> architecture; all add testable acceptance criteria. The full propagation
> history is archived in `history/plan-superseded.md`.
>
> **2026-08-07 session-2 propagation**: The `/speckit-clarify` session-2
> answers are encoded as FR-009 (sheet-over-library toggle rule), FR-011a
> (library/search exception guarantee), FR-014c (unified empty-state
> component for search no-results + empty Trash), FR-050b (unified block
> presentation), FR-141b (async-feedback split policy), and FR-180b (scoped
> VoiceOver labeling). Each is propagated into the sections below; none
> alter the architecture.

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
│   ├── diagnostic-bundle.schema.json   # FR-191 diagnostic content boundary
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
├── Packages/
│   └── StickyCore/              # Local Swift package: 7 library modules + tests
│       ├── Package.swift
│       ├── Sources/
│       │   ├── Domain/          # Foundation-only models & rules
│       │   ├── Persistence/     # GRDB, migrations, FTS5, repositories
│       │   ├── EditorCore/      # Block ops, Markdown FSM, canonical conversion
│       │   ├── AssetStore/      # Atomic asset writes, thumbnails, hashing
│       │   ├── SecurityCore/    # Vault, KDF, key wrap, AES-GCM envelopes
│       │   ├── SyncCore/        # Provider protocol, WebDAV, S3-SigV4, engine
│       │   └── SystemBridge/    # NSWindow/Dock/capture/bookmarks/permissions
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

**Structure Decision**: A single local package `StickyCore` with seven
library SwiftPM targets is chosen over seven separate repos or one monolithic
app target. The seven library modules map 1:1 to the constitution's required separable concerns (domain,
persistence, editor, asset, security, sync, system bridge, UI) and enforce the
dependency direction below at the compiler level. This avoids excessive
micro-modules (each module has a clear, broad responsibility) while keeping
AppKit, GRDB, URLSession, and Keychain out of Domain and out of each other's
internals. The App target depends on the package.

## Architecture

### Module boundaries and dependency direction

```text
                        ┌───────────────┐
                        │   App (UI)    │
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
  practical.
- No circular dependencies (enforced by SwiftPM target graph).

Dependency injection is via explicit initializers and a small `AppEnvironment`
(composed services). No DI framework.

### Application scenes and window architecture

- **Menu-bar library**: `MenuBarExtra` with window-style presentation. Contains
  search, card grid, sorting, new-note + screenshot actions, Trash, sync state,
  Settings/Help/Quit. Re-click behavior per FR-009: focus if not focused,
  dismiss if focused, never a second window. When an app-modal sheet (Settings,
  Save As, export dialog) is open at the moment of a menu-bar-icon click, the
  sheet stays open and the library toggles exactly as specified — the toggle
  never dismisses an open sheet (FR-009, clarified 2026-08-07). Positioning per FR-001a
  (clarified 2026-08-07): left edge aligned with the menu-bar icon's left
  edge, clamped to the visible screen frame, 4 points below the menu bar,
  instant open/dismiss with no animation (so the SC-001 ≤150 ms warm-
  presentation target is measurable without animation interference).
  Card rendering per FR-020a (clarified 2026-08-07): the body preview is
  truncated at 2 rendered lines with a trailing ellipsis (line-level at the
  card's current width, from the first rich-text block — never duplicating
  the generated summary title); the last-modified time is relative ("5 min
  ago") within the last 7 days and switches to an absolute date ("Aug 1",
  with the year when in a previous calendar year) beyond that. Locale-aware
  formatters (FR-180a).
- **First-launch experience (FR-014a)**: on first launch the library presents
  an empty card grid with a clear call-to-action to create the first note
  (button + keyboard shortcut). No permission prompts appear unless the user
  invokes the feature requiring them. When synchronization is not configured,
  the sync-status area shows "not configured" (never an error). A brief,
  dismissible onboarding hint explains auto-save and the menu-bar-primary
  model;   the hint is   never shown again after the first note is created. The
  dismissed/seen state is a device-local preference (standard UserDefaults),
  never synchronized and never in canonical JSON.
- **Unified empty-state (FR-014c, clarified 2026-08-07)**: search
  no-results and empty-Trash MUST both render a single reusable empty-state
  component — a localized message + icon, no call-to-action, no other
  content — in the same component, spacing, and visual style on both
  surfaces (localized per FR-180a). The first-launch empty-library variant
  (FR-014a) is distinct (CTA + onboarding hint) and is never substituted
  for the unified empty-state.
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

- **Sandbox Application Support**: SQLite DB, asset originals, thumbnails,
  app-icon snapshots, sync staging.
- **Standard UserDefaults (device-local, never synced)**: non-sensitive local
  preferences such as the first-launch onboarding-hint dismissed/seen state
  (FR-014a) and Dock-icon preference mirror. No credentials, note content, or
  secrets ever live here.
- **Keychain**: WebDAV password/token, S3 access/secret keys, optional session
  token, remembered unlocked vault key material, certificate trust records.
- Never in SQLite/UserDefaults/logs/exported diagnostics/source-controlled
  config.
- GRDB `DatabasePool`, WAL mode, bounded busy timeout of 5 seconds (FR-140a),
  short write transactions. Manual-order sort keys use a 1024 gap with
  renormalization of a contiguous run when any adjacent gap falls below 64,
  executed within a single transaction (FR-022a). Main app owns migrations.
  Integrity checking, pre-migration backup, interrupted-migration recovery. A
  test fixture for every historical schema version.

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
- **Block presentation (FR-050b, clarified 2026-08-07)**: one unified block
  container style consistent with the note-window aesthetic (FR-030a corner
  radius family; no per-block borders/backgrounds by default; consistent
  vertical spacing). Categories are distinguished by inherent affordances
  only: todo checkbox, monospaced code font (FR-080), compact file card with
  FR-100 fields, framed media scaled from the FR-094a thumbnail (never
  decoded at full resolution). Per-category pixel spacing/border/background
  values beyond these affordances are implementation choices, not spec
  requirements.
- Rich-text block: SwiftUI `TextEditor` + `AttributedString` on macOS 26. An
  isolated **RichTextAdapter** converts between SwiftUI attributed state ↔
  canonical rich-text document ↔ searchable plain text. No arbitrary platform
  attributes enter storage.
- Editor plan covers: selection, cross-block focus movement, insert before/after
  special blocks, keyboard deletion at block boundaries, drag + keyboard
  reordering, undo/redo, auto-save, IME composition, pasted rich text, pasted
  Markdown, pasted images, link detection, accessibility actions.
- **Empty-block behavior (FR-050a, clarified 2026-08-07)**: an emptied block
  (paragraph/list item/todo/heading) stays in place while the cursor remains
  within it; on cursor exit the application removes it by merging with the
  adjacent block (or deleting when no merge is possible). The final block of a
  note is never removed this way — it remains an empty paragraph. Every
  automatic removal is reversible with a single Undo and never fires while an
  input-method composition is active (FR-063).
- **Cross-block selection (FR-054, clarified 2026-08-07)**: text selection MAY
  span block boundaries (paragraphs, list items, todo items, headings).
  Copying a spanning selection places both plain-text and rich-text
  (RTF/HTML) representations on the clipboard, where the rich representation
  contains only application-supported formatting (FR-053). Deleting a spanning
  selection removes only the selected characters; an emptied block is merged
  away per the FR-050a rules (single Undo restores). The trailing empty
  padding paragraph is never selectable. This is implemented in the editor's
  selection model (RichTextAdapter + block selection map) and covered by
  editor tests, without changing the canonical block model.
- **Keystroke latency instrumentation (SC-004a)**: OSLog signposts bracket the
  keystroke path (keystroke event → attributed-state mutation → glyph commit)
  so keystroke-to-glyph latency is measurable in Instruments and in a
  performance test; the measured bound is <16 ms during normal editing,
  including with Chinese IME composition active. This is validated in M1 along
  with the rest of the editor.
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
  whitespace-inferred. Maximum nesting depth of 6 levels (FR-072a); indent
  disabled at depth 6; validation rejects deeper hierarchies.
- Completion/incompletion, reorder, indent/outdent, child relationships, stable
  sync conflict preservation. Completing a parent does NOT
  silently change children (spec does not require it).
- Validation prevents: cycles, invalid parent refs, nesting deeper than 6
  (FR-072a), unnormalizable sort-key collisions, orphaned children after
  deletion.
- Pointer + keyboard operations. Todo actions address items by UUID.

### Code blocks

- Dedicated view + canonical payload: plain text, optional language label,
  monospaced, preserved whitespace, copy action, wrap-or-scroll per spec,
  keyboard movement into/out of block. No syntax-highlighting deps; no code
  execution.

### Auto-save

- Local-first. In-memory draft per open note; debounce ordinary text persistence
  **500 ms** (FR-141a — deterministic per build, decoupled from the 2-4 s sync
  debounce); save structural ops + todo completion immediately; flush on focus
  loss, before window close, before deletion, before application quit; never
  wait for remote sync to consider a local save complete.
- **Crash-loss contract (FR-141a, clarified 2026-08-07)**: after an abnormal
  process exit, the user loses at most the input entered within the last
  autosave debounce window (500 ms plus the in-flight write) and never loses
  content persisted by a completed autosave. Crash recovery is covered by
  automated tests that terminate the process mid-edit and verify restoration.
- **Empty-note auto-removal (FR-012/FR-013/FR-012a, clarified 2026-08-07)**:
  on window close, a newly created note that has never contained meaningful
  content MAY be auto-removed; a note that previously contained meaningful
  content MUST NOT be auto-deleted merely because its text is now empty.
  "Meaningful content" is precisely defined (FR-012a): at least one non-
  whitespace Unicode character in the title field or any rich-text block, OR
  the presence of any todo/image/screenshot/code-block/file-reference block.
  A single character (letter, digit, CJK, emoji, punctuation, any non-
  whitespace code point) qualifies; whitespace-only content does not. This
  makes the auto-removal decision objectively testable and guarantees a note
  with even one typed character is never silently deleted on close
  (Constitution III).
- Stale-debounced-write protection via revision tokens / serialized note-edit
  sessions. Crash-consistency behavior documented in research.md.
- **Async-feedback split policy (FR-141b, clarified 2026-08-07)**: background
  operations — automatic saving (FR-141a), search query updates (FR-024a),
  thumbnail generation (FR-094a) — are SILENT: no progress indicator,
  spinner, or completion toast, interface fully interactive. User-initiated
  operations — screenshot capture (FR-091), manual synchronization
  (FR-151), single-note JSON export/import (FR-031a) — provide explicit,
  non-blocking status feedback (status text or indicator in the relevant
  surface, localized per FR-180a). No async operation may block typing or
  other interaction (FR-153).

### Search

- SQLite FTS5 via GRDB, implemented as an **external-content table** backed by
  the canonical note/block rows with an explicit rowid-to-Note.id mapping
  (FR-023a). The external-content design guarantees the index cannot drift
  from canonical data: note deletion cascades to the FTS5 entry automatically.
  If drift is detected, the index is rebuilt from canonical data without loss.
- One searchable document per note: manual title, generated summary source,
  normal text, todo text, code text, file display names, screenshot captions,
  future OCR text. Indexed transactionally with note changes. Active notes by
  default; separate Trash scope. Results never reveal privacy-excluded notes.
  Performance tests at 10,000 notes.
- Search update latency per FR-024a: results begin updating within 100 ms of a
  query change and complete within the SC-005 target (200 ms for 10,000
  notes); incremental updates (partial results before full completion) are
  allowed.

### Asset storage

- Binary assets outside SQLite in the sandbox Application Support directory;
  opaque UUID filenames;
  separate originals/thumbnails/app-icons/temp-imports/sync-staging.
- Atomic temp-write + rename; SHA-256 hashes (FR-090a, Constitution IV);
  metadata transactions; cleanup queues; verify before deleting source/temp.
- Pasted images: embedded original, privacy-normalized metadata, async
  thumbnail, no original decode in card grid.
- Screenshots: static original, thumbnail at **256px longest edge**
  (FR-094a) — the single canonical thumbnail size for card-grid display,
  lossless preferred for text-heavy window captures, independent
  thumbnail storage, multiple per note, at most one cover enforced
  transactionally. No OCR in first release; model extensible for later OCR
  text.
- **Synchronized as independent encrypted objects** (FR-090a): originals,
  thumbnails, and app icons are each uploaded as their own encrypted envelope
  with a SHA-256 integrity hash, never bundled inside an encrypted note
  envelope. Each asset object is independently retried on partial upload/
  download failure (Constitution VIII); a failed asset upload MUST NOT block
  synchronization of the referencing note's metadata. The sync state for a
  note with a not-yet-uploaded asset is recorded as
  `partialAssetSyncFailure` so the asset retries independently without
  re-encrypting or re-uploading already-succeeded note metadata.
- **Scale limits (FR-090b, clarified 2026-08-07)**: a single asset (pasted
  image or screenshot original) is capped at 50 MB raw bytes and 16,384 px
  on the longest edge after capture/paste normalization; a single note's
  structured content (canonical envelope before asset payloads) is capped
  at 5 MB. Oversize insertions are rejected with a localized explanation and
  no partial asset write; oversize content changes are refused while
  preserving the last valid saved state. Limit constants are documented and
  covered by tests.

### Note appearance

- Six built-in colors with **one canonical sRGB hex each** (FR-040a, clarified
  2026-08-07): Yellow `#FFE08A`, Pink `#F9A8C4`, Purple `#C9A8E8`, Blue
  `#A8CFF9`, Green `#A8E8B8`, Gray `#D8D8DC` — shared across light/dark
  appearance. These values are the deterministic input for FR-042 WCAG 2.2
  contrast tests; any change to a canonical value updates the contrast tests
  in the same change.
- Background **opacity adjustable 40%–100% in 5-pt steps, default 100%**
  (FR-041a, clarified 2026-08-07); below 100%, FR-042 contrast validation
  and automatic foreground adjustment run against the effective composited
  background (note color at the chosen opacity over the desktop).
- Per-note text size: bounded 9–24 pt in 1-pt steps, default 13 pt
  (FR-043a, clarified 2026-08-07 — 16 discrete steps; text ≥18 pt is large
  text for the FR-042 contrast thresholds); global font preference with
  Chinese/English fallback (FR-043).

### Screenshot capture

- ScreenCaptureKit. Application-window capture uses the system content-sharing
  picker (no custom picker), single static frame, preserves app name/icon/title/
  capture time, no retained live stream. Region capture: single-frame capture +
  lightweight transparent multi-display selection overlay; handles Retina, multi
  display, rotation, coordinate conversion; cancels cleanly without creating a
  note/asset. Screen-recording permission requested only on capture invocation;
  no accessibility permission for ordinary capture. Opening a screenshot does
  not activate the original app.
- **Screenshot viewer (FR-095a, clarified 2026-08-07)**: opens in an
  independent, borderless, note-style window matching the FR-030a window style
  family (multi-window model per FR-005; several viewers may be open at once;
  images drag out). Bounded zoom 25%–400% in 25% steps via scroll wheel or
  pinch, with ⌘+/- keyboard equivalents; double-click toggles actual size
  (100%) ↔ fit-to-window. Arrow keys navigate between the screenshots of the
  same note; Return (or double-click on a screenshot) enters caption editing.
  The viewer never activates the captured application (FR-095).

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

### Widgets — REMOVED 2026-08-13

- ~~One WidgetKit + SwiftUI extension; AppIntent configuration; AppIntents for
  toggle-todo/create-note; deep links to open a specific note.~~
- ~~Data access via shared App Group SQLite in short transactions; todo updates
  in small atomic writes; change-driven timeline refresh (FR-110a).~~

All withdrawn with FR-110/FR-110a/FR-111/FR-112 (user decision — the
placeholder App Group cannot be registered without a paid developer account,
so widget data access could never work in production). No WidgetKit extension
ships; the per-note widget-eligibility field and the widget-selection store
are removed. URL routing below remains for external deep links.

- URL routing: `stickynotes://note/<uuid>`, `stickynotes://new`,
  `stickynotes://search` (placeholder scheme until final bundle id chosen).

### Global shortcuts — REMOVED 2026-08-10

- ~~Thin native adapter over Carbon `RegisterEventHotKey` (no Accessibility
  permission, conflict detection, unregister/re-register), shortcuts stored
  outside sync'd note data.~~
- **Removed** with FR-120/FR-121 (user decision — system-wide conflicts with
  other applications). The app registers no global hotkeys; the Settings
  General panel holds only the Dock toggle; in-app menu shortcuts (⌘N/⌘F/⌘W/⌘,)
  are unaffected. `SystemBridge` no longer links Carbon for hotkeys.

### Permissions

- Permission service exposes: current screen-recording status, current
  accessibility status, feature-specific explanation, request action,
  open-System-Settings action, denied-state recovery.
- Screen recording: requested only on capture invocation. Accessibility:
  reserved for future "identify active window"; not requested at startup or
  during ordinary window selection; advanced code behind a feature boundary.
  Denial affects only the related feature.

### Encryption architecture

- E2E encryption for all synced content + meaningful metadata. "Meaningful
  metadata" is positively enumerated in FR-160a (user-content fields from
  FR-161, semantic object types, structural metadata, note appearance/behavior
  choices, version-lineage fields revealing editing patterns); the accepted
  observable-leakage bound (opaque IDs, sizes, mod times, network addresses,
  access timing) is explicitly stated as a non-violation in FR-160b.
- Audited Argon2id package → KEK from sync password, using production minimum
  parameters of memory ≥ 19456 KiB (19 MiB), iterations ≥ 2, parallelism
  ≥ 1 (FR-160c, OWASP guidance); schema minimums (8/1/1) exist only for
  deterministic test fixtures. Random vault master key; CryptoKit HKDF-SHA-256
  for context-specific object keys; CryptoKit AES-GCM for authenticated
  encryption; Keychain for local secrets; secure random nonces/IDs. No
  hand-rolled crypto.
- **Vault bootstrap** (versioned): format version, random vault ID, random vault
  locator, Argon2id salt + params (≥ production minimums per FR-160c), wrapped
  master key, password-verification/key-confirmation material, encryption-suite
  version. Password protects master key (not every object). Password change
  re-wraps master key (FR-164).
- **Object-key derivation**: per-object key from context = {vaultID, objectID,
  objectType, schemaVersion, encryptionSuiteVersion}; same immutable context is
  AES-GCM AAD. Fail closed (FR-160d) on each of the exhaustively-enumerated
  inputs: wrong password; modified ciphertext; invalid/mismatched auth tag;
  mismatched object ID; mismatched object type; mismatched vault ID;
  unsupported envelope schema version; corrupted/truncated envelope structure.
  Each input is a required deterministic test vector (Constitution VII).
- **Encrypted envelope** (versioned): envelope version, opaque object ID, nonce,
  ciphertext, auth tag. Remote filenames random/opaque; no semantic type.
- **Key lifecycle**: minimize decrypted-key lifetime/duplication. Document when
  vault is unlocked, optional "remember unlocked vault on this Mac" (FR-162a:
  persists across app launches until the user logs out, restarts the Mac, or
  explicitly locks the vault; Keychain item cleared on lock; NOT a login-item-
  bound daemon that survives system restarts), how to lock, how remembered
  state is removed, Keychain-failure behavior, password-changed-elsewhere
  behavior, wrong-vault-selected behavior (fail closed with a clear
  "different vault detected" message; do not modify any local or remote data;
  user must choose a different repository or start a new empty vault that
  bootstraps alongside the existing one without overwriting it).
  Wrong-password unlock is stateless and never rate-limited/throttled/lockout-
  bounded (FR-160e); the Argon2id KDF cost is the rate limiter. App-launch
  unlock restores silently only when "remember" is enabled AND the boot
  timestamp matches (no restart) AND the vault was not explicitly locked;
  otherwise the password is required (FR-162a). Toggling "remember" off while
  unlocked clears the Keychain item immediately but preserves the current
  unlocked session until explicit lock or exit (FR-162a). Deterministic test
  vectors with no real secrets.

### Remote vault layout

- Provider sees only: random vault locator, opaque object names, sizes, mod
  times, network-level access metadata — the accepted observable-leakage bound
  (FR-160b), which reveals no user content, structure, or behavior beyond
  coarse object count and volume.
- Layout: one discoverable bootstrap object under the random vault locator; one
  encrypted manifest/index; independently encrypted note objects; independently
  encrypted asset objects (originals, thumbnails, app icons — each its own
  object per FR-090a, never bundled in note envelopes); independently encrypted
  tombstones. No uploaded SQLite DB, no bookmarks, no referenced-file content.
  Safe temp-upload + commit.

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
  2-4 seconds after the last local change (FR-152a debounce window; fires at
  end of quiet period; deterministic per build; cancelable by manual-sync /
  shutdown / network change); periodic (~15 min); startup; network
  restoration; manual; bounded best-effort at termination (never blocks
  indefinitely).
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
- **Sort-key-only divergence (FR-022b, clarified 2026-08-07)**: when two
  devices reorder notes independently and ONLY manual-order sort-key positions
  diverge (note content unchanged), the engine applies the most recently
  written sort key per note (last-writer-wins, deterministic via the note
  version's timestamp/sequence) and MUST NOT create conflict copies for
  sort-key-only divergence. Content divergence is evaluated on content fields
  only. This is a documented scoped interpretation of Constitution VIII:
  the no-silent-overwrite guarantee protects user content; reorder position
  is presentation metadata (FR-160a) whose loss carries no data-loss risk.
  A crossed-reorder test (A moves X above Y while B moves Y above X) is a
  required sync test.

### Deletion and tombstones

- Local delete → Trash 30 days. Permanent delete removes readable local content
  when safe, retains minimum tombstone for sync. Tombstones carry enough version
  info to prevent resurrection. Behavior defined for: offline <30 d, offline
  >30 d, delete-vs-edit, deleted asset refs, device returning after remote
  cleanup, unknown devices, manual Trash empty. Returning long-offline device
  reconciles remote deletion history before uploading locally-deleted notes. Not
  wall-clock "last modified wins".
- **Long-offline device returning after remote tombstone purge (FR-174
  clarification, 2026-08-07)**: the returning device MUST NOT auto-delete any
  local content. It reconciles against available remote deletion history: if no
  remote tombstone is found for a note, the device treats the note as "no
  remote deletion record found" and preserves it locally. Notes that the user
  deleted on the returning device MUST NOT be re-uploaded unless the user
  explicitly restores them. The application MUST inform the user that some
  synchronization history has aged out.
- **Empty Trash (FR-014b, clarified 2026-08-07)**: an "Empty Trash" action
  permanently deletes all notes currently in Trash in one batch. It requires
  explicit confirmation that states the notes are permanently deleted
  immediately and that the 30-day recoverability guarantee no longer applies.
  Executed deletions follow the permanent-deletion path (Trash-unrecoverable;
  tombstones and sync-safety rules still apply per FR-174). The action lives
  in the Trash view, is keyboard-accessible (FR-181), and is localized
  (FR-180a).

### Repository replacement and password changes

- User-safe workflows documented for: enabling sync on existing collection,
  joining existing vault, importing vault locator, wrong password, selecting
  repo with another vault (fail closed "different vault detected"; no local or
  remote data modified; user must choose a different repository or start a new
  empty vault that bootstraps alongside the existing one), disabling sync
  (retain local notes), forgetting local creds/unlocked key material,
  replacing WebDAV↔S3 (FR-154 clarification, 2026-08-07: replace after explicit
  warning + confirmation; local notes preserved; new vault bootstraps fresh;
  the application MUST NOT automatically delete the prior repository's remote
  data — server-side cleanup of the old vault remains a manual user
  responsibility), creating new empty vault, uploading existing notes to new
  vault, changing password, updating other Macs after password change,
  recovering from partial password-change propagation. Never silently delete
  remote data when local sync is disabled.

### Diagnostics and logging

- OSLog `Logger` with privacy annotations (dynamic values private by default).
  Logs never include content/titles/todo/code/file names/paths/window titles/
  captions/credentials/passwords/key material/complete responses/full object
  names where avoidable. Stable error domains + sanitized codes.
- **Exportable diagnostic bundle (FR-191 clarification, 2026-08-07)**: contains
  ONLY the following positively-enumerated fields — application version; macOS
  version; local schema version; sync provider type (WebDAV or S3 — never the
  endpoint URL, hostname, or credentials); normalized provider error categories
  with timestamps for the last 30 days (never raw server responses or bodies);
  synchronization run counts and durations (never payloads or object names);
  aggregate counts of notes / blocks / assets (never titles, summaries,
  captions, or content); vault state (locked or unlocked — never the password
  or derived key); permission statuses (screen-recording / accessibility
  granted-or-denied booleans). Any field not in this list is excluded by
  default. OS signposts on measurable paths.

### Error model

- Typed categories: Persistence, EditorConversion, AssetStorage, FileRefAccess,
  Capture, Permission, Encryption, Credentials, WebDAV, S3, SyncConflict,
  RemoteCorruption, SchemaCompatibility. Mapped to: silent retry / non-blocking
  status / inline recovery / blocking confirmation (destructive only).
  User-facing messages localized, no sensitive technical detail; diagnostics
  sanitized.
- **Library/search exception guarantee (FR-011a, clarified 2026-08-07)**: a
  failure in any library action (open note window, toggle/dismiss library,
  switch sort, manual reorder, search) MUST NOT crash the application, MUST
  NOT lose or corrupt note data, and MUST surface as a non-blocking,
  localized status message when user-visible (FR-141b/FR-191 sanitization).
  Two explicit cases: (a) note-window-open failure leaves the library
  usable, reports non-blockingly, and permits retry; (b) search with no
  results renders the unified empty-state (FR-014c) and is never treated
  as an error. Sort/reorder failures fall under the general guarantee plus
  FR-022a transactional persistence (no partial order observable).

### Accessibility

- VoiceOver labels/actions, keyboard navigation, focus order, menus/keyboard
  alternatives for hover controls, keyboard reordering of blocks/todos, keyboard
  indent/outdent, announcements for todo-state changes + failed file access +
  failed capture, Increased Contrast, Reduce Motion, light/dark, dynamic
  readable foreground colors, font fallback (Chinese/English), IME marked text,
  emoji, mixed-language editing. Custom colors failing contrast are adjusted
  for display or rejected with explanation. No essential command available only
  via hover.
- **Scoped labeling policy (FR-180b, clarified 2026-08-07)**: standard
  platform controls rely on platform-provided labels/actions (no custom
  labels duplicating visible text); custom-built controls MUST provide
  explicit localized labels and actions — file-reference card (open,
  reveal, copy path, relink, move, remove), screenshot viewer (zoom,
  actual size, fit-to-window, copy, drag out, Save As, delete association,
  edit caption, navigation), upper-area hover controls, and editor block
  affordances (todo checkbox with completed/incomplete state, code-block
  copy button, image/screenshot blocks). Required VoiceOver announcements:
  deletion toast (FR-009a) and completion of user-initiated operations
  with explicit status feedback (capture, manual sync, export/import per
  FR-141b).

### Localization

- String Catalogs; English + Simplified Chinese (**zh-Hans + en, FR-180a**,
  clarified 2026-08-07 — system-language switch; all user-visible strings
  from catalogs; note content never translated; the deletion toast announced
  by VoiceOver respects the active locale). Persisted enum values + sync
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
- ~~App Group GRDB access from Widget Extension~~ (removed 2026-08-13 with the
  widget surface).
- ScreenCaptureKit single-frame capture + region overlay.
- Confirm Xcode 26.x / Swift 6.3 baseline + select + integrate Argon2id package.
  (Global-shortcut prototype removed from the milestone 2026-08-10 — the
  feature is withdrawn, FR-120/FR-121.)

### Milestone 1 — Local core

Menu-bar library; independent note windows; persistence + migrations; rich text;
todos; code blocks; file references; search; colors/transparency (FR-040a
canonical hexes, FR-041a 40%–100%/5-pt opacity); Trash including **Empty Trash
(FR-014b)**; single-note **JSON export/import (FR-031a)**; window placement;
Dock preference. First-launch experience per FR-014a (empty-library
CTA, no premature permission prompts, "not configured" sync status, dismissible
onboarding hint) lands with the library. Keystroke-latency signposts and the
<16 ms measurement (SC-004a) land with the editor. Auto-save per FR-141a
(500 ms debounce, crash-loss contract) lands with the editor. (SyncCore/
SecurityCore present but inert.)

### Milestone 2 — System integration

Screenshot capture; embedded clipboard images; screenshot viewer;
permission UI; display restoration; accessibility polish; zh-Hans
+ en localization completion per FR-180a. (Global shortcuts removed from this
milestone 2026-08-10 — feature withdrawn.)

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
introduces no violations. Key confirmations (full per-FR detail lives in
spec.md and research.md R entries):

- Data model separates synchronized vs device-local fields, uses UUIDs +
  ordered migrations + version lineage; sort keys use the pinned 1024 gap with
  renormalization at <64 (FR-022a); todo nesting bounded at 6 levels (FR-072a);
  the FR-174 long-offline tombstone reconciliation is reflected in the
  Tombstone lifecycle and OfflineReconciler design (IV, VIII).
- Canonical contracts are versioned JSON with no platform archives / local
  paths / bookmark bytes (IV, VII, IX). File-reference locator is device-local;
  only generic metadata syncs (IX).
- Encryption envelope uses contextual AAD and fails closed; meaningful metadata
  positively enumerated (FR-160a), observable-leakage bound stated as
  non-violation (FR-160b), Argon2id production minimums enforced (FR-160c),
  fail-closed inputs exhaustively enumerated as test vectors (FR-160d);
  FR-162a remember-unlock lifetime and wrong-vault-selected fail-closed
  behavior reflected in the Key lifecycle and Repository-replacement sections
  (VII, VIII).
- Conflict + tombstone design is non-destructive with deterministic dedup
  (VIII). Sort-key-only divergence reconciles per-note by LWW, no conflict
  copies (FR-022b).
- Database concurrency uses a 5s bounded busy timeout (FR-140a).
- Assets sync as independent encrypted objects with SHA-256 + partial-failure
  retry (FR-090a); thumbnails pinned at 256px longest edge (FR-094a) so the
  card grid never decodes full-resolution images (XI, SC-008).
- Search uses an external-content FTS5 table with rowid-to-Note.id mapping
  (FR-023a), guaranteeing the index cannot drift from canonical data (IV).
- Sync debounce window pinned at 2-4 seconds (FR-152a) (VIII, XI).
- FR-191 diagnostic-bundle positive content boundary reflected in the
  Diagnostics section and the `diagnostic-bundle.schema.json` contract (VI,
  VII). FR-154 repository-replacement behavior reflected in the
  Repository-replacement section (VIII, III).
- FR-012a (meaningful-text boundary), FR-160e (no lockout), FR-022a
  Trash-restore, FR-162a app-launch + toggle-off, FR-031a export/import,
  FR-090b scale limits, FR-141a autosave, FR-022b, FR-040a/FR-041a,
  FR-050a, FR-014b, FR-180a, FR-001a, FR-020a, FR-043a, FR-095a,
  FR-054, and SC-004a are all reflected in the corresponding sections above,
  in data-model.md, and in the relevant contracts; each is traceable to its
  spec FR via the propagation summary near the top of this file (XIV).
- Session-2 clarifications are reflected likewise: FR-009 (sheet rule) in
  the menu-bar library scene, FR-011a in the Error model, FR-014c in the
  library empty-state design, FR-050b in the Editor architecture,
  FR-141b in Auto-save, and FR-180b in Accessibility (X, VI).
- Test strategy covers failure injection across editor/persistence/security/
  provider/sync/UI/performance (XII); the clarified FRs add testable scenarios
  listed in tasks.md Phases 16-23.
- Only GRDB + one audited Argon2id are approved; WebDAV/SigV4/crypto-envelope
  are project-owned (XIII).

No Complexity Tracking exceptions are required. The plan is ready for
`/speckit-checklist` and `/speckit-tasks`.

<!-- token-budget: compacted (level=medium) on 2026-08-07T08:59:57Z; original at plan.full.md -->
