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
holding seven library modules (Domain, Persistence, EditorCore,
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

> **2026-08-07 clarification propagation (two `/speckit-clarify` sessions)**:
> Sixteen spec clarifications have been folded into this plan. The first five
> (FR-154 repository replacement, FR-162a remember-unlock lifetime, FR-174
> long-offline tombstone reconciliation, FR-191 diagnostic-bundle content
> boundary, and the wrong-vault-selected edge case) sharpen existing decisions
> without altering the architecture. The next eleven (FR-022a sort-key
> gap=1024/renorm-at-<64, FR-023a FTS5 external-content mode, FR-072a todo
> maxDepth=6, FR-090a assets as independent encrypted sync objects with
> SHA-256 + partial-failure retry, FR-094a 256px thumbnail longest edge,
> FR-140a 5s bounded busy timeout, FR-152a 2-4s sync debounce, FR-160a
> meaningful-metadata positive enumeration, FR-160b observable-leakage bound,
> FR-160c Argon2id production minimums ≥19 MiB/≥2 iter/≥1 lane, FR-160d
> exhaustive fail-closed input list) promote previously illustrative or
> plan-level values into binding spec requirements. The architecture is
> unchanged; the values below now cite their binding FR. The post-design
> Constitution Check (bottom of this file) remains PASS.
>
> **2026-08-07 UX-gap propagation**: a `checklists/ux.md` coverage review
> (CHK058) identified the first-launch experience as an undefined requirement;
> it is now binding in spec.md as **FR-014a** (empty library with a clear
> create-first-note call to action; no permission prompts on first launch
> unless the user invokes a feature requiring them; sync-status area shows
> "not configured" rather than an error when sync is unconfigured; a brief,
> dismissible onboarding hint explaining auto-save and the menu-bar-primary
> model, never shown again after the first note is created). The same review
> promoted "no visible lag" (SC-004) into a measurable bound, **SC-004a**
> (keystroke-to-glyph latency <16 ms during normal editing, including with
> Chinese IME composition active, measured via OSLog signposts/Instruments).
> These are UI/UX-facing requirements with no impact on the data model,
> contracts, or sync protocol; they are reflected below in the Menu-bar
> library, Local storage, Editor, and Milestones sections, in research.md
> R28/R29, and in the post-design Constitution Check. The post-design
> Constitution Check (bottom of this file) remains PASS.
>
> **2026-08-07 third `/speckit-clarify` session propagation**: five additional
> ambiguities were resolved and encoded in spec.md as **FR-012a** (meaningful-
> text definition for empty-note auto-removal: ≥1 non-whitespace Unicode
> character in the title or any rich-text block, OR the presence of any
> todo/image/screenshot/code-block/file-reference block; a single character
> qualifies, whitespace-only does not), **FR-160e** (wrong-password unlock
> attempts MUST NOT be rate-limited/throttled/lockout-bounded; Argon2id KDF
> cost is the rate limiter; no cached password/derived key), and expansions to
> **FR-022a** (Trash-restore resets sort-key to max+1024, placing at end of
> Manual order; pre-deletion key not retained) and **FR-162a** (app-launch
> unlock via boot-timestamp comparison — remember enabled + no restart →
> silent restore + startup sync; otherwise prompt; toggle-off while unlocked
> → immediate Keychain clearance but current session preserved until explicit
> lock/exit). These are reflected below in the Auto-save, Encryption
> architecture (Key lifecycle) sections, in data-model.md (Note lifecycle,
> VaultConfiguration with `rememberedUnlockBootTimestamp`), in
> `contracts/encrypted-envelope.schema.json` ($comment references FR-160e),
> and in research.md R30/R31/R32/R33 (R21 refined). None alter the
> architecture; all add testable acceptance criteria. The post-design
> Constitution Check (bottom of this file) remains PASS.
>
> **2026-08-07 fourth `/speckit-clarify` session propagation**: six additional
> ambiguities were resolved and encoded in spec.md as **FR-031a** (single-note
> JSON export/import reusing the canonical note-envelope schema; round-trip
> faithful; file-reference blocks export generic metadata only; import fails
> closed on unsupported/corrupted envelopes), **FR-180a** (zh-Hans + en
> UI localization, system-language switch), **FR-090b** (scale limits:
> single asset ≤ 50 MB and ≤ 16,384 px longest edge; note structured content
> ≤ 5 MB; oversize insertions rejected with a localized explanation),
> **FR-141a** (auto-save debounce 500 ms; flush before close/delete/quit;
> crash-loss window ≤ one debounce window; crash-recovery tests), and
> **FR-022b** (Manual-order sort-key divergence reconciled per-note by
> last-writer-wins, no conflict copies for sort-key-only divergence — a
> documented scoped interpretation of Constitution VIII protecting user
> content while treating reorder position as presentation metadata). Whole-
> library bulk export/import was explicitly declared a non-goal. These are
> reflected below in the Auto-save, Asset storage, Widgets, Conflict model,
> Localization, and Milestones sections, in data-model.md, and in research.md
> R34/R35/R36. None alter the architecture; all add testable acceptance
> criteria. The post-design Constitution Check (bottom of this file) remains
> PASS.
>
> **2026-08-07 fifth `/speckit-clarify` session propagation** (targeted at
> `checklists/ux.md` coverage gaps): five ambiguities were resolved and encoded
> in spec.md as **FR-040a** (one canonical sRGB hex per built-in color —
> Yellow #FFE08A, Pink #F9A8C4, Purple #C9A8E8, Blue #A8CFF9, Green #A8E8B8,
> Gray #D8D8DC — shared across light/dark, deterministic input for FR-042
> contrast tests), **FR-041a** (opacity adjustable 40%–100% in 5-pt steps,
> default 100%; contrast validation below 100% against the composited
> background), **FR-050a** (emptied blocks stay while the cursor remains, are
> removed on cursor exit — merge with adjacent block, final block stays as
> empty paragraph — and every removal is single-Undo reversible and never
> fires during IME composition), **FR-110a** (change-driven widget refresh:
> main app triggers affected widget timeline reloads on data change; no
> fixed high-frequency polling, consistent with SC-006), and **FR-014b**
> (Empty Trash batch permanent delete with explicit confirmation stating
> immediate deletion and loss of the 30-day recoverability guarantee).
> These are reflected below in the Note appearance/Editor/Widgets/Deletion
> sections and research.md R37/R38. None alter the architecture; all add
> testable acceptance criteria. The post-design Constitution Check (bottom
> of this file) remains PASS.

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
├── WidgetExtension/             # WidgetKit + AppIntents target
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

**Structure Decision**: A single local package `StickyCore` with seven
library SwiftPM targets is chosen over seven separate repos or one monolithic
app target. The seven library modules map 1:1 to the constitution's required separable concerns (domain,
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
- **First-launch experience (FR-014a)**: on first launch the library presents
  an empty card grid with a clear call-to-action to create the first note
  (button + keyboard shortcut). No permission prompts appear unless the user
  invokes the feature requiring them. When synchronization is not configured,
  the sync-status area shows "not configured" (never an error). A brief,
  dismissible onboarding hint explains auto-save and the menu-bar-primary
  model; the hint is never shown again after the first note is created. The
  dismissed/seen state is a device-local preference (App Group UserDefaults),
  never synchronized and never in canonical JSON (see Local storage).
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
- **App Group UserDefaults (device-local, never synced)**: non-sensitive local
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
  executed within a single transaction (FR-022a). Main app owns migrations;
  widgets detect unsupported schema and fall back to privacy-safe placeholders
  read-only. Widget read transactions MUST be short enough to complete well
  within the 5s timeout; on timeout the widget reports a sanitized
  "temporarily unavailable" status (never a raw error or note content).
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
  widget updates, sync conflict preservation. Completing a parent does NOT
  silently change children (spec does not require it).
- Validation prevents: cycles, invalid parent refs, nesting deeper than 6
  (FR-072a), unnormalizable sort-key collisions, orphaned children after
  deletion.
- Pointer + keyboard operations. Widget todo actions address items by UUID.

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

- Binary assets outside SQLite in App Group container; opaque UUID filenames;
  separate originals/thumbnails/app-icons/temp-imports/sync-staging.
- Atomic temp-write + rename; SHA-256 hashes (FR-090a, Constitution IV);
  metadata transactions; cleanup queues; verify before deleting source/temp.
- Pasted images: embedded original, privacy-normalized metadata, async
  thumbnail, no original decode in card grid.
- Screenshots: static original, thumbnail at **256px longest edge**
  (FR-094a) — the single canonical thumbnail size for card-grid and widget
  display, lossless preferred for text-heavy window captures, independent
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
- Per-note text size; global font preference with Chinese/English fallback
  (FR-043).

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
- **Change-driven refresh (FR-110a, clarified 2026-08-07)**: the main
  application proactively triggers a WidgetKit timeline reload for affected
  widget forms whenever local data affecting a widget changes (note created/
  edited/deleted/trashed/restored, todo toggled, widget-eligibility changed,
  conflict copy created). Widgets never poll the database on a fixed
  high-frequency schedule (SC-006); widget interactions (todo toggle,
  quick-create) also trigger refresh of the affected widgets. If the app is
  not running, widgets may show last-known content until the app next runs or
  the system refreshes the timeline; read failure reports the FR-140a
  "temporarily unavailable" status.
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
  **Wrong-password unlock attempts (FR-160e, clarified 2026-08-07)**: wrong-
  password unlock attempts MUST NOT be rate-limited, throttled, or lockout-
  bounded by the application. Every wrong-password attempt MUST fail closed
  (per FR-160d (a)) and MUST NOT cache the supplied password or derived key.
  Brute-force resistance relies entirely on the Argon2id production minimums
  in FR-160c (memory ≥ 19456 KiB, iterations ≥ 2, parallelism ≥ 1), which
  make each attempt computationally expensive. The application MUST NOT
  introduce account-lockout, timed backoff, or attempt-counting mechanisms,
  because such mechanisms could be used to denial-of-service a legitimate
  user in this local-first, no-account architecture, and because the
  Argon2id KDF cost itself serves as the rate limiter.
  **App-launch unlock behavior (FR-162a, clarified 2026-08-07)**: at
  application launch with auto-synchronization enabled, (a) if "remember" is
  enabled AND the Mac has not been restarted since the remembered unlock was
  stored (verified by comparing the system boot timestamp against the
  timestamp recorded at remember-time), the application silently restores
  the unlocked vault state from Keychain and triggers startup synchronization
  per FR-152a without prompting; (b) if "remember" is disabled, OR the Mac
  has been restarted since the remembered unlock, OR the user explicitly
  locked the vault, the application prompts for the synchronization password
  before any synchronization occurs. The boot-timestamp comparison makes the
  "restart clears remember" rule objectively testable.
  **Toggle-off behavior (FR-162a, clarified 2026-08-07)**: when the user
  toggles "remember unlocked vault" from enabled to disabled while the vault
  is currently unlocked, the application immediately removes the remembered
  key from Keychain (so future launches will not silently restore) but
  preserves the current unlocked vault state in memory until the user
  explicitly locks the vault or the application exits. The application MUST
  NOT force a re-prompt merely because the "remember" setting was toggled
  off — explicit lock remains a separate, intentional user action.
  Deterministic test vectors with no real secrets.

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
- App Group GRDB access from Widget Extension.
- ScreenCaptureKit single-frame capture + region overlay.
- Native global-shortcut registration (no Accessibility permission).
- Confirm Xcode 26.x / Swift 6.3 baseline + select + integrate Argon2id package.

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

Screenshot capture; embedded clipboard images; screenshot viewer; widgets
(including FR-110a change-driven timeline refresh); App Intents; global
shortcuts; permission UI; display restoration; accessibility polish; zh-Hans
+ en localization completion per FR-180a.

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
  UUIDs + ordered migrations + version lineage (IV, VIII). Manual-order sort
  keys use a pinned 1024 gap with renormalization at <64 (FR-022a); todo
  nesting is bounded at 6 levels (FR-072a). The 2026-08-07 FR-174
  clarification (long-offline tombstone reconciliation: never auto-delete
  local content; treat missing remote tombstone as "no deletion record found")
  is reflected in the Tombstone lifecycle and OfflineReconciler design (VIII).
- Canonical contracts are versioned JSON with no platform archives/local paths/
  bookmark bytes (IV, VII, IX).
- The encryption envelope uses contextual AAD and fails closed (VII).
  "Meaningful metadata" is positively enumerated (FR-160a) and the accepted
  observable-leakage bound is stated as a non-violation (FR-160b). Argon2id
  production minimums (≥19 MiB / ≥2 iterations / ≥1 lane, FR-160c) are
  enforced, with schema minimums reserved for test fixtures. The fail-closed
  input list is exhaustively enumerated as required test vectors (FR-160d).
  The FR-162a remember-unlock lifetime (persist across app launches until
  logout / restart / explicit lock; Keychain item cleared on lock; not a
  login-item daemon) and the wrong-vault-selected fail-closed behavior are
  reflected in the Key lifecycle and Repository-replacement sections (VII,
  VIII).
- Conflict + tombstone design is non-destructive with deterministic dedup (VIII).
- File-reference locator is device-local; only generic metadata syncs (IX).
- Widget access is minimal, privacy-safe, and never initializes sync (VI, XI).
  Database concurrency uses a 5s bounded busy timeout (FR-140a) so app+widget
  WAL access is testable and never deadlocks (XI).
- Assets are synchronized as independent encrypted objects with SHA-256
  integrity hashes and independent partial-failure retry (FR-090a); note
  metadata sync is never blocked by an asset upload failure (IV, VIII).
  Thumbnails use a pinned 256px longest edge (FR-094a) so the card grid and
  widget never decode full-resolution images (XI, SC-008).
- Search uses an external-content FTS5 table with rowid-to-Note.id mapping
  (FR-023a), guaranteeing the index cannot drift from canonical data (IV).
- The sync debounce window is pinned at 2-4 seconds (FR-152a), making the
  trigger observable in tests without blocking local editing (VIII, XI).
- The FR-191 diagnostic-bundle positive content boundary (app/OS/schema
  versions, provider type only, normalized error categories + timestamps, sync
  run counts/durations, aggregate object counts, vault locked/unlocked state,
  permission statuses — and nothing else) is reflected in the Diagnostics
  section and the `diagnostic-bundle.schema.json` contract (VI, VII).
- The FR-154 repository-replacement behavior (replace after warning +
  confirmation; local notes preserved; new vault bootstraps fresh; never
  auto-delete prior remote data) is reflected in the Repository-replacement
  section (VIII, III).
- **FR-012a (clarified 2026-08-07)** precisely defines "meaningful text" for
  empty-note auto-removal as ≥1 non-whitespace Unicode character in the title
  or any rich-text block, OR the presence of any structural block. This makes
  the auto-removal decision objectively testable and guarantees a note with
  even one typed character is never silently deleted on close (III, XII, X).
- **FR-160e (clarified 2026-08-07)** prohibits rate-limiting/throttling/
  lockout-bounding of wrong-password unlock attempts; brute-force resistance
  relies on the Argon2id KDF cost (FR-160c). This avoids a DoS-prone lockout
  in the no-account architecture while keeping fail-closed behavior
  stateless and testable (VII, VI). Reflected in the Key lifecycle section
  and the `encrypted-envelope.schema.json` $comment.
- **FR-022a Trash-restore (clarified 2026-08-07)** resets the restored note's
  `manualSortKey` to max(active)+1024, placing it at the end of Manual order
  and avoiding collisions with notes inserted during its absence. Reflected
  in the data-model Note lifecycle and Conventions (IV, XII, X).
- **FR-162a app-launch + toggle-off (clarified 2026-08-07)** makes the
  remember-unlock behavior at launch and on toggle-off precise: boot-
  timestamp comparison detects restart (silent restore only if remember
  enabled + no restart + not explicitly locked); toggle-off clears Keychain
  immediately but preserves the current unlocked session until explicit
  lock/exit. Reflected in the Key lifecycle section, data-model
  VaultConfiguration (`rememberedUnlockBootTimestamp`), and research.md
  R21/R33 (VII, VI, XII).
- Test strategy covers failure injection across editor/persistence/security/
  provider/sync/UI/performance (XII). The 2026-08-07 clarifications add
  testable scenarios: wrong-vault-selected fail-closed, long-offline
  tombstone-purge reconciliation, remember-unlock lifetime, diagnostic-bundle
  field-boundary verification, fail-closed test vectors (FR-160d), Argon2id
  production-minimum enforcement (FR-160c), sort-key renormalization
  (FR-022a), todo depth-6 validation (FR-072a), FTS5 drift/rebuild (FR-023a),
  5s busy-timeout concurrency (FR-140a), 2-4s sync debounce (FR-152a),
  independent-asset partial-failure retry (FR-090a), 256px thumbnail
  generation (FR-094a), meaningful-text auto-removal boundary (FR-012a),
  no-lockout wrong-password retry (FR-160e), Trash-restore sort-key reset
  (FR-022a), app-launch unlock via boot timestamp (FR-162a), toggle-off
  Keychain clearance + session preservation (FR-162a).
- Only GRDB + one audited Argon2id are approved; WebDAV/SigV4/crypto-envelope
  are project-owned (XIII).
- The FR-014a first-launch experience (empty library CTA; no permission prompts
  unless a feature is invoked; "not configured" sync status; dismissible
  onboarding hint never shown again after the first note) strengthens VI
  (least privilege — no preemptive permission requests) and X (reversible,
  accessible UX) while remaining fully local-first (III); the hint state is a
  device-local preference, never synced (IV, IX).
- SC-004a makes the keystroke-to-glyph latency bound (<16 ms) measurable via
  signposts, reinforcing XI (performance is measured, optimizations never
  compromise correctness/privacy) and XII (verification mandatory).
- **FR-031a (clarified 2026-08-07)** makes single-note JSON export/import reuse
  the canonical note-envelope schema — one format contract for sync, export,
  and import — with round-trip tests, generic-metadata-only file references,
  and fail-closed import validation (IV, VII, XII, X). Whole-library bulk
  export/import is a declared non-goal (I).
- **FR-090b (clarified 2026-08-07)** bounds scale (asset ≤ 50 MB / ≤ 16,384 px;
  note content ≤ 5 MB) so performance and sync behavior have deterministic
  limits; oversize insertions are rejected without partial writes (IV, XI, XII).
- **FR-141a (clarified 2026-08-07)** pins the auto-save debounce at 500 ms with
  flush-before-close/delete/quit and a crash-loss window of at most one
  debounce window, verified by crash-recovery tests (III, XII).
- **FR-022b (clarified 2026-08-07)** reconciles manual-order sort-key divergence
  per-note by last-writer-wins without conflict copies — a documented scoped
  interpretation of VIII: no-silent-overwrite protects user content; reorder
  position is presentation metadata with no data-loss risk (VIII, IV, XII).
- **FR-040a / FR-041a (clarified 2026-08-07)** pin canonical sRGB hex values
  and the 40%–100%/5-pt opacity range, making FR-042 contrast guarantees
  deterministically testable on every opacity step (X, XI, XII).
- **FR-050a (clarified 2026-08-07)** defines empty-block removal (removed on
  cursor exit, final block preserved, single-Undo reversible, never during IME
  composition), keeping the seamless editor intact and testable (V, X, XII).
- **FR-110a (clarified 2026-08-07)** makes widget refresh change-driven with no
  fixed high-frequency polling, preserving SC-006 while keeping widget data
  fresh (XI, VI).
- **FR-014b (clarified 2026-08-07)** adds Empty Trash with explicit
  confirmation stating immediate permanent deletion and loss of the 30-day
  guarantee; executed deletions still honor tombstones/sync-safety (X, VIII).
- **FR-180a (clarified 2026-08-07)** binds zh-Hans + en UI localization with
  system-language switching, including the VoiceOver-announced deletion toast
  (X, II).
- All design traces to spec FRs and acceptance scenarios (XIV).

No Complexity Tracking exceptions are required. The plan is ready for
`/speckit-checklist` and `/speckit-tasks`.
