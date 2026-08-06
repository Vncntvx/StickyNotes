# Research: macOS Sticky Notes

**Feature**: 001-sticky-notes-app | **Date**: 2026-08-06 | **Plan**: [plan.md](./plan.md)

This document records each major technical decision with rationale, alternatives
considered, rejected alternatives, risks, a validation plan, and constitution
impact. It resolves every `NEEDS CLARIFICATION` from the plan's Technical
Context.

> **Verification caveat**: The environment that generated this plan has only the
> Command Line Tools (no full Xcode, `xcodebuild` unavailable; Swift 6.4; macOS
> 27.0) and network access to external package indices / Apple docs was
> unavailable during planning. Decisions marked **[VERIFY IN M0]** are
> directions based on established Apple-platform knowledge that must be
> confirmed by a Milestone 0 prototype in a networked, full-Xcode environment.
> No external package name, version, or URL is asserted as a verified fact here;
> the Argon2id selection is a selection *process* with acceptance criteria, not
> a pre-verified choice.

## R0. Toolchain availability (Xcode / Swift / CI)

- **Decision**: Declare the project baseline as macOS 26 deployment target,
  Xcode 26.x (preferred 26.6), Swift 6.3 in Swift 6 language mode with strict
  concurrency. CI uses a stable macOS GitHub Actions runner with the selected
  Xcode 26.x.
- **Rationale**: The user-supplied baseline. macOS 26 is the constitution's
  minimum (Principle II). Swift 6 strict concurrency enforces the data-race
  safety the architecture relies on (Principles XI, XIII).
- **Alternatives considered**: Building against the local CLT-only Swift 6.4 /
  macOS 27 SDK. Rejected as the project baseline because there is no GUI/Widget
  toolchain, no XCTest GUI host, and the deployment target must stay macOS 26.
- **Rejected alternatives**: Adopting Swift 6.4 as the language baseline solely
  because the generating machine has it — would couple the project to a machine
  that cannot even build the app.
- **Risks**: If Xcode 26.6 is not yet available to contributors, the earliest
  stable Xcode 26.x is used; if a needed API is macOS-26-only it is gated
  behind availability checks.
- **Validation**: M0 confirms the exact installed Xcode version and records it
  in `Documentation/toolchain.md`; CI matrix pins the runner image.
- **Constitution impact**: Satisfies Principle II (macOS 26 minimum, SwiftUI-
  first) and XI (strict concurrency). No violation.

## R1. SwiftUI rich-text viability

- **Decision**: Use SwiftUI `TextEditor` with `AttributedString` on macOS 26 for
  the rich-text block, behind a `RichTextAdapter` protocol that converts to/from
  the canonical rich-text document and searchable plain text.
- **Rationale**: Principle II mandates SwiftUI-first. macOS 26 `TextEditor`
  supports attributed strings and run-scoped attributes sufficient for the
  spec's supported marks (bold/italic/underline/strike/inline-code/links/lists/
  heading).
- **Alternatives considered**: `NSTextView` via `NSViewRepresentable` from the
  start. Rejected: violates SwiftUI-first unless proven necessary.
- **Rejected alternatives**: A fully custom text layout engine; a third-party
  editor framework (constitutionally prohibited, Principle XIII).
- **Risks**: SwiftUI `TextEditor` may have gaps for IME marked-text edge cases,
  precise selection/cursor control at block boundaries, or programmatic scroll.
  These are the specific failure modes the M0 prototype must exercise.
- **Validation**: M0 prototype types Simplified Chinese with an active IME,
  mixed Chinese/English, emoji, applies Markdown inline conversion with
  single-Undo, and round-trips through the canonical format. Pass criteria:
  no composition corruption; one Undo restores exact source; canonical round-
  trip is lossless for supported marks.
- **Constitution impact**: Principle II (SwiftUI-first with isolated AppKit
  fallback only if proven). Principle V (only supported formatting persists).

## R2. NSTextView fallback criteria

- **Decision**: If M0 proves `TextEditor` cannot satisfy a *required* behavior,
  an isolated `NSViewRepresentable` wrapping `NSTextView` is used for the
  rich-text block ONLY, behind the same `RichTextAdapter` protocol.
- **Rationale**: A bounded, documented escape hatch keeps the project shippable
  without abandoning the canonical format or leaking AppKit into Domain.
- **Fallback requirements** (constitutional): documented as an architecture
  decision record; behind a protocol; canonical format unchanged; AppKit
  editing types confined to SystemBridge/EditorCore-internal adapter; specific
  evidence (which behavior, which macOS 26 `TextEditor` limitation) recorded.
- **Alternatives considered**: Widening to NSTextView for all blocks — rejected
  (over-broad). Dropping the failing feature — rejected only if the feature is
  a spec MUST.
- **Risks**: Two code paths to test. Mitigated by the protocol boundary and by
  test fixtures shared between both adapters.
- **Validation**: The fallback is adopted only after a recorded M0 failure with
  a reproducible case; both adapters pass the same canonical round-trip + IME +
  Undo suite.
- **Constitution impact**: Principle II (AppKit only through isolated adapter,
  with documented justification). Principle XIII (no third-party editor).

## R3. SwiftUI multi-window identity (one window per note)

- **Decision**: SwiftUI multi-window scenes keyed by note UUID, coordinated by a
  `NoteWindowCoordinator` that uses SystemBridge to register/focus the
  underlying `NSWindow`.
- **Rationale**: SwiftUI multi-window gives standard window behavior
  (accessibility, focus, resizing). The coordinator enforces the one-window-
  per-note invariant (FR-005) and focus-instead-of-duplicate (FR-005).
- **Alternatives considered**: Pure AppKit `NSWindowController` per note.
  Rejected as primary: violates SwiftUI-first; kept only as the thin bridge for
  level/frame/display handling.
- **Rejected alternatives**: A single window with tabs — does not match
  "independent windows" (spec).
- **Risks**: SwiftUI window identity/`$0`-based `openWindow` reliability across
  relaunch and Dock-activation changes. M0 validates.
- **Validation**: M0 opens note A, opens note B, re-selects A → A focuses, no
  duplicate; closes A (note preserved); toggles Dock accessory; reopens A.
- **Constitution impact**: Principle II and X (one window per note, close≠delete,
  no auto-restore after relaunch).

## R4. Dynamic Dock activation behavior

- **Decision**: Default `NSApplicationActivationPolicyRegular` (Dock icon on).
  User may switch to `accessory` at runtime via SystemBridge
  (`setActivationPolicy`) without restart where reliable. Settings/Help/About/
  sync status/Quit remain reachable from the menu-bar library.
- **Rationale**: FR-008. Switching policy at runtime is supported by AppKit;
  `MenuBarExtra` keeps the menu-bar entry point alive in accessory mode.
- **Command-Tab behavior**: In `regular` the app appears in the app switcher;
  in `accessory` it typically does not. This is an OS-level limitation to
  document, not work around.
- **Alternatives considered**: Require restart for the change. Rejected where
  runtime switch is reliable (better UX).
- **Risks**: Some window/activation quirks when switching policy with open
  note windows. Mitigation: coordinator re-evaluates window levels after a
  policy change. A widget opening a note MUST NOT temporarily flip to `regular`
  (FR-008/plan).
- **Validation**: M0 toggles the policy with 0 and 2 note windows open and
  confirms menu-bar access + no Dock flicker from widget deep links.
- **Constitution impact**: Principle X (Dock enabled by default, disable-able,
  menu-bar access preserved).

## R5. Global shortcut API

- **Decision**: Thin native adapter using the Carbon `RegisterEventHotKey` /
  `UnregisterEventHotKey` family for global hotkeys that do NOT require
  Accessibility permission. **[VERIFY IN M0]** exact symbol surface and Swift 6
  strict-concurrency interop (Carbon APIs are C/pointer-heavy; the adapter wraps
  them in an actor-isolated, `Sendable`-safe facade).
- **Rationale**: This family has historically been the macOS API for system-wide
  hotkeys without Accessibility permission, matching the plan's "prefer a
  system-level registration API that does not require Accessibility permission."
- **Alternatives considered**: A global event tap (`CGEvent` tap). Rejected for
  ordinary shortcuts: it typically requires Accessibility permission, which the
  constitution forbids requesting preemptively (Principle VI). An event tap may
  be revisited only for a future advanced feature with explicit permission.
- **Rejected alternatives**: A third-party global-shortcut package — prohibited
  unless M0 proves native APIs inadequate AND a constitution-compliant exception
  is documented (Principle XIII).
- **Risks**: Carbon hotkey API deprecation trajectory on macOS 26; conflict
  detection is best-effort (the system does not always expose existing
  bindings). Mitigation: detect registration failure and surface a clear
  localized error; allow re-registration.
- **Validation**: M0 registers/unregisters a shortcut, verifies it fires while
  another app is focused, verifies registration failure is detected, and
  confirms no Accessibility prompt appears.
- **Constitution impact**: Principle VI (no preemptive Accessibility request),
  XIII (no shortcut package unless justified).

## R6. App Group GRDB multi-process access (app + widget)

- **Decision**: GRDB `DatabasePool` with WAL mode in the App Group container.
  Main app owns migrations; widget performs only short reads and small atomic
  todo-toggle writes. Widget detects an unsupported schema version and falls
  back to privacy-safe read-only placeholders.
- **Rationale**: WAL allows concurrent readers + one writer across processes.
  Widgets must not run migrations or initialize sync (Principles VI, XI).
- **Alternatives considered**: `DatabaseQueue` (serial) for the widget only.
  Rejected: WAL pool is needed for app+widget concurrency and app
  read-during-write responsiveness.
- **Risks**: Cross-process write contention; a widget write during an app
  migration. Mitigation: bounded busy timeout; widget schema-version gate;
  widget writes are tiny and retried on `SQLITE_BUSY`.
- **Validation**: Persistence test suite runs app + widget processes
  concurrently (reads during writes, widget toggle during app migration) under
  WAL. Schema-mismatch fallback tested with a fixture.
- **Constitution impact**: Principle IV (migrations owned by app), VI/XI
  (widget never initializes sync, privacy-safe fallback).

## R7. ScreenCaptureKit region capture

- **Decision**: Use ScreenCaptureKit single-frame capture. For window capture,
  use the system content-sharing picker (no custom picker), capture one static
  frame, release the stream. For region capture, a lightweight transparent
  multi-display selection overlay lets the user draw a rectangle; capture a
  single authorized frame and crop to the selection (or capture only the
  selected area where supported).
- **Rationale**: Static screenshots only (spec non-goal: no live monitoring).
  ScreenCaptureKit is the modern, permission-aware capture API.
- **Handling**: Retina scale, multiple displays, rotated displays, and
  coordinate conversion between screen/overlay/capture spaces.
- **Alternatives considered**: `CGWindowListCreateImage` (legacy). Rejected as
  primary: ScreenCaptureKit is the forward path on macOS 26 and handles
  permissions more cleanly; legacy API kept only as a documented fallback if M0
  proves a specific gap.
- **Rejected alternatives**: Continuous streaming then picking a frame —
  violates "static snapshot, no live stream."
- **Risks**: Region overlay + coordinate conversion across mixed-DPI/rotated
  displays is the highest-risk capture item. Mitigation: M0 prototype on a
  multi-display Retina setup.
- **Validation**: M0 captures a window (via system picker) and a region (via
  overlay) on a Retina + external display, cancels cleanly (no note/asset
  created), and confirms no Accessibility prompt for ordinary capture.
- **Constitution impact**: Principle VI (screen-recording permission only on
  invocation; no Accessibility for ordinary capture), I (no live monitoring).

## R8. Security-scoped drag-out behavior

- **Decision**: Files are references via security-scoped bookmarks. Drag-out
  uses native transfer/file representation APIs to *copy or provide* the file
  without deleting it. Explicit "move original" is a separate command with a
  destination picker, confirmation, and verify-before-replace-bookmark.
- **Rationale**: FR-101/FR-102. Ordinary drag-out must never move/delete the
  original.
- **Multi-card-same-file-after-move**: An explicit move replaces the bookmark
  for the card that initiated the move. Other cards referencing the same
  original file are NOT silently rewritten; they retain their bookmark and will
  report "missing" with a relink offer if the original path no longer resolves.
  (Each card holds its own bookmark; bookmarks are per-reference, not shared.)
- **Alternatives considered**: Sharing one bookmark across all cards referencing
  the same file. Rejected: complicates per-card relink and stale-status
  semantics; per-card bookmarks are simpler and independently verifiable.
- **Risks**: Bookmark staleness after the user moves a file outside the app.
  Mitigation: availability status + relink; never filesystem-wide scan
  (FR-103).
- **Validation**: SystemBridge + file-reference tests: drag-out copies (original
  intact), explicit move updates only the initiating card's bookmark, a second
  card referencing the old path reports missing + offers relink.
- **Constitution impact**: Principle IX (references not attachments; explicit
  destructive move; no filesystem scan).

## R9. Argon2id package selection

- **Decision**: Select ONE small, maintained, auditable Argon2id implementation
  compatible with macOS 26 and Swift 6 strict concurrency. **[VERIFY IN M0]** —
  final package chosen in a networked environment by evaluating candidates on
  Swift Package Index / GitHub against the criteria below.
- **Selection criteria** (must all pass): active maintenance (recent commits,
  responsive issues); permissive license (MIT/BSD/Apache-2.0); public security
  review history or audited provenance; minimal API surface (Argon2id derive
  only); no (or minimal, audited) transitive dependencies; explicit Swift 6
  compatibility / `Sendable` annotations; Apple-platform support (macOS arm64 +
  x86_64); a documented replacement strategy; known limitations disclosed.
- **Rationale**: Principle VII forbids hand-rolling crypto; Principle XIII
  permits one audited Argon2id dependency. The KEK must come from Argon2id
  (memory-hard) rather than a fast KDF.
- **Alternatives considered**: Implementing Argon2id manually — explicitly
  forbidden (Principle VII). Using a fast KDF (PBKDF2/`CryptoKit` only) —
  rejected: insufficient memory-hardness for a password-derived KEK.
- **Rejected alternatives**: Bundling a large crypto library to get Argon2id —
  violates dependency minimization (Principle XIII).
- **Risks**: The chosen package may lag Swift 6 concurrency or have a
  transitive C dependency with build-size impact. Mitigation: the selection
  record (this section, finalized in M0) documents transitive deps + build-size
  + replacement/removal strategy before adoption.
- **Validation**: M0 integrates the chosen package, runs the security test
  vectors (correct/wrong password, re-wrap), and confirms a Swift 6 clean build.
- **Constitution impact**: Principle VII (no custom crypto; Argon2id for KEK),
  XIII (one audited dependency with documented decision).

## R10. WebDAV conditional writes

- **Decision**: Implement the required WebDAV subset over `URLSession`:
  `PROPFIND`, `MKCOL`, `GET`, `PUT`, `HEAD`, `DELETE`, with `ETag` +
  `If-Match` (conditional replace) + `If-None-Match` (conditional create),
  `Depth`, XML multistatus parsing, auth challenges, redirect safety.
- **Rationale**: Conditional writes enable the manifest commit + object
  precondition checks the sync engine needs (Principle VIII: explicit about
  version/precondition failures).
- **Alternatives considered**: A WebDAV library. Rejected (Principle XIII:
  project-owned code over large vendor SDKs; WebDAV subset is small).
- **Risks**: Server capability differences (some servers omit ETags or mangle
  `If-Match`). Mitigation: capability probe at connection test; surface a
  clear error if conditional writes are unavailable.
- **Validation**: Provider contract test suite (Put/Get/Head/conditional
  create/conditional replace/conditional failure/delete/missing/auth
  error/server error/timeout/cancellation/retry classification) against a
  standards-compliant local WebDAV server.
- **Constitution impact**: Principle VIII (idempotent, retry-safe, explicit
  precondition failures), XIII (project-owned).

## R11. S3-compatible conditional writes

- **Decision**: Implement AWS SigV4 in project-owned code over `URLSession`.
  Use conditional operations: `PutObject` with `If-None-Match: *` (create) and
  `If-Match: <etag>` (replace) where supported; otherwise versioned-bucket
  `If-Match` on the object version id.
- **Compatibility targets**: AWS S3, Cloudflare R2, MinIO, Backblaze B2 S3 API,
  generic SigV4 endpoints. Documented: canonical request construction, header
  normalization, URI/query encoding, payload hashing, clock-skew handling,
  error XML parsing, ETag limitations, multipart thresholds.
- **Rationale**: Principle VIII needs precondition failures; SigV4 in-house
  avoids the AWS SDK (Principle XIII).
- **Alternatives considered**: AWS SDK. Rejected (Principle XIII). Multipart —
  avoided in first impl unless required for supported screenshot sizes.
- **Risks**: ETag semantics differ across S3-compatible stores (some return
  non-content-hash ETags for multipart/encrypted objects); conditional-write
  support varies. Mitigation: manifest uses a single conditional-replaceable
  object; per-object uploads are immutable (no precondition needed) and
  referenced by the manifest; clock skew handled with a server-time check.
- **Validation**: Provider contract suite + opt-in credentialed compatibility
  tests (MinIO locally; AWS S3 / a hosted provider when secrets supplied).
- **Constitution impact**: Principle VIII, XIII.

## R12. Manifest concurrency

- **Decision**: A single encrypted manifest/index object is the serialization
  point. The `SyncActor` permits only one sync transaction per vault at a time
  locally; the remote manifest is committed via a conditional write
  (`If-Match`/versioned `If-Match`). On precondition failure, the engine
  re-fetches the manifest, re-compares, and retries (bounded).
- **Rationale**: One manifest + conditional commit gives safe multi-device
  serialization without a server-side transaction.
- **Alternatives considered**: Per-object independent versioning with no
  manifest. Rejected: makes listing/reconciliation expensive and leaks object
  counts/structure more than a single manifest does.
- **Risks**: Contended manifest under many fast devices. Mitigation: jittered
  backoff; the manifest is small; retries are cheap.
- **Validation**: Sync test "interrupted manifest commit" + "repeated retry" +
  "simultaneous edit" with a deterministic local provider.
- **Constitution impact**: Principle VIII (non-blocking, retry-safe, explicit
  precondition failures), XI (sync actor serializes vault mutation).

## R13. Self-signed certificate pinning

- **Decision**: Self-signed cert trust is an advanced option. TLS validation is
  NEVER disabled globally. On explicit user confirmation, the accepted
  certificate (or its public-key fingerprint) is pinned to the configured
  endpoint and stored securely (Keychain trust record). Certificate changes are
  detected and require re-confirmation with a clear warning.
- **Rationale**: Principle VIII (HTTPS only; self-signed only via explicit
  advanced action + clear warning).
- **Alternatives considered**: `URLSession` delegate disabling validation for
  the session. Rejected: too broad; pinning is narrower and safer.
- **Validation**: Security/provider test: pin a self-signed cert, confirm a
  changed cert is rejected with a warning, confirm trust record is stored in
  Keychain (not config files).
- **Constitution impact**: Principle VIII (HTTPS only; explicit self-signed
  trust).

## R14. Widget privacy behavior

- **Decision**: Widget eligibility is per-note. Widget-ineligible notes expose
  nothing (no title/body/todo/screenshot/summary) in timelines, previews,
  placeholders, or snapshots. Widgets read only the App Group DB in short
  transactions, never initialize sync, and show privacy-safe placeholders for
  deleted/trashed/conflicted/unavailable or schema-mismatched notes.
- **Rationale**: Principle VI (per-note widget privacy; no content exposure).
- **Alternatives considered**: A separate widget-specific projection table.
  Adopted as an implementation detail (a read-only card/todo projection) to
  keep widget reads short and to avoid exposing full rows.
- **Validation**: Widget tests confirm an ineligible note's content is absent
  from the timeline/snapshot, and that schema mismatch yields a placeholder
  without crashing.
- **Constitution impact**: Principle VI (widget privacy), XI (no full-res
  decode / bounded reads).

## R15. Long-offline deletion safety

- **Decision**: Tombstones retain version lineage (note UUID, deleted version
  ID, parent version ID, deleting device ID, deletion time) for 30 days. A
  returning long-offline device reconciles remote tombstone/deletion history
  BEFORE uploading local notes, so a note deleted elsewhere is not resurrected.
  Delete-vs-edit yields a recovered conflict copy, not a silent loss/resurrection.
  Not wall-clock "last modified wins."
- **Offline >30 days**: tombstone may have been cleaned up remotely; the
  returning device treats an unknown remote (no matching lineage) conservatively
  — it does not auto-delete local content; if its local version diverges from
  the last known common ancestor it creates a conflict copy on next sync.
- **Rationale**: Principle VIII (tombstones prevent resurrection; non-
  destructive; 30-day retention).
- **Alternatives considered**: Permanent tombstones. Rejected: unbounded growth.
  Hard 30-day cutoff ignoring sync safety. Rejected: could resurrect.
- **Validation**: Sync tests "long-offline device," "tombstone expiration,"
  "delete versus edit," "device returning after remote object cleanup."
- **Constitution impact**: Principle VIII (non-destructive sync, tombstones).

## R16. Unicode normalization and index stability

- **Decision**: The canonical rich-text model stores text as Unicode scalars
  with run boundaries expressed as scalar offsets, NOT as Swift `String.Index`
  values (which are not stable across serialization). Persisted text is
  normalized to a chosen form (NFC) at the canonical boundary; marks reference
  scalar offsets. Index stability is a property of the canonical document, not
  the runtime `AttributedString`.
- **Rationale**: Principle IV (stable, versioned, durable representation that
  does not rely on unstable runtime indices).
- **Alternatives considered**: Storing `AttributedString` runs with
  `String.Index`. Rejected: not serializable/stable. Storing byte offsets.
  Rejected: breaks on grapheme/normalization differences.
- **Validation**: Editor tests round-trip Chinese, mixed CJK/Latin, emoji, and
  combining marks through canonical ↔ attributed ↔ plain text, asserting offset
  stability and lossless marks.
- **Constitution impact**: Principle IV (explicit durable format), V (editor
  integrity with IME/emoji).

## R17. Auto-save crash-consistency

- **Decision**: Structural ops + todo completion persist immediately in short
  transactions. Ordinary text is debounced ~300 ms but flushed on focus loss,
  window close, and termination. A revision token / serialized note-edit
  session prevents a stale debounced write from clobbering a newer structural
  edit. WAL + atomic asset writes give crash consistency: a partially written
  asset is never referenced (metadata commit follows asset-rename verification).
- **Rationale**: Principle III (auto-save; local writes complete independently),
  IV (atomic asset writes).
- **Validation**: Persistence tests simulate a crash mid-debounce and mid-asset-
  write, asserting the last flushed state is intact and no orphan/partial asset
  is referenced.
- **Constitution impact**: Principle III, IV.

## R18. Conflict-copy determinism

- **Decision**: Conflict-copy creation is gated by a reconciliation record keyed
  by `(originalNoteUUID, localVersionID, remoteVersionID)`. Once a conflict copy
  is created for that key, retrying the same reconciliation reuses the existing
  conflict copy instead of making another.
- **Rationale**: Principle VIII (retry must not create unbounded duplicates).
- **Validation**: Sync test "conflict deduplication" retries reconciliation N
  times and asserts exactly one conflict copy.
- **Constitution impact**: Principle VIII.

## Resolved NEEDS CLARIFICATION

The plan's Technical Context had no product-level `NEEDS CLARIFICATION` markers
(the single spec clarification, menu-bar re-click behavior, was resolved during
`/speckit-specify` as FR-009). All technical unknowns above are resolved as
decisions with M0 validation where external verification was unavailable. No
item requires another `/speckit.clarify` run.

## Remaining risks (summary)

1. SwiftUI `TextEditor` IME/selection gaps → bounded NSTextView fallback (R1/R2).
2. Carbon global-hotkey deprecation/conflict-detection limits → best-effort with
   clear failure UX (R5).
3. Argon2id package Swift-6/build-size fitness → selection record finalized in
   M0 (R9).
4. S3-compatible ETag/conditional-write variance → manifest-as-serialization +
   immutable per-object uploads (R11/R12).
5. Region-capture coordinate conversion on mixed-DPI/rotated displays → M0
   prototype (R7).
6. Build environment: this plan was generated without a full Xcode install; all
   UI/Widget/capture assumptions are M0-validated (R0).
