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

## Avoiding committing secrets

- Keep all credentials in Keychain at runtime and in CI encrypted secrets for
  tests.
- Do not paste real provider credentials into Settings files, fixtures, or
  documentation.
- `.gitignore` must exclude the App Group container, derived data, and any local
  `.env`-style credential files.
- The `sync-profile-export` contract carries NO secrets (see
  [contracts/sync-profile-export.schema.json](./contracts/sync-profile-export.schema.json)).
