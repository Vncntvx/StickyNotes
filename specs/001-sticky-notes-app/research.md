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
  migration. Mitigation: bounded busy timeout of 5 seconds (FR-140a); widget
  schema-version gate; widget writes are tiny and retried on `SQLITE_BUSY`; on
  timeout the widget reports a sanitized "temporarily unavailable" status
  (never a raw error or note content).
- **Validation**: Persistence test suite runs app + widget processes
  concurrently (reads during writes, widget toggle during app migration) under
  WAL with the 5s busy timeout (FR-140a). Schema-mismatch fallback tested with
  a fixture.
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
  Swift Package Index / GitHub against the criteria below. Production vault
  bootstrapping MUST use Argon2id parameters no weaker than memory ≥ 19456 KiB
  (19 MiB), iterations ≥ 2, parallelism ≥ 1 (FR-160c, OWASP guidance); the
  `vault-bootstrap.schema.json` minimums (8/1/1) exist ONLY for deterministic
  unit-test fixtures that exercise envelope parsing without paying the full
  derivation cost. Parameter values used at vault creation MUST be stored
  alongside the wrapped master key so future unlocks reproduce the derivation
  exactly.
- **Selection criteria** (must all pass): active maintenance (recent commits,
  responsive issues); permissive license (MIT/BSD/Apache-2.0); public security
  review history or audited provenance; minimal API surface (Argon2id derive
  only); no (or minimal, audited) transitive dependencies; explicit Swift 6
  compatibility / `Sendable` annotations; Apple-platform support (macOS arm64 +
  x86_64); a documented replacement strategy; known limitations disclosed;
  supports parameter sets at or above the FR-160c production minimums.
- **Rationale**: Principle VII forbids hand-rolling crypto; Principle XIII
  permits one audited Argon2id dependency. The KEK must come from Argon2id
  (memory-hard) rather than a fast KDF. FR-160c pins production-strength
  parameters so the encryption guarantee is testable and cannot be silently
  weakened to schema minimums.
- **Alternatives considered**: Implementing Argon2id manually — explicitly
  forbidden (Principle VII). Using a fast KDF (PBKDF2/`CryptoKit` only) —
  rejected: insufficient memory-hardness for a password-derived KEK.
- **Rejected alternatives**: Bundling a large crypto library to get Argon2id —
  violates dependency minimization (Principle XIII).
- **Risks**: The chosen package may lag Swift 6 concurrency or have a
  transitive C dependency with build-size impact. Mitigation: the selection
  record (this section, finalized in M0) documents transitive deps + build-size
  + replacement/removal strategy before adoption. A second risk is parameter
  drift over time; FR-160c requires review against contemporary OWASP guidance
  at each release.
- **Validation**: M0 integrates the chosen package, runs the security test
  vectors (correct/wrong password, re-wrap) at the FR-160c production
  parameters, confirms production bootstrapping rejects parameter sets weaker
  than the minimums, and confirms a Swift 6 clean build.
- **Constitution impact**: Principle VII (no custom crypto; Argon2id for KEK;
  FR-160c production parameters), XIII (one audited dependency with documented
  decision).

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
- **Offline >30 days with remote tombstone already purged (FR-174
  clarification, 2026-08-07)**: the returning device MUST NOT auto-delete any
  local content. It reconciles against available remote deletion history: if no
  remote tombstone is found for a note, the device treats the note as "no
  remote deletion record found" and preserves it locally. Notes that the user
  deleted on the returning device MUST NOT be re-uploaded unless the user
  explicitly restores them. The application MUST inform the user that some
  synchronization history has aged out. If the returning device's local version
  diverges from the last known common ancestor, it creates a conflict copy on
  next sync (per the conflict model).
- **Rationale**: Principle VIII (tombstones prevent resurrection; non-
  destructive; 30-day retention). The clarification closes the highest-risk
  tombstone edge case (research.md R15 / security.md CHK042): getting it wrong
  either resurrects a deleted note (violates VIII) or silently deletes local
  content the user still wants. The fail-safe direction is "preserve locally;
  never auto-delete; let the user decide."
- **Alternatives considered**: Permanent tombstones. Rejected: unbounded growth.
  Hard 30-day cutoff ignoring sync safety. Rejected: could resurrect. Treating
  absence of a remote tombstone as "note was never deleted" and re-uploading
  locally-deleted notes. Rejected: silently resurrects deleted notes remotely.
  Purging all local content older than 30 days to match remote state. Rejected:
  silently destroys local content the user may still want.
- **Validation**: Sync tests "long-offline device," "tombstone expiration,"
  "delete versus edit," "device returning after remote object cleanup." A
  specific test asserts: returning device with a locally-deleted note whose
  remote tombstone was purged → note is NOT re-uploaded; user is informed; no
  auto-delete of any local content.
- **Constitution impact**: Principle VIII (non-destructive sync, tombstones,
  no resurrection). The clarification strengthens, not weakens, VIII.

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
  transactions. Ordinary text is debounced **500 ms** (FR-141a, clarified
  2026-08-07 — deterministic per build, decoupled from the 2-4 s sync
  debounce) and flushed on focus loss, window close, note deletion,
  automatic-removal decisions, and application quit. A revision token /
  serialized note-edit session prevents a stale debounced write from
  clobbering a newer structural edit. WAL + atomic asset writes give crash
  consistency: a partially written asset is never referenced (metadata
  commit follows asset-rename verification).
- **Crash-loss contract (FR-141a)**: after an abnormal process exit, the user
  loses at most the input entered within the last autosave debounce window
  (500 ms plus the in-flight write) and never loses content persisted by a
  completed autosave; automated tests terminate the process mid-edit and
  verify restoration.
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

## R19. Repository replacement (WebDAV ↔ S3)

- **Decision**: Replacing an existing sync repository with a new one (WebDAV→S3,
  S3→WebDAV, or a different endpoint of the same type) requires an explicit user
  action with a clear warning and confirmation. Upon confirmed replacement:
  local notes are preserved; the new vault bootstraps fresh; the application
  MUST NOT automatically delete the prior repository's remote data — server-side
  cleanup of the old vault remains a manual user responsibility.
- **Rationale**: Principle III (local notes preserved regardless of sync state)
  and VIII (non-destructive sync; never silently delete remote data). The
  application has no business destructively touching a remote vault the user
  may still want (e.g., for rollback, or because the "replacement" was a
  mistake). Fail-safe direction: leave old remote intact; let the user clean up.
- **Alternatives considered**: Reject the new config and force a separate
  "Remove" step first. Rejected: clunkier UX with no safety gain, since the
  single confirmed replace already preserves local notes and never touches old
  remote data. Attempt to delete the old remote vault before bootstrapping the
  new one. Rejected: destructive to remote data the user may still want; also
  fragile if the old endpoint is unreachable.
- **Validation**: Sync test "repository replacement" asserts: after confirmed
  replace, local notes intact; new vault bootstraps; old remote data untouched
  (verified via provider test double that no DELETE was issued against the old
  locator); wrong-vault detection still fires if the new repo already contains
  a different vault.
- **Constitution impact**: Principle III (local-first), VIII (non-destructive),
  IX (file refs unaffected — they're device-local). Strengthens VIII.

## R20. Wrong-vault-selected detection

- **Decision**: When the user configures sync against a repository that already
  contains a different vault's bootstrap, the application MUST fail closed with
  a clear "different vault detected" message, MUST NOT modify any local or
  remote data, and MUST prompt the user to choose a different repository or
  start a new empty vault (which bootstraps alongside the existing one without
  overwriting it).
- **Rationale**: Principle VII (fail closed on unexpected object context) and
  VIII (non-destructive). The bootstrap object's `vaultId` is the authoritative
  check: if it doesn't match the locally-configured `vaultId` (or, for a new
  vault, if a bootstrap already exists under the chosen locator), the app
  refuses to proceed. This prevents accidental cross-vault corruption and
  gives the user a clear, actionable error.
- **Alternatives considered**: Offer to overwrite the remote vault after
  confirmation. Rejected: destructive to remote data; violates VIII.
  Silently join the existing vault and prompt for its password. Rejected: the
  user may have intended a fresh vault; silent join could mix unrelated note
  sets.
- **Validation**: SecurityCore / SyncCore test "wrong vault selected" asserts:
  bootstrap fetch returns a `vaultId` ≠ local; app returns a typed
  `Credentials.wrongVault` / `Encryption.wrongVaultContext` error; no PUT/DELETE
  issued to the remote; no local config mutation; user-facing message is
  localized and actionable. A second test asserts that starting a new empty
  vault on a repo that already contains a different vault's bootstrap
  bootstraps under a new random locator without overwriting the existing one.
- **Constitution impact**: Principle VII (fail closed), VIII (non-destructive).
  Strengthens VII/VIII.

## R21. Remember-unlock lifetime

- **Decision**: The optional "remember unlocked vault on this Mac" convenience
  (FR-162a) persists the remembered unlock across application launches until
  the user logs out, restarts the Mac, or explicitly locks the vault. The
  remembered key is stored in Keychain and cleared on explicit lock. The
  application MUST NOT behave as a login-item-bound daemon that keeps the vault
  unlocked across system restarts. Forgetting the synchronization password
  remains unrecoverable regardless of this setting (per FR-163).
- **App-launch unlock behavior (FR-162a, clarified 2026-08-07)**: at
  application launch with auto-synchronization enabled, if "remember" is
  enabled AND the Mac has not been restarted since the remembered unlock was
  stored (verified by comparing the system boot timestamp against the
  timestamp recorded at remember-time), the application silently restores
  the unlocked vault state from Keychain and triggers startup synchronization
  per FR-152a without prompting. Otherwise (remember disabled, Mac restarted,
  or vault explicitly locked), the application prompts for the password
  before any synchronization occurs.
- **Toggle-off behavior (FR-162a, clarified 2026-08-07)**: when the user
  toggles "remember" from enabled to disabled while the vault is currently
  unlocked, the application immediately removes the remembered key from
  Keychain (so future launches will not silently restore) but preserves the
  current unlocked vault state in memory until the user explicitly locks the
  vault or the application exits. The application MUST NOT force a re-prompt
  merely because the setting was toggled off.
- **Rationale**: Balances convenience against exfiltration risk (security.md
  CHK064). Persisting across normal app launches means users aren't re-entering
  the password daily, but a reboot/logoff forces re-entry, limiting the window
  if the device is stolen while unattended. "Not a login-item daemon" prevents
  the vault from being silently re-unlocked on every system start. The
  toggle-off-preserves-current-session rule avoids surprising the user with a
  re-prompt for an action that feels like it should only affect future
  behavior; the boot-timestamp comparison makes restart detection testable
  without relying on login-item or daemon behavior.
- **Implementation direction [VERIFY IN M0]**: store the wrapped/unwrapped key
  material in a Keychain item marked `kSecAttrSynchronizable = false` (iCloud
  Keychain sync disabled for this item) and clear it on explicit lock. Detect
  "restart" by capturing the system boot timestamp at remember-time and
  comparing it against the current boot timestamp at launch (via
  `ProcessInfo.systemUptime` combined with a persisted boot-time derivation,
  or `sysctl kern.boottime`). The boot timestamp is stored alongside the
  VaultConfiguration as a device-local field. Exact API confirmed in M0.
- **Alternatives considered**: Persist indefinitely until explicit lock (Option
  A). Rejected: too broad an exfiltration window. Never persist (Option C).
  Rejected: poor UX for a single-user multi-Mac product; defeats the
  convenience of the feature. Force re-lock on toggle-off (Option B for
  toggle). Rejected: punishes the current session for a future-affecting
  setting change.
- **Validation**: SecurityCore test asserts: remember-unlock enabled → relaunch
  app (no restart) → vault still unlocked without password re-entry; remember-
  unlock enabled → simulate restart (boot timestamp change) → vault locked,
  password required; explicit lock → Keychain item cleared; toggle-off while
  unlocked → Keychain item cleared but vault remains unlocked in session until
  explicit lock or exit; password forgotten → unrecoverable even with
  remember-unlock on.
- **Constitution impact**: Principle VII (E2E encryption; forgotten password
  unrecoverable), VI (Keychain for secrets). The clarification does not weaken
  VII — it only bounds the convenience window and makes the bound testable.

## R22. Diagnostic-bundle content boundary

- **Decision**: The user-exportable diagnostic bundle (the artifact a user may
  save and share for support) contains ONLY the following positively-enumerated
  fields: application version; OS version; local schema version; sync provider
  type (WebDAV or S3 — never the endpoint URL, hostname, or credentials);
  normalized provider error categories with timestamps for the last 30 days
  (never raw server responses or bodies); synchronization run counts and
  durations (never payloads or object names); aggregate counts of notes / blocks
  / assets (never titles, summaries, captions, or content); vault state (locked
  or unlocked — never the password or derived key); permission statuses
  (screen-recording / accessibility granted-or-denied booleans). Any field not
  in this list is excluded by default.
- **Rationale**: SC-010 and FR-191 forbid note content, file names/paths,
  window titles, credentials, etc. in logs/diagnostics, but did not positively
  enumerate what IS included (security.md CHK009). A positive, finite content
  boundary is testable by enumeration and lets reviewers decide whether a newly
  added field is in or out of scope. "Excluded by default" makes the safe
  direction the default.
- **Alternatives considered**: Include only app/OS/schema versions + a sync
  OK/error boolean (Option B). Rejected: too sparse to be useful for support.
  Include everything above plus redacted server response codes and hashed
  remote object names (Option C). Rejected: hashed object names still leak
  cardinality/structure; response codes add little over normalized error
  categories.
- **Validation**: `DiagnosticsPrivacyTests` (already mandated by T109) extended
  to assert the bundle contains exactly the enumerated fields and nothing else,
  using a fixture vault with known note/asset content that must NOT appear in
  the bundle. A schema (`contracts/diagnostic-bundle.schema.json`) enforces the
  boundary at the contract level.
- **Constitution impact**: Principle VI (privacy & least privilege), VII (no
  key material), VIII (no credentials). Strengthens VI.

## R23. Meaningful-metadata enumeration and observable-leakage bound

- **Decision**: "Meaningful metadata" that MUST be encrypted before upload is
  positively enumerated in FR-160a: (a) all user-content fields from FR-161;
  (b) semantic object types; (c) structural metadata (block ordering, todo
  nesting/completion, note-to-block composition, cover selection, sort-key
  position); (d) note appearance/behavior choices (color, transparency, text
  size, Always-on-Top, widget-eligibility); (e) version-lineage fields revealing
  editing patterns. The accepted observable-leakage bound (opaque IDs, sizes,
  mod times, network addresses, access timing) is explicitly stated as a
  non-violation in FR-160b.
- **Rationale**: Principle VII requires encrypting all "meaningful metadata,"
  but without a positive enumeration a future contributor could accidentally
  upload an unencrypted meaningful field (security.md CHK002/CHK013). The
  observable-leakage bound prevents reviewers from treating inherent protocol
  metadata as a privacy gap (security.md CHK011).
- **Validation**: SecurityCore test asserts every field in the FR-160a
  enumeration is encrypted before upload; a negative test asserts no field
  outside the FR-160b bound is left unencrypted.
- **Constitution impact**: Principle VII (E2E encryption), XIV (traceability).
  Strengthens VII.

## R24. Fail-closed input enumeration

- **Decision**: "Fail closed" (Constitution VII, FR-160) MUST be triggered by
  each input in the exhaustively-enumerated list in FR-160d: wrong password;
  modified ciphertext; invalid/mismatched auth tag; mismatched object ID;
  mismatched object type; mismatched vault ID; unsupported envelope schema
  version; corrupted/truncated envelope structure. Each input is a required
  deterministic test vector. The list is exhaustive for the initial release;
  any newly introduced envelope field or context dimension MUST add a
  corresponding fail-closed input and test vector in the same change.
- **Rationale**: Principle VII mandates "fail closed" but did not enumerate the
  triggering inputs, leaving the encryption correctness boundary untestable
  (security.md CHK012/CHK028/CHK029). A positive list makes each input a
  machine-checkable test vector.
- **Validation**: SecurityCore test suite includes one deterministic test
  vector per FR-160d input; each asserts the object is rejected without writing
  local data, accepting the remote object, or overwriting a local version.
- **Constitution impact**: Principle VII (fail closed; deterministic test
  vectors), XII (verification). Strengthens VII.

## R25. Thumbnail size, FTS5 mode, sort-key gap, todo depth

- **Decision**: Four previously-illustrative values are now binding spec
  requirements: (1) Thumbnail longest edge = 256px for card and widget display
  (FR-094a); (2) FTS5 search index is an external-content table backed by
  canonical note/block rows with an explicit rowid-to-Note.id mapping
  (FR-023a); (3) Manual-order sort keys use a 1024 gap, renormalizing a
  contiguous run when any adjacent gap falls below 64, within a single
  transaction (FR-022a); (4) Todo nesting depth is bounded at 6 levels,
  indent disabled at depth 6, validation rejects deeper (FR-072a).
- **Rationale**: Constitution IV (explicit durable data) and XII (testing)
  require these values to be concrete and testable, not illustrative. The
  external-content FTS5 mode guarantees the index cannot drift from canonical
  data (deletions cascade). The 256px thumbnail guarantees no full-res decode
  in the card grid (SC-008). The sort-key gap and renormalization threshold
  make reordering deterministic. The todo depth bound prevents unbounded
  recursion (data.md CHK011/CHK012/CHK013/CHK014).
- **Validation**: AssetStore test asserts thumbnail generation produces 256px
  longest edge. Persistence test asserts FTS5 index is external-content,
  deletion cascades, and drift triggers rebuild. Persistence test asserts
  sort-key insertion uses midpoint and renormalization fires at gap <64 in a
  single transaction. EditorCore test asserts indent is disabled at depth 6
  and validation rejects depth >6.
- **Constitution impact**: Principle IV (explicit durable data), XI
  (performance), XII (testing). No violation.

## R26. Bounded busy timeout

- **Decision**: Database access (SQLite via GRDB, WAL mode) uses a bounded busy
  timeout of 5 seconds (FR-140a). Widget read transactions MUST be short
  enough to complete within the timeout; on timeout the widget reports a
  sanitized "temporarily unavailable" status and retries on next refresh.
- **Rationale**: The app and widget share the SQLite DB in the App Group
  container; without a concrete timeout, concurrent WAL access could block
  indefinitely or report spurious errors (data.md CHK015/CHK016/CHK035). Five
  seconds gives the widget's short reads enough headroom to wait out an app
  write while still failing fast enough to surface real contention.
- **Validation**: Persistence test suite runs app + widget concurrently under
  WAL with the 5s timeout; asserts widget reads complete within the timeout
  under normal load and report "temporarily unavailable" (not a crash or raw
  error) under artificial contention.
- **Constitution impact**: Principle XI (performance; concurrency), VI (privacy
  — sanitized status). No violation.

## R27. Independent encrypted asset synchronization

- **Decision**: Assets (originals, 256px thumbnails per FR-094a, app icons)
  are synchronized as independent encrypted objects — never bundled inside an
  encrypted note envelope (FR-090a). Each asset object carries a SHA-256
  integrity hash (Constitution IV) for dedup and corruption detection. Each
  asset object is independently retried on partial upload/download failure
  (Constitution VIII); a failed asset upload MUST NOT block synchronization of
  the referencing note's metadata. The sync state for a note with a
  not-yet-uploaded asset is recorded as `partialAssetSyncFailure` so the asset
  retries independently without re-encrypting or re-uploading already-succeeded
  note metadata.
- **Rationale**: Bundling assets inside note envelopes would make large-asset
  sync non-resumable and block note metadata sync on a single failed upload
  (data.md CHK034, security.md CHK005). Independent objects with per-object
  retry match Constitution IV (atomic asset writes + hash-based dedup) and
  Constitution VIII (resistant to partial upload/download).
- **Validation**: SyncCore test injects a mid-asset-upload failure; asserts
  note metadata syncs successfully, asset state is `partialAssetSyncFailure`,
  and a subsequent sync run retries the asset independently without
  re-uploading the note metadata.
- **Constitution impact**: Principle IV (atomic writes; hashes), VIII
  (partial-upload safety), XI (off-main-actor asset work). No violation.

## R28. First-launch experience and onboarding-hint state

- **Decision**: The first-launch experience (FR-014a) presents an empty
  library with a clear call-to-action to create the first note (button +
  keyboard shortcut). No permission prompts are shown on first launch unless
  the user invokes a feature that requires them. When synchronization is not
  configured, the sync-status area shows "not configured" (never an error).
  A brief, dismissible onboarding hint explains auto-save and the
  menu-bar-primary model; it is never shown again after the first note is
  created. The hint's seen/dismissed state and the first-note-created flag are
  stored as device-local preferences in App Group UserDefaults — never in
  SQLite, never synchronized, never in canonical JSON.
- **Rationale**: FR-014a, Principle VI (permissions only on feature
  invocation), Principle III (local-first; sync absence is a normal state, not
  an error), Principle X (clear, reversible onboarding). UserDefaults is
  appropriate here because the state is a single non-sensitive boolean pair,
  is not needed by the widget, and must never appear in synced data; the
  Widget Extension does not read it (widgets show privacy-safe placeholders
  regardless).
- **Alternatives considered**: A `LocalPreferences` table in SQLite. Rejected
  as overkill for two booleans, though it remains an option if the preference
  surface grows; the data model documents the boundary (device-local
  preferences never sync). Showing a permission prompt on first launch to
  "prepare" capture. Rejected: violates Principle VI.
- **Validation**: App-level test/UI check: fresh launch → empty library CTA
  visible; no permission prompts appear; sync status shows "not configured";
  hint visible; create first note → hint never shown again; dismiss hint →
  not shown again. Preference keys never appear in exported diagnostics
  (FR-191 boundary) or synced objects.
- **Constitution impact**: Principle VI (least privilege), III (offline-first),
  X (reversible UX), IV (durable data boundary — device-local preference never
  leaks into synced format). No violation.

## R29. Keystroke-to-glyph latency measurement (SC-004a)

- **Decision**: The keystroke latency path is instrumented with OSLog
  signposts: begin on the keystroke event entering the editor, end when the
  attributed state commit drives the glyph update. Keystroke-to-glyph latency
  MUST be below 16 ms (one frame at 60 Hz) during normal editing, including
  with Chinese IME composition active (SC-004a). The measurement is exposed
  in Instruments and asserted by an editor performance test using an injected
  fake IME/marked-text sequence; the signpost markers themselves are
  disabled by default and carry no note content (Principle VI — no content in
  logs/signposts; only timing).
- **Rationale**: SC-004 "no visible lag" was not machine-checkable; SC-004a
  pins the bound and the measurement technique. The editor's input path is
  the same SwiftUI `TextEditor`/`AttributedString` path validated in M0
  (R1/R2); IME composition must not introduce re-decoding or full-document
  re-layout per keystroke.
- **Alternatives considered**: Instruments-only manual measurement without a
  test. Rejected: not automated (Principle XII). Measuring in production code
  with content-bearing logs. Rejected: privacy (Principle VI).
- **Validation**: EditorCore performance test types a mixed CJK/Latin/emoji
  sequence through the adapter and asserts the signposted interval <16 ms on
  the supported baseline; a manual Instruments profile (Signpost Logging
  track) confirms the same bound on the running app.
- **Constitution impact**: Principle XI (measured performance), XII
  (verification mandatory), VI (signposts carry timing only, no content). No
  violation.

## R30. Meaningful-text definition for empty-note auto-removal (FR-012a)

- **Decision**: "Meaningful text" for the empty-note auto-removal rule
  (FR-012/FR-013) is precisely defined (FR-012a, clarified 2026-08-07): a
  note contains meaningful content if its title field or any rich-text block
  contains at least one non-whitespace Unicode character, OR it contains any
  todo/image/screenshot/code-block/file-reference block. A single character
  (letter, digit, CJK character, emoji, punctuation, or any other non-
  whitespace code point) is sufficient; whitespace-only content (spaces,
  tabs, newlines, and other Unicode whitespace) does NOT qualify.
- **Rationale**: FR-012/FR-013 used the undefined term "meaningful text,"
  leaving the auto-removal decision untestable and risking silent data loss
  if a user typed a single character and closed the window (ux.md CHK023,
  CHK032). A one-non-whitespace-character threshold is the safest, simplest,
  most objectively testable definition; it aligns with Constitution III
  (local-first; never silently lose content) and Principle X (non-
  destructive). Treating any structural block (todo/image/etc.) as
  meaningful regardless of text length covers the cases where a user adds
  an empty todo or pastes an image without typing.
- **Alternatives considered**: Require ≥3 characters (Option B). Rejected:
  arbitrary, still loses a 1-2 character note. Require letters/digits/CJK
  only — punctuation/emoji not meaningful (Option C). Rejected: a user
  typing a single emoji or "?" deserves preservation; excluding them is
  surprising and culturally biased.
- **Validation**: EditorCore/Persistence test matrix: (a) note with only
  whitespace in title+body → auto-removable on close; (b) note with one
  non-whitespace char in body → NOT auto-removable; (c) note with one emoji
  → NOT auto-removable; (d) note with one punctuation char → NOT auto-
  removable; (e) note with only an empty todo block → NOT auto-removable
  (structural block present); (f) note that previously held content, now
  emptied → NOT auto-deleted (FR-013).
- **Constitution impact**: Principle III (never silently lose content),
  XII (testable), XIV (traceable). Strengthens III.

## R31. No rate-limit on wrong-password unlock attempts (FR-160e)

- **Decision**: Wrong-password unlock attempts MUST NOT be rate-limited,
  throttled, or lockout-bounded by the application (FR-160e, clarified
  2026-08-07). Every wrong-password attempt MUST fail closed (per FR-160d
  (a)) and MUST NOT cache the supplied password or derived key. Brute-force
  resistance relies entirely on the Argon2id production minimums in
  FR-160c (memory ≥ 19456 KiB, iterations ≥ 2, parallelism ≥ 1), which
  make each attempt computationally expensive. The application MUST NOT
  introduce account-lockout, timed backoff, or attempt-counting
  mechanisms.
- **Rationale**: In a local-first, no-account architecture, any lockout or
  attempt-counting mechanism could be used to denial-of-service a
  legitimate user (an attacker who knows the endpoint could trigger
  lockouts). The Argon2id KDF cost itself serves as the rate limiter: at
  ≥19 MiB memory and ≥2 iterations, each attempt takes hundreds of
  milliseconds to seconds, making remote brute-force infeasible while
  never blocking a legitimate user who simply mistypes. This is the
  standard pattern for password-based encryption (security.md CHK028).
- **Alternatives considered**: Lockout after N attempts (Option A).
  Rejected: DoS vector; unnecessary given KDF cost. Timed backoff
  (Option A variant). Rejected: same DoS concern. Require app restart
  after 3 failures (Option C). Rejected: punishes legitimate users for
  typos.
- **Validation**: SecurityCore test asserts: any number of wrong-password
  attempts yields the same fail-closed behavior with no state
  accumulation, no increasing delay, no lockout, and no caching of the
  supplied password or derived key. Performance test confirms a single
  Argon2id derivation with production minimums takes ≥100 ms (sanity
  bound on reference hardware), demonstrating the KDF-cost rate limiting.
- **Constitution impact**: Principle VII (fail closed; no DoS-prone
  lockout; KDF cost is the rate limiter), VI (no cached credentials).
  Strengthens VII and VI.

## R32. Trash-restore sort-key reset (FR-022a)

- **Decision**: When a note is restored from Trash (FR-014), its
  `manualSortKey` MUST be reset to (current maximum sort-key among active
  notes) + 1024, placing it at the end of Manual order (FR-022a,
  clarified 2026-08-07). The pre-deletion sort-key MUST NOT be retained.
- **Rationale**: During the note's absence, other notes may have been
  inserted or reordered, so the original position is no longer
  semantically valid and retaining the old key could collide with a new
  note's key or produce a surprising jump to a stale position. Appending
  to the end is the most predictable, conflict-free behavior: the new
  key is strictly greater than all existing keys, so restore alone never
  triggers renormalization. This matches the user intuition that a
  restored note is "rejoining" the list rather than "returning to a
  remembered spot" (data.md CHK038).
- **Alternatives considered**: Retain pre-deletion sort-key; renormalize
  on collision (Option A). Rejected: collisions possible; position
  surprise. Insert at nearest-neighbor position with gap check
  (Option C). Rejected: complex; may trigger renormalization; the
  "nearest" position is ill-defined after reordering.
- **Validation**: Persistence test: delete a note from the middle of
  Manual order, insert a new note (which may reuse the freed position),
  restore the deleted note → restored note's sort-key = max(active) +
  1024; it appears at the end; no renormalization triggered; ordering
  of other notes unchanged.
- **Constitution impact**: Principle IV (explicit durable data), XII
  (testable), X (predictable, non-surprising UX). No violation.

## R33. App-launch unlock and toggle-off semantics (FR-162a)

- **Decision**: Two FR-162a behaviors are precisely defined (clarified
  2026-08-07): (1) **App-launch unlock** — at application launch with
  auto-synchronization enabled, if "remember" is enabled AND the Mac has
  not been restarted since the remembered unlock was stored (verified by
  comparing the system boot timestamp against the timestamp recorded at
  remember-time), the application silently restores the unlocked vault
  state from Keychain and triggers startup synchronization per FR-152a
  without prompting; otherwise it prompts for the password. (2)
  **Toggle-off while unlocked** — when the user toggles "remember" from
  enabled to disabled while the vault is currently unlocked, the
  application immediately removes the remembered key from Keychain (so
  future launches will not silently restore) but preserves the current
  unlocked vault state in memory until the user explicitly locks the
  vault or the application exits; it MUST NOT force a re-prompt.
- **Rationale**: The original FR-162a stated the lifetime boundary
  ("persist across app launches until logout/restart/explicit lock") but
  did not define what happens at launch or on toggle-off, leaving both
  behaviors to implementation discretion (security.md CHK064). The
  boot-timestamp comparison makes "restart clears remember" objectively
  testable without relying on login-item or daemon behavior. The
  toggle-off-preserves-current-session rule avoids surprising the user
  with a re-prompt for a setting change that should only affect future
  launches; explicit lock remains the intentional re-authentication
  action.
- **Implementation direction [VERIFY IN M0]**: capture the system boot
  timestamp at remember-time (via `sysctl kern.boottime` or
  `ProcessInfo.systemUptime` + a persisted derivation) and store it as a
  device-local field on `VaultConfiguration` (`rememberedUnlockBootTimestamp`).
  At launch, compare the stored timestamp against the current boot
  timestamp; a mismatch indicates a restart since remember-time, so the
  Keychain item is treated as stale and the password is required. Exact
  API confirmed in M0.
- **Alternatives considered**: Always prompt at launch regardless of
  remember (Option B for launch). Rejected: defeats the convenience
  feature. Silently restore even after restart (Option C for launch).
  Rejected: violates FR-162a's "restart clears remember" rule. Force
  re-lock on toggle-off (Option B for toggle). Rejected: punishes the
  current session for a future-affecting setting change.
- **Validation**: SecurityCore test matrix: (a) remember enabled, no
  restart → launch restores unlock silently + triggers startup sync; (b)
  remember enabled, boot timestamp changed (simulated restart) → launch
  prompts for password; (c) remember disabled → launch prompts; (d)
  vault explicitly locked → launch prompts; (e) toggle-off while unlocked
  → Keychain item cleared, vault remains unlocked in session, no re-
  prompt, future launch prompts.
- **Constitution impact**: Principle VII (E2E encryption; restart
  clears remember), VI (Keychain for secrets; immediate clearance on
  toggle-off), XII (testable via boot timestamp). Strengthens VII and
  VI. No weakening.

## R34. Single-note JSON export/import reusing the canonical envelope (FR-031a)

- **Decision**: The note-level "export note as JSON" action emits a versioned
  JSON document built from the same canonical note-envelope schema used for
  encrypted synchronization (`contracts/note-document.schema.json`); the
  initial release also supports importing such a document (library-level
  action). Export→import is round-trip faithful for text, supported
  rich-text attributes, todos (text/state/nesting/order), code blocks,
  embedded images and screenshots (embedded as assets), and note appearance
  (color, transparency, text size, Always-on-Top). File-reference blocks
  export generic metadata only — never device-local bookmark data or
  absolute paths (FR-105). Import validates the schema version and fails
  closed on unsupported/corrupted envelopes without creating partial notes.
  Whole-library bulk export/import is a declared non-goal (clarified
  2026-08-07).
- **Rationale**: One schema = one format contract for sync, export, and
  import (Constitution IV); reusing the envelope avoids maintaining a second
  portable format and lets round-trip tests reuse canonical serialization
  tests. Bulk export was rejected to keep scope focused; sync serves as the
  multi-device redundancy path (Constitution I).
- **Implementation direction**: `Persistence`/`Domain` serializes a Note +
  its Blocks + referenced Asset payloads into the canonical document; the
  UI layer writes the file via an NSSavePanel (sandbox user-selected
  location); import reads via NSOpenPanel, validates, and inserts through the
  same repository path as any new note. Deterministic serialization per
  Constitution IV.
- **Alternatives considered**: Import-free export (rejected — round-trip is
  the portability guarantee); a separate human-readable export schema
  (rejected — two formats to maintain and test).
- **Validation**: round-trip tests across all block kinds; schema-version
  fail-closed import tests; file-reference metadata-only export assertions.
- **Constitution impact**: IV (versioned canonical JSON as the single
  portable format), XII (round-trip + fail-closed tests), X (explicit
  user action). No weakening.

## R35. Manual-order sort-key divergence: per-note last-writer-wins (FR-022b)

- **Decision**: When two devices reorder notes independently and only
  manual-order sort-key positions diverge (note content unchanged), the
  sync engine applies the most recently written sort key per note
  (last-writer-wins, deterministic via the note version's
  timestamp/sequence) and does NOT create conflict copies. Content
  divergence is evaluated on content fields only (clarified 2026-08-07).
- **Rationale**: A reorder position is presentation metadata (FR-160a
  enumerates manual sort-key position as structural metadata that is
  encrypted, not as user content); creating a conflict copy for a reorder
  disagreement would be user-hostile noise. This is a documented scoped
  interpretation of Constitution VIII: the no-silent-overwrite guarantee
  protects user content; LWW on a presentation field carries no data-loss
  risk and is applied per note, so no position change can corrupt another
  note's content version.
- **Implementation direction**: compare the note envelope's version lineage;
  if the ONLY diff is `manualSortKey`, accept the newer version's key
  without a divergence record. Crossed reorder (A moves X above Y while B
  moves Y above X) resolves deterministically per-note by version
  recency; no global order arbitration is attempted.
- **Alternatives considered**: Conflict copy on any envelope divergence
  (rejected — noise for reorders); deterministic set-merge of orderings
  (rejected — complex, still overwrites someone's preference, and is not
  required by the spec).
- **Validation**: sync tests for (a) sort-key-only divergence → LWW applied,
  no conflict copy; (b) crossed reorder → deterministic per-note outcome;
  (c) sort-key divergence combined with content divergence → content
  conflict copy still created with the winning content version.
- **Constitution impact**: VIII (scoped interpretation documented; content
  preservation unchanged), IV (deterministic reconciliation), XII
  (crossed-reorder test). No weakening.

## R36. Widget change-driven refresh (FR-110a)

- **Decision**: Widget content is refreshed change-driven: the main
  application proactively triggers a WidgetKit timeline reload for the
  affected widget forms whenever local data affecting a widget changes
  (note created/edited/deleted/trashed/restored, todo toggled,
  widget-eligibility changed, conflict copy created). Widgets never poll
  the database on a fixed high-frequency schedule; widget interactions
  (todo toggle, quick-create) also trigger refresh of affected widgets
  (clarified 2026-08-07).
- **Rationale**: SC-006 forbids high-frequency polling while idle; change
  notification is the standard macOS pattern (WidgetCenter
  `reloadTimelines(ofKind:)`). When the app is not running, widgets show
  last-known content until the app next runs or the system refreshes its
  timeline — acceptable for a menu-bar-primary app and consistent with
  FR-140a's "temporarily unavailable" read-failure status.
- **Implementation direction**: after any persistence write touching widget
  surface, call `WidgetCenter.shared.reloadTimelines(ofKind:)` for the
  affected kinds (cheap, no polling). Widget read transactions remain short
  (FR-140a 5 s bounded busy timeout).
- **Alternatives considered**: Fixed-interval timeline polling (rejected —
  violates SC-006 and wastes battery); system-default only (rejected —
  unbounded staleness for todo toggles).
- **Validation**: widget integration test: edit/toggle in the app → timeline
  reload observed for the affected kind; no periodic polling timers exist
  in the widget process.
- **Constitution impact**: XI (no idle polling; performance measured), VI
  (widget privacy unaffected), X (fresh data, graceful fallback). No
  weakening.

## R37. Canonical color hexes and opacity range (FR-040a / FR-041a)

- **Decision**: Each built-in color has exactly one canonical sRGB hex
  shared across light/dark (yellow #FFE08A, pink #F9A8C4, purple #C9A8E8,
  blue #A8CFF9, green #A8E8B8, gray #D8D8DC). Background opacity is
  adjustable 40%–100% in 5-pt steps, default 100%; below 100%, FR-042
  contrast validation and automatic foreground adjustment run against the
  effective composited background (clarified 2026-08-07).
- **Rationale**: FR-042's WCAG 2.2 AA guarantee is only testable with fixed
  input colors and a finite opacity step set; the chosen light pastel hexes
  keep dark text contrast comfortably above 4.5:1. A single hex per color
  keeps the test matrix small; light/dark differences are handled by the
  existing foreground auto-adjustment instead of doubling the color set.
- **Implementation direction**: store canonical hexes as constants in
  `Domain` (NoteAppearance); contrast logic tests iterate the 13 opacity
  steps × 6 colors (+ custom samples). Any hex change must update the
  contrast tests in the same change (Constitution IV).
- **Alternatives considered**: Dual light/dark hex sets (rejected — doubles
  the test matrix without product need); hex-free color families (rejected
  — untestable contrast).
- **Validation**: contrast matrix tests at every opacity step; hex constant
  assertions.
- **Constitution impact**: X (readable contrast), XI (bounded, tested
  appearance space), XII (deterministic contrast tests). No weakening.

## R38. Empty-block removal and Empty Trash (FR-050a / FR-014b)

- **Decision**: (1) **Empty blocks** (paragraph/list/todo/heading) stay in
  place while the cursor remains within them; on cursor exit the editor
  removes them by merging with the adjacent block (or deleting when no
  merge is possible), the final block of a note is never removed this way,
  every automatic removal is single-Undo reversible, and removal never
  fires during IME composition (FR-050a). (2) **Empty Trash** permanently
  deletes all trashed notes in one batch after explicit confirmation
  stating immediate permanent deletion and loss of the 30-day guarantee;
  executed deletions follow the permanent-deletion path with tombstones
  retained for sync (FR-014b) (both clarified 2026-08-07).
- **Rationale**: (1) Matches standard text-editor expectation (an emptied
  line survives while you keep typing; it disappears when you leave it)
  while keeping the block model canonical and Undo-consistent (Constitution
  V). (2) Batch empty matches macOS conventions and satisfies X's
  reversibility requirement via an explicit, explanatory confirmation
  (contrast with silent bulk delete).
- **Implementation direction**: (1) editor block-merge operation on cursor
  exit (one undo group); block model never contains persistent empty
  blocks after merge. (2) one transaction: trashed → permanentlyDeleted
  for all rows; tombstone creation per note; single confirmation dialog
  (localized).
- **Alternatives considered**: Immediate merge on empty (rejected — fighting
  the user mid-edit); keep-empty-blocks-always (rejected — empty blocks
  accumulate in the model); no Empty Trash (rejected — batch cleanup is
  expected).
- **Validation**: editor tests for cursor-exit removal, final-block
  preservation, single-Undo restore, IME-composition suppression; Trash
  tests for batch transition, confirmation gate, tombstone retention.
- **Constitution impact**: V (structured editor integrity), X (explicit
  destructive confirmation; single-Undo reversibility), XII (tests). No
  weakening.

## R39. Scale limits and zh-Hans + en localization (FR-090b / FR-180a)

- **Decision**: (1) **Scale limits (FR-090b)** — a single asset is capped at
  50 MB raw bytes and 16,384 px longest edge after capture/paste
  normalization; a single note's structured content (canonical envelope
  before asset payloads) is capped at 5 MB. Oversize insertions are
  rejected with a localized explanation and NO partial asset write (no
  orphan temp files, no metadata record); oversize content changes are
  refused while preserving the last valid saved state. (2) **Localization
  (FR-180a)** — user-facing UI is localized in zh-Hans + en following the
  system language preference; all user-visible strings come from String
  Catalogs; note content is never translated; the VoiceOver-announced
  deletion toast respects the active locale.
- **Rationale**: (1) Bounded scale keeps performance and sync behavior
  deterministic (Constitution XI) and prevents pathological notes/assets
  from degrading the library, editor, or sync (SC-005/SC-008); limits are
  enforced at the asset-store/persistence boundary, not in the UI. (2) The
  constitution requires Chinese + English text support (Principle X);
  binding the UI to zh-Hans + en makes localization completeness testable
  (SC-011 operability in either language).
- **Implementation direction**: (1) constants in AssetStore/Persistence
  (maxAssetBytes, maxAssetLongestEdge, maxNoteContentBytes) with rejection
  at write boundaries; (2) Localizable.xcstrings with zh-Hans + en variants
  for every key; source audit for hard-coded UI strings.
- **Alternatives considered**: (1) no caps with lazy/async degradation
  (rejected — untestable performance bounds; unbounded sync payload
  behavior); (2) English-only UI with Chinese content support (rejected —
  contradicts the bilingual requirement and the localized deletion toast).
- **Validation**: ScaleLimitTests (T227); LocalizationCompletenessTests
  (T230).
- **Constitution impact**: XI (bounded, measured performance), IV (explicit
  durable data with deterministic limits), X (readable, accessible, and
  bilingual UI), II (macOS conventions incl. system-language switch). No
  weakening.

## Resolved NEEDS CLARIFICATION

The plan's Technical Context had no product-level `NEEDS CLARIFICATION` markers
(the single spec clarification, menu-bar re-click behavior, was resolved during
`/speckit-specify` as FR-009). All technical unknowns above are resolved as
decisions with M0 validation where external verification was unavailable. No
item requires another `/speckit.clarify` run.

> **2026-08-07 clarification propagation (two `/speckit-clarify` sessions)**:
> The first pass resolved five encryption/privacy/sync requirements-quality
> gaps flagged by `checklists/security.md` (CHK008 repository-replacement,
> CHK009 diagnostic-bundle boundary, CHK015/CHK042 tombstone retention, CHK043
> wrong-vault, CHK064 remember-unlock). These are encoded in spec.md as
> FR-154 expansion, FR-162a (new), FR-174 expansion, FR-191 expansion, and two
> new edge cases. Research entries R15 (refined), R19, R20, R21, R22 (new)
> capture the technical decisions.
>
> The second and third passes resolved eleven additional data/security
> requirements-quality gaps, promoting previously-illustrative values into
> binding spec requirements: FR-022a (sort-key gap=1024/renorm-at-<64),
> FR-023a (FTS5 external-content mode), FR-072a (todo maxDepth=6), FR-090a
> (independent encrypted asset objects with SHA-256 + partial-failure retry),
> FR-094a (256px thumbnail longest edge), FR-140a (5s bounded busy timeout),
> FR-152a (2-4s sync debounce), FR-160a (meaningful-metadata positive
> enumeration), FR-160b (observable-leakage bound), FR-160c (Argon2id
> production minimums ≥19 MiB/≥2 iter/≥1 lane), FR-160d (exhaustive fail-closed
> input list as test vectors). Research entries R23 (new), R24 (new), R25
> (new), R26 (new), R27 (new), and R9 (refined for FR-160c) capture the
> technical decisions.
>
> None of these alter the architecture; all add testable acceptance criteria.
> No item requires another `/speckit-clarify` run.
>
> **2026-08-07 UX-gap propagation**: a `checklists/ux.md` coverage review
> (CHK058) flagged the first-launch experience as undefined and SC-004 "no
> visible lag" as unmeasurable. These are now binding spec requirements
> **FR-014a** (first-launch: empty-library CTA, no premature permission
> prompts, "not configured" sync status, dismissible onboarding hint never
> shown again after the first note) and **SC-004a** (keystroke-to-glyph
> latency <16 ms). Research entries R28 (first-launch experience + device-local
> onboarding-hint state) and R29 (signpost-based latency measurement) capture
> the technical decisions. Both are UI/UX-facing; no impact on contracts or
> the sync protocol.
>
> **2026-08-07 third `/speckit-clarify` session propagation**: five additional
> ambiguities were resolved and encoded in spec.md as **FR-012a** (meaningful-
> text definition for empty-note auto-removal: ≥1 non-whitespace Unicode
> char in title or any rich-text block, OR any structural block present),
> **FR-160e** (no rate-limit/throttle/lockout on wrong-password unlock;
> Argon2id KDF cost is the rate limiter), and expansions to **FR-022a**
> (Trash-restore resets sort-key to max+1024, placing at end of Manual order)
> and **FR-162a** (app-launch unlock via boot-timestamp comparison; toggle-off
> while unlocked clears Keychain immediately but preserves current session
> until explicit lock/exit). Research entries R30 (FR-012a), R31 (FR-160e),
> R32 (FR-022a Trash-restore), R33 (FR-162a launch + toggle), and R21
> (refined for FR-162a) capture the technical decisions. The
> `encrypted-envelope.schema.json` contract `$comment` now references
> FR-160e. None alter the architecture; all add testable acceptance criteria.
> No item requires another `/speckit-clarify` run.
>
> **2026-08-07 fourth `/speckit-clarify` session propagation**: FR-031a
> (single-note JSON export/import reusing the canonical note-envelope
> schema, generic-metadata-only file references, fail-closed import),
> FR-180a (zh-Hans + en UI localization), FR-090b (scale limits: asset
> ≤ 50 MB / ≤ 16,384 px; note content ≤ 5 MB; oversize insertions
> rejected), FR-141a (auto-save 500 ms debounce + crash-loss window ≤ one
> debounce window + flush before close/delete/quit), FR-022b (manual-order
> sort-key divergence reconciled per-note by LWW, no conflict copies);
> whole-library bulk export/import declared a non-goal. Research entries
> R34 (FR-031a), R35 (FR-022b), R36 (FR-110a) capture the technical
> decisions.
>
> **2026-08-07 fifth `/speckit-clarify` session propagation** (targeted at
> `checklists/ux.md` coverage gaps): FR-040a (canonical sRGB hex per
> built-in color), FR-041a (opacity 40%–100%, 5-pt steps, default 100%),
> FR-050a (empty-block removal on cursor exit, final block preserved,
> single-Undo, IME-safe), FR-110a (change-driven widget refresh, no fixed
> polling), FR-014b (Empty Trash with explicit confirmation). Research
> entries R36, R37 (FR-040a/FR-041a), R38 (FR-050a/FR-014b) capture the
> technical decisions.
>
> None of the fourth/fifth batches alter the architecture; all add testable
> acceptance criteria. No item requires another `/speckit-clarify` run.

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
