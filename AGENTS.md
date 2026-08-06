# AGENTS.md

Specs-first repository for "macOS Sticky Notes" — a native, menu-bar-primary sticky-notes app for macOS 26+. **No application code exists yet**; everything lives in the single feature dir `specs/001-sticky-notes-app/` (spec, plan, tasks, research, data-model, quickstart, contracts/). Only one commit exists; work is driven through the Spec Kit (speckit) workflow, not ad-hoc editing.

## Workflow (critical)

- Use the speckit commands/skills (`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.implement`, …) wired in `.opencode/commands/` and `.claude/skills/`. Run them in order: specify → plan → tasks → implement, with review gates.
- `spec.md`, `plan.md`, and `tasks.md` are authoritative design artifacts. Implement per `tasks.md` — it defines exact repository paths (`App/Sources/…`, `WidgetExtension/`, `Packages/StickyCore/Sources/{Domain,Persistence,EditorCore,AssetStore,SecurityCore,SyncCore,SystemBridge}`) and module boundaries. Do not invent structure that contradicts the plan.
- Keep artifacts in sync: never change behavior in `spec.md`/`plan.md` outside the speckit flow (`speckit-analyze` checks cross-artifact consistency).
- "macOS Sticky Notes" is a **working title only** — never invent a final product or brand name (spec.md line 9).

## Documentation lookups (context7 MCP)

Before writing any code that touches a library, framework, or Apple API (GRDB, SwiftUI, WidgetKit, App Intents, OSLog, CryptoKit, …), query context7 for current docs — training data may be stale, and this project targets macOS 26 / Swift 6 APIs.

- Flow: (1) `context7_resolve-library-id` with the library name + what to look up; (2) pick the best match (exact name, benchmark score, source reputation; prefer version-specific IDs when a version matters); (3) `context7_query-docs` scoped to a **single concept** per call — split multi-topic questions into separate `query-docs` calls, max ~3 calls per question.
- Do not use for: refactoring, debugging business logic, code review, or general Swift language knowledge.
- Do not invent or guess API signatures for GRDB/macOS frameworks — verify via context7 first (e.g. GRDB migration + `DatabasePool`/WAL usage, FTS5 search, App Intent / WidgetKit entry points).

## Constitution constraints (non-negotiable)

- **Tests are written FIRST** and must fail before implementation (Constitution Principle XII, tasks.md header).
- Local-first, offline-complete; no developer-operated backend, no analytics/telemetry (FR-140, FR-190).
- Never commit credentials, keys, or real note content in fixtures. Credentials live in Keychain only. Sanitized logs/diagnostics must never contain note content, paths, or secrets (FR-165, FR-191).
- macOS 26 is the minimum deployment target; preserve it regardless of the dev machine's OS.

## Build & test (from quickstart.md — the validation guide)

```bash
xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'
```

- `CODE_SIGNING_ALLOWED=NO` for local debug builds.
- Test suites: `Packages/StickyCore/Tests/{PersistenceTests,EditorCoreTests,SyncCoreTests}` (+ migration fixtures `Fixtures/schema_vN.sqlite`).
- Credentialed WebDAV/S3 sync tests are opt-in via CI secrets (`STICKY_WEBDAV_TEST_*`, `STICKY_S3_TEST_*`) and must be skipped when absent — never commit real credentials.
- Naming inconsistency between docs: `tasks.md` T001 says workspace + app target `App`; `quickstart.md` uses `StickyNotes.xcodeproj` / scheme `StickyNotes`. Reconcile before Phase 1 work.
- Placeholder App Group: `group.local.stickynotes.placeholder` in both app and WidgetExtension entitlements.

## Environment gotchas

- This dev machine has only Command Line Tools (no full Xcode): Swift 6.4, macOS 27.0. App/Widget targets and XCUITest **cannot** build here. Intended toolchain: Xcode 26.x, Swift 6.3, Swift 6 language mode, strict concurrency. Record any actual toolchain in `Documentation/toolchain.md` (task T008) — do not silently change the deployment target or language mode.
- Intended architecture: modular monolith — app target + WidgetExtension + one local Swift package `StickyCore` (7 modules). GRDB SQLite (WAL, FTS5) in the App Group container is the source of truth; Keychain for credentials/secrets; sync is an additive E2E-encrypted layer (WebDAV or S3-compatible, one at a time).
