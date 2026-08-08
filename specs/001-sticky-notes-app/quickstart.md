# Quickstart: macOS Sticky Notes

**Feature**: 001-sticky-notes-app | **Date**: 2026-08-06 | **Plan**: [plan.md](./plan.md)

This is a **validation/run guide**, not an implementation document. It describes
how to build, run, and validate the application end-to-end, and how to exercise
the migration, editor, and synchronization test suites. Implementation details
belong in `tasks.md` (generated later by `/speckit-tasks`).

## Required environment

- **macOS**: 26 or later (the minimum deployment target; preserved regardless of
  the dev machine's own OS version).
- **Xcode**: 26.x (preferred 26.6). A full Xcode install is required — the
  Command Line Tools alone cannot build the app/Widget targets or host XCUITest.
  See [research.md](./research.md) R0 for the toolchain note recorded during
  planning.
- **Swift**: 6.3, Swift 6 language mode, strict concurrency.
- **SwiftPM**: pinned via `Package.resolved`.

> If the installed stable toolchain differs, record the exact detected toolchain
> in `Documentation/toolchain.md`, explain the effect, and keep the macOS 26
> deployment target.

## Clone and build

```bash
git clone <repo-url> StickyNotes
cd StickyNotes
xcodebuild -resolvePackageDependencies -project StickyNotes.xcodeproj
```

**Project generation (T249 reconciliation)**: `StickyNotes.xcodeproj` IS
committed, and `project.yml` (XcodeGen) is the source of truth. When any
target/source/package configuration changes, regenerate with
`brew install xcodegen && xcodegen generate` and commit the regenerated
project. CI regenerates + runs `git diff --exit-code` as a drift check, so
forgetting to regenerate fails CI.

Build the app (debug, no code signing for local tests):

```bash
xcodebuild build \
  -project StickyNotes.xcodeproj \
  -scheme StickyNotes \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

## Placeholder App Group + entitlements setup

The app and Widget Extension share an App Group container. Until a final bundle
identifier is chosen, use a placeholder App Group identifier (e.g.
`group.local.stickynotes.placeholder`) configured identically in both targets'
entitlements:

- `App/Resources/StickyNotes.entitlements`: `com.apple.security.application-groups`
  entry + sandbox + `com.apple.security.files.user-selected.read-write` (+ write
  for screenshot Save As).
- `WidgetExtension/WidgetExtension.entitlements`: same App Group entry (read +
  limited write) so widgets can read the shared SQLite DB.

`PrivacyInfo.xcprivacy` lives under `App/Resources/` and documents screen-
recording usage (capture) only.

## Running the application

Open `StickyNotes.xcodeproj` in Xcode, select the `StickyNotes` scheme, and run
(⌘R). The menu-bar icon appears; click it to open the library.

## Validating the first-launch experience (FR-014a)

On a fresh install (delete the App Group container first — see *Resetting local
development data*):

1. Launch the app and open the menu-bar library: the card grid is empty with a
   clear call-to-action to create the first note (button and keyboard
   shortcut).
2. No permission prompts appear (no screen-recording, no accessibility, no
   notifications) — permissions are requested only when the corresponding
   feature is invoked.
3. With synchronization unconfigured, the sync-status area shows
   "not configured" — never an error.
4. A brief onboarding hint (auto-save + menu-bar-primary model) is visible and
   dismissible; after creating the first note, the hint is never shown again
   (relaunch the app to confirm).
5. The hint state keys never appear in an exported diagnostic bundle
   (FR-191 boundary).

## Measuring keystroke-to-glyph latency (SC-004a)

SC-004a requires keystroke-to-glyph latency below 16 ms (one frame at 60 Hz)
during normal editing, including with Chinese IME composition active. Measure
with:

- **Instruments**: profile the app with the Signpost Logging track and filter
  on the editor's keystroke interval; or
- **Automated**: the editor performance test types a mixed CJK/Latin/emoji
  sequence through the rich-text adapter and asserts the signposted
  keystroke-to-glyph interval stays below 16 ms on the supported baseline
  (see [research.md](./research.md) R29).

## Validating core-behavior clarifications (2026-08-07)

These scenarios validate the behavior fixed by the latest spec clarifications:

- **Auto-save + crash-loss (FR-141a)**: type into a note, stop for 500 ms,
  verify the note persists without any save command; kill the app process
  (or `kill -9`) within the debounce window and relaunch — at most the input
  from the last debounce window is lost, never content persisted by a
  completed autosave. Automated crash-recovery tests terminate the process
  mid-edit and verify restoration.
- **JSON export/import round-trip (FR-031a)**: from a note's contextual menu,
  export as JSON; import that JSON from the library; verify text,
  rich-text attributes, todos (text/state/nesting/order), code blocks,
  embedded images/screenshots, and appearance survive unchanged; file
  references import as generic-metadata-only cards. Importing a corrupted or
  unsupported-version JSON is refused with no partial note created.
- **Empty Trash (FR-014b)**: with notes in Trash, choose Empty Trash; the
  confirmation states immediate permanent deletion (30-day guarantee lost);
  after confirming, the notes are gone from Trash and tombstones follow
  sync-safety rules.
- **Scale limits (FR-090b)**: pasting an image over 50 MB or 16,384 px longest
  edge is rejected with a localized explanation and no partial asset;
  oversized note content is refused while the last valid state is preserved.
- **Widget change-driven refresh (FR-110a)**: with a widget configured, edit
  or todo-toggle the displayed note in the main app and confirm the widget
  updates shortly after without any fixed polling interval of its own.
- **Empty-block behavior (FR-050a)**: clear a paragraph mid-note — it stays
  while the cursor remains, is removed when the cursor exits, and a single
  Undo restores it; the final paragraph of a note is never removed.
- **Colors/opacity (FR-040a/FR-041a)**: each built-in color matches its
  canonical hex; opacity steps are 5% in 40%–100%; at any custom
  color + opacity step the text meets WCAG 2.2 AA (auto foreground
  adjustment applies below 100%).

## Running the Widget Extension

Select the `WidgetExtension` scheme and run (⌘R) onto the desktop to add a
widget. Configure a widget via its App Intent (select a note) to validate deep
links and todo-toggle-by-UUID.

## Running tests

Unit + integration (Swift Testing / XCTest):

```bash
xcodebuild test \
  -project StickyNotes.xcodeproj \
  -scheme StickyNotes \
  -destination 'platform=macOS'
```

> **UI-test runner Gatekeeper workaround (verified 2026-08-07)**: the first
> `xcodebuild test` run on a freshly built `AppUITests-Runner.app` can be
> blocked by a "damaged / downloaded at an unknown date" Gatekeeper dialog
> (unsigned runner carrying `com.apple.provenance` on this machine). Fix
> once per build before re-running:
>
> ```bash
> RUNNER=$(find ~/Library/Developer/Xcode/DerivedData -name "AppUITests-Runner.app" -maxdepth 6 | head -1)
> xattr -dr com.apple.provenance "$RUNNER"; xattr -dr com.apple.quarantine "$RUNNER"
> codesign --force --sign - --deep "$RUNNER"
> ```
>
> `spctl --assess --type execute "$RUNNER"` should return rc=0 afterwards.
> Without the UI-test target the unit/integration suites are unaffected
> (`-only-testing:AppTests`).

### Migration tests

`StickyCore/Tests/PersistenceTests` walks every historical schema fixture
(`Fixtures/schema_vN.sqlite`) forward to current and asserts row integrity, plus
an interrupted-migration recovery case (backup restore) and a widget schema-
mismatch fallback case.

### Editor tests

`StickyCore/Tests/EditorCoreTests` covers Markdown line/inline transforms,
single-Undo restoration, unmatched delimiters, code-fence behavior, and Chinese
IME / mixed CJK-Latin / emoji / pasted rich text / cursor-at-boundary cases.

### Synchronization tests

`StickyCore/Tests/SyncCoreTests` uses a deterministic local test provider with
failure injection (offline, interrupted upload/download, auth failure,
conditional-write failure, missing objects, corrupt ciphertext, concurrent
edits, delete-vs-edit, long-offline device, tombstone expiration, repository
replacement, password change, network loss/restoration).

## Configuring local WebDAV testing

Run a standards-compliant WebDAV server locally (e.g. a containerized WebDAV
image) bound to HTTPS with a valid local cert (or use the self-signed advanced
flow for testing only). Configure the repository in Settings → Synchronization,
test the connection, and trigger manual sync. Conditional-write support is probed
at connection test (see [research.md](./research.md) R10).

## Configuring local S3-compatible testing

Run MinIO locally and configure an S3-compatible repository with:
endpoint `http(s)://localhost:9000`, region, bucket, prefix, access/secret keys.
Credentials MUST be entered via the UI and stored in Keychain (never in config
files). Validate SigV4 against MinIO, then optionally against a hosted provider
or AWS S3 when credentials are supplied.

## Required environment variables

None for the application itself. **Opt-in** credentialed compatibility tests use
CI secrets (never committed):

- `STICKY_WEBDAV_TEST_URL`, `STICKY_WEBDAV_TEST_USER`,
  `STICKY_WEBDAV_TEST_PASS`
- `STICKY_S3_TEST_ENDPOINT`, `STICKY_S3_TEST_REGION`,
  `STICKY_S3_TEST_BUCKET`, `STICKY_S3_TEST_KEY`,
  `STICKY_S3_TEST_SECRET`, `STICKY_S3_TEST_TOKEN` (optional)

## Rules for test credentials

- Never commit credentials, tokens, or real vault passwords.
- Never include real note content or personal content in test fixtures.
- Deterministic CI tests use local test servers / mocks / in-process providers.
- Credentialed compatibility tests are gated and skipped when secrets are absent.

## Resetting local development data

Remove the App Group container + Keychain entries to start clean:

- Delete the App Group container directory for the placeholder group.
- Remove the app's Keychain items (WebDAV/S3 credentials, remembered vault key,
  cert trust records).
- Relaunch the app to recreate a fresh database (Milestone 1 behavior).

## Inspecting sanitized logs

Use Console.app filtering on the app's subsystem, or `log stream --predicate
'subsystem == <subsystem>'`. Dynamic values are private by default (OSLog
privacy annotations). The in-app "Export Diagnostics" action produces a bundle
containing app version, macOS version, schema versions, provider type,
sanitized codes, operation timing, object counts/sizes, redacted config, and
recent sanitized logs — no note content, file names, paths, or secrets.

## Building without code signing (local tests)

Pass `CODE_SIGNING_ALLOWED=NO` for local debug builds (see above). The Widget
Extension requires the App Group entitlement to be resolvable locally; for
widget testing on your own machine, a self-signed development identity suffices.

## Running the XCUITest critical flows (T305)

The AppUITests journeys need a **signed** app: an unsigned app cannot write
the App Group container on macOS (bootstrap fails and the menu-bar library
shows the database-error state). Build unsigned, ad-hoc sign app + widget,
then run without rebuilding:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  build-for-testing -project StickyNotes.xcodeproj -scheme StickyNotes \
  -configuration Debug CODE_SIGNING_ALLOWED=NO

APP=$(find ~/Library/Developer/Xcode/DerivedData/StickyNotes-*/Build/Products/Debug/StickyNotes.app -maxdepth 0 | head -1)
codesign --force --sign - --entitlements WidgetExtension/WidgetExtension.entitlements \
  "$APP/Contents/PlugIns/StickyNotesWidget.appex"
codesign --force --sign - --entitlements App/Resources/StickyNotes.entitlements "$APP"

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  test-without-building -project StickyNotes.xcodeproj -scheme StickyNotes \
  -destination 'platform=macOS' -only-testing:AppUITests/CriticalFlowsUITests
```

The screenshot-viewer journey is skipped when screen-recording permission is
not granted (headless CI stays green); the other journeys seed their note via
the test-only `-UITestSeedNote <marker>` launch argument — no synthetic
keyboard input, which is unreliable through XCUITest on macOS 27 beta.

## Avoiding committing secrets

- Keep all credentials in Keychain at runtime and in CI encrypted secrets for
  tests.
- Do not paste real provider credentials into Settings files, fixtures, or
  documentation.
- `.gitignore` must exclude the App Group container, derived data, and any local
  `.env`-style credential files.
- The `sync-profile-export` contract carries NO secrets (see
  [contracts/sync-profile-export.schema.json](./contracts/sync-profile-export.schema.json)).
