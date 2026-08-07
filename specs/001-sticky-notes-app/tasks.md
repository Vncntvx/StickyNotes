# Tasks: macOS Sticky Notes

**Input**: Design documents from `/specs/001-sticky-notes-app/`

**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, contracts/

**Tests**: MANDATORY for this project. The project constitution (Principle XII)
makes tests part of implementation, not optional follow-up work, and the plan's
testing strategy enumerates required suites. Every user story therefore includes
test tasks written FIRST (fail before implementation), per the spec/plan.

**Organization**: Tasks are grouped by user story to enable independent
implementation and testing of each story. Phases align with the plan's delivery
milestones (M0 prototypes → M1 local core → M2 system integration → M3 sync →
M4 release). The seven `StickyCore` modules (Domain, Persistence, EditorCore,
AssetStore, SecurityCore, SyncCore, SystemBridge) + App + WidgetExtension map to
file paths below.

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1–US10)
- Include exact file paths in descriptions
- Tests are written FIRST and must FAIL before implementation within each story

## Path Conventions

This is a native macOS app. Repository layout (from plan.md §Project Structure):

```text
App/Sources/{App,Features,Resources}
WidgetExtension/
Packages/StickyCore/Sources/{Domain,Persistence,EditorCore,AssetStore,SecurityCore,SyncCore,SystemBridge}
Packages/StickyCore/Tests/{DomainTests,PersistenceTests,EditorCoreTests,AssetStoreTests,SecurityCoreTests,SyncCoreTests,SystemBridgeTests}
AppTests/  AppUITests/  Documentation/  .github/workflows/
```

All paths below are repository-relative.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Xcode workspace, Swift package, targets, CI, App Group, entitlements.

- [X] T001 Create Xcode project via XcodeGen `project.yml` (source of truth) defining macOS app target `StickyNotes` and Widget Extension target `WidgetExtension` per plan.md §Project Structure; binary `StickyNotes.xcodeproj` is generated at build time, not committed
- [X] T002 [P] Create local Swift package `Packages/StickyCore/Package.swift` declaring 7 library targets (Domain, Persistence, EditorCore, AssetStore, SecurityCore, SyncCore, SystemBridge) + 7 test targets with dependency direction from plan.md §Module boundaries
- [X] T003 [P] Configure macOS 26 deployment target + Swift 6 language mode + strict concurrency + treat-warnings-as-errors for project-owned code in both Xcode project and Package.swift
- [X] T004 Add GRDB.swift as a SwiftPM dependency pinned via Package.resolved; wire into Persistence target only
- [X] T005 [P] Create App Group entitlement (`group.local.stickynotes.placeholder`) + sandbox + user-selected read/write in `App/Resources/StickyNotes.entitlements` and matching entry in `WidgetExtension/WidgetExtension.entitlements`
- [X] T006 [P] Create `App/Resources/PrivacyInfo.xcprivacy` documenting screen-recording usage (capture) only, per constitution Principle VI
- [X] T007 [P] Create String Catalogs `App/Resources/Localizable.xcstrings` with English + Simplified Chinese (zh-Hans) per plan.md §Localization
- [X] T008 [P] Set up `Documentation/toolchain.md` recording the detected Xcode/Swift toolchain and macOS 26 minimum target per research.md R0
- [X] T009 Create `.github/workflows/ci.yml` macOS runner with Xcode 26.x stages: dependency resolve, debug build, unit tests, migration tests, editor tests, security vectors, provider contract tests, sync tests, UI smoke, static warnings per plan.md §Testing and §Project Structure (.github/workflows/)
- [X] T010 [P] Configure `.gitignore` to exclude App Group container, derived data, local credential/env files per quickstart.md §Avoiding committing secrets

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T011 [P] Define Domain value types: `Note`, `Block`, `TodoItem`, `Asset`, `FileReference`, `ScreenshotAssociation`, `Tombstone`, `DeviceIdentity`, `VaultConfiguration`, `WindowState` (device-local frame), `SyncState` (device-local vault run state), `SearchDocument` projection in `Packages/StickyCore/Sources/Domain/Models/` per data-model.md §Entities (Foundation-only, Sendable)
- [X] T012 [P] Define Domain enums: `BlockKind`, `NoteColorKey`, `TextSize`, `NoteLifecycleState`, `FileAvailability`, `SyncVersionState` (per-entity sync lineage: unsynchronizedLocalModification/synchronizedVersion/divergentVersion/partialAssetSyncFailure per data-model.md §SyncVersionState) in `Packages/StickyCore/Sources/Domain/Models/Enums.swift`
- [X] T013 [P] Define Domain version-lineage struct (`versionId`, `parentVersionId`, `lastModifiedDeviceId`, `modifiedAt`) + sort-key normalization rules (1024-gap, renorm threshold 64, FR-022a) in `Packages/StickyCore/Sources/Domain/Models/VersionLineage.swift`
- [X] T014 [P] Define canonical rich-text model (paragraph/run/scalar-offset, NFC, supported marks) in `Packages/StickyCore/Sources/Domain/Models/RichTextDocument.swift` conforming to contracts/rich-text.schema.json
- [X] T015 [P] Define canonical note document + block payload types in `Packages/StickyCore/Sources/Domain/Models/CanonicalNote.swift` conforming to contracts/note-document.schema.json and contracts/block-payloads.schema.json
- [X] T016 [P] Implement deterministic JSON encoding/decoding for canonical types (stable keys, ISO 8601 UTC, UUID strings, explicit schemaVersion) in `Packages/StickyCore/Sources/Domain/CanonicalCoding.swift`
- [X] T017 Implement GRDB `DatabasePool` with WAL mode + bounded busy timeout in App Group container in `Packages/StickyCore/Sources/Persistence/DatabaseStore.swift`
- [X] T018 Implement ordered migration framework + `schema_migrations` table in `Packages/StickyCore/Sources/Persistence/Migrations/Migrator.swift`; main app owns migrations
- [X] T019 Create initial schema migration `v1` (all entities from data-model.md) in `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` with indexes from data-model.md §Indexes
- [X] T020 [P] Implement FTS5 `notes_fts` table + indexing on note change in `Packages/StickyCore/Sources/Persistence/FullTextSearch.swift`
- [X] T021 [P] Define repository protocols (NoteRepository, BlockRepository, TodoRepository, AssetRepository) in `Packages/StickyCore/Sources/Persistence/Repositories/` returning Sendable snapshots; concrete rows NOT exported as contracts
- [X] T022 Implement integrity check + pre-migration backup + interrupted-migration recovery in `Packages/StickyCore/Sources/Persistence/Recovery.swift`
- [X] T023 [P] Define typed error categories (Persistence, EditorConversion, AssetStorage, FileRefAccess, Capture, Permission, Encryption, Credentials, WebDAV, S3, SyncConflict, RemoteCorruption, SchemaCompatibility) in `Packages/StickyCore/Sources/Domain/Errors.swift`
- [X] T024 [P] Define small `AppEnvironment` with explicit-initializer DI (composed services, no DI framework) in `App/Sources/App/AppEnvironment.swift`
- [X] T025 [P] Define OSLog `Logger` wrappers with privacy annotations + sanitized error codes in `Packages/StickyCore/Sources/Domain/Logging.swift` per plan.md §Diagnostics

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 2.5: Milestone 0 Prototypes (Risk Gate)

**Purpose**: Validate highest-risk assumptions BEFORE broad feature work depends on them (plan.md §Milestone 0). This is a hard gate — user stories MUST NOT proceed until prototypes confirm feasibility.

- [ ] T025a Milestone 0 prototypes: SwiftUI rich-text + Chinese IME; Markdown single-Undo; one-window-per-note; per-window floating; App Group GRDB widget access; ScreenCaptureKit single-frame; native global shortcut; confirm Xcode 26.x/Swift 6.3 + integrate Argon2id per research.md R0–R18 in `Prototypes/` scratch directory outside the StickyCore package (no library/test target changes) — **partial**: headless prototypes (MarkdownUndo, AppGroupGRDB, GlobalShortcut criteria 1–3, Argon2id) PASS and are verified; GUI prototypes (RichTextIME, WindowCoordinator, ScreenCapture) compile under Xcode-beta but are NOT interactively verified. Interactive GUI verification is tracked as T158. T025a cannot be marked complete until T158 passes.

**Checkpoint**: Milestone 0 prototypes pass → high-risk assumptions de-risked; user stories may proceed.

---

## Phase 3: User Story 1 - Local Note Capture and Editing (Priority: P1) 🎯 MVP

**Goal**: User opens menu-bar library, creates a note, types, closes, reopens — content preserved without Save.

**Independent Test**: Click menu-bar icon → create note → type → close → reopen from library → verify text present and not duplicated.

### Tests for User Story 1 (write FIRST, must FAIL) ⚠️

- [X] T026 [P] [US1] Migration test: fresh DB creation + v1 schema integrity (covers schema creation only; migration-recovery scenarios are in T153) in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift`
- [X] T027 [P] [US1] Domain test: Note create/lifecycle + auto-discard empty note + preserve previously-content note when text empty in `Packages/StickyCore/Tests/DomainTests/NoteLifecycleTests.swift`
- [X] T028 [P] [US1] Domain test: canonical Note round-trip JSON lossless in `Packages/StickyCore/Tests/DomainTests/CanonicalNoteTests.swift`
- [ ] T029 [US1] Integration test: create note → close without save → reopen → content preserved; one window per note, focus not duplicate in `AppTests/NoteCaptureIntegrationTests.swift`

### Implementation for User Story 1

- [X] T030 [US1] Implement SQLite repository for Note + Block (CRUD, ordering) in `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift`
- [X] T031 [P] [US1] Implement auto-save draft manager (debounce ~300ms, structural ops immediate, flush on focus-loss/close/terminate, revision tokens) in `Packages/StickyCore/Sources/EditorCore/AutoSave.swift`
- [ ] T032 [US1] Implement SwiftUI `MenuBarExtra` window-style library scene with search/sort/new/Trash/sync-status/Settings/Help/Quit affordances in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (create-blank-note entry per FR-010)
- [ ] T033 [US1] Implement re-click behavior (focus if not focused, dismiss if focused, never second window) per FR-009 in `App/Sources/Features/Library/MenuBarLibraryScene.swift`
- [ ] T034 [US1] Implement SwiftUI multi-window note scenes + `NoteWindowCoordinator` (open by UUID, one window per note, focus existing, flush pending edits before close, no reopen after relaunch) in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift`
- [ ] T035 [US1] Implement AppKit bridge for `NSWindow` registration/focus/level in `Packages/StickyCore/Sources/SystemBridge/NoteWindowBridge.swift` (AppKit isolated here)
- [ ] T036 [US1] Implement basic rich-text `TextEditor` block view + `RichTextAdapter` (SwiftUI attributed ↔ canonical ↔ plain text) in `App/Sources/Features/Editor/RichTextBlockView.swift` and `Packages/StickyCore/Sources/EditorCore/RichTextAdapter.swift`
- [ ] T037 [US1] Implement card-grid note-card view in `App/Sources/Features/Library/NoteCardView.swift`

**Checkpoint**: User Story 1 fully functional and independently testable

---

## Phase 4: User Story 2 - Retrieval, Browsing, and Search (Priority: P1)

**Goal**: User searches across all active notes by any word, switches sort, finds notes with minimal effort.

**Independent Test**: Create several notes with varied titles/content → search a word appearing only in body/todo/code/filename → matching note appears; switch sort orders.

### Tests for User Story 2 (write FIRST, must FAIL) ⚠️

- [X] T038 [P] [US2] Persistence test: FTS5 indexes title/summary/body/todos/code/fileNames/captions and updates transactionally in `Packages/StickyCore/Tests/PersistenceTests/FullTextSearchTests.swift`
- [X] T039 [P] [US2] Performance test: search across 10,000 textual notes within 200ms in `Packages/StickyCore/Tests/PersistenceTests/SearchPerformanceTests.swift`
- [X] T040 [P] [US2] Domain test: generated summary does not silently become permanent title in `Packages/StickyCore/Tests/DomainTests/NoteSummaryTests.swift`
- [ ] T041 [US2] Integration test: sort switch (modified/created/title/manual) + manual reorder persists in `AppTests/RetrievalIntegrationTests.swift`

### Implementation for User Story 2

- [X] T042 [P] [US2] Implement search query + result update (active notes by default; privacy-excluded never revealed) in `Packages/StickyCore/Sources/Persistence/SearchService.swift`
- [X] T043 [P] [US2] Implement manual-order sort key + reorder (1024-gap, normalize on collision) in `Packages/StickyCore/Sources/Domain/Models/VersionLineage.swift`
- [ ] T044 [US2] Implement library search field + sort switcher UI with prompt result updates in `App/Sources/Features/Library/LibrarySearchView.swift`
- [X] T045 [US2] Implement generated-summary derivation (first meaningful content as temporary display title) in `Packages/StickyCore/Sources/Domain/NoteSummary.swift`

**Checkpoint**: User Stories 1 AND 2 work independently

---

## Phase 5: User Story 3 - Note Appearance and Independent Windows (Priority: P1)

**Goal**: User keeps a note visible as a colored sheet, sets Always-on-Top, adjusts transparency/text-size; note remembers size/position; disconnected-display window recovery.

**Independent Test**: Open note → choose color → enable Always-on-Top → resize/move → close/reopen → verify appearance/on-top/size/position persist; disconnect display → window returns to main display, remembers disconnected-display frame.

### Tests for User Story 3 (write FIRST, must FAIL) ⚠️

- [X] T046 [P] [US3] Domain test: color/transparency/textSize/alwaysOnTop persist per note in `Packages/StickyCore/Tests/DomainTests/NoteAppearanceTests.swift`
- [X] T047 [P] [US3] Persistence test: WindowState (frame, preferredDisplayUUID, fallbackFrame) stored device-local, never synced in `Packages/StickyCore/Tests/PersistenceTests/WindowStateTests.swift`
- [ ] T048 [US3] SystemBridge test: window-frame correction moves off-screen window to visible display + preserves disconnected-display preferred frame in `Packages/StickyCore/Tests/SystemBridgeTests/WindowFrameCorrectionTests.swift`
- [ ] T049 [US3] Integration test: Always-on-Top per note; contrast readable across light/dark/custom-color/transparency/increased-contrast in `AppTests/AppearanceIntegrationTests.swift`

### Implementation for User Story 3

- [X] T050 [P] [US3] Implement note appearance model (built-in colors Yellow/Pink/Purple/Blue/Green/Gray + custom) in `Packages/StickyCore/Sources/Domain/Models/NoteAppearance.swift`
- [X] T051 [P] [US3] Implement WindowState repository (device-local) in `Packages/StickyCore/Sources/Persistence/Repositories/WindowStateRepository.swift`
- [ ] T052 [US3] Implement upper control area (title/color/transparency/textSize/Always-on-Top/screenshot/file-ref/actions/close) hidden until pointer enter in `App/Sources/Features/NoteWindow/NoteControlsView.swift`
- [ ] T053 [US3] Implement per-window floating level via AppKit bridge in `Packages/StickyCore/Sources/SystemBridge/WindowLevelBridge.swift`
- [ ] T054 [US3] Implement display connect/disconnect handling + frame restoration + fallback frame in `Packages/StickyCore/Sources/SystemBridge/DisplayChangeBridge.swift`
- [ ] T055 [US3] Implement dynamic readable foreground colors + contrast adaptation (reject/adjust custom colors failing contrast) in `App/Sources/Features/NoteWindow/ReadableTheme.swift`

**Checkpoint**: User Stories 1–3 work independently

---

## Phase 6: User Story 4 - Todos, Code Blocks, and File References (Priority: P1)

**Goal**: User adds todos, inserts code blocks with copy, drops a Finder file as a reference openable/revealable without copying.

**Independent Test**: Add todos and toggle; insert code block and copy; drag a file into note then open/reveal from the note.

### Tests for User Story 4 (write FIRST, must FAIL) ⚠️

- [X] T056 [P] [US4] Domain test: TodoItem stable UUID across identical text/text-change/reorder (FR-071) + hierarchy validation (no cycles, depth bound ≤6 per FR-072a, no orphaned children). See also T189 for binding-value verification. in `Packages/StickyCore/Tests/PersistenceTests/TodoRepositoryTests.swift`
- [X] T057 [P] [US4] Domain test: code block preserves whitespace/tabs/line breaks; copy copies only code in `Packages/StickyCore/Tests/DomainTests/CodeBlockTests.swift`
- [X] T058 [P] [US4] Domain test: FileReference syncs only generic metadata; FileLocator bookmark/paths never in canonical JSON in `Packages/StickyCore/Tests/DomainTests/FileReferenceTests.swift`
- [ ] T059 [US4] SystemBridge test: drag-out copies without deleting; explicit move requires command+destination+confirmation+verify-before-replace; missing file preserves card + relink; no filesystem scan in `Packages/StickyCore/Tests/SystemBridgeTests/FileReferenceAccessTests.swift`
- [ ] T060 [US4] Integration test: todo complete state communicated by more than color alone (strikethrough) in `AppTests/TodoCodeFileRefIntegrationTests.swift`

### Implementation for User Story 4

- [X] T061 [P] [US4] Implement TodoItem repository (identity, hierarchy, sort-key, completion) in `Packages/StickyCore/Sources/Persistence/Repositories/TodoRepository.swift`
- [ ] T062 [P] [US4] Implement todo block view (complete/incomplete, drag reorder, indent/outdent, edit, delete, strikethrough) in `App/Sources/Features/Editor/TodoBlockView.swift`
- [ ] T063 [P] [US4] Implement code block view (monospaced, preserved whitespace, copy button, optional language label, wrap-or-scroll) in `App/Sources/Features/Editor/CodeBlockView.swift`
- [X] T064 [P] [US4] Implement FileReference + FileLocator models per data-model.md in `Packages/StickyCore/Sources/Domain/Models/FileReference.swift`
- [ ] T065 [US4] Implement security-scoped bookmark access (balanced start/stop) + availability status + relink in `Packages/StickyCore/Sources/SystemBridge/SecurityScopedBookmarks.swift`
- [ ] T066 [US4] Implement file-reference card view (name/icon/size/date/availability/origin device) + open/reveal/copy-path/drag-out/move/relink/remove in `App/Sources/Features/Editor/FileReferenceCardView.swift`
- [ ] T067 [US4] Implement drag-out (copy, never move/delete) + explicit move (destination picker + confirmation + verify) in `Packages/StickyCore/Sources/SystemBridge/FileDragOutBridge.swift`

**Checkpoint**: User Stories 1–4 work independently

---

## Phase 7: User Story 5 - Markdown Input and Undo (Priority: P1)

**Goal**: Markdown shortcuts convert to formatting; single Undo restores exact syntax; no corruption of Chinese/IME composition.

**Independent Test**: Type each Markdown pattern → converts → Undo once → exact syntax returns; repeat with active Chinese IME composition.

### Tests for User Story 5 (write FIRST, must FAIL) ⚠️

- [X] T068 [P] [US5] EditorCore test: line-level transforms (heading/bullet/todo/code-fence) trigger on space/confirm in `Packages/StickyCore/Tests/EditorCoreTests/MarkdownLineTransformTests.swift`
- [X] T069 [P] [US5] EditorCore test: inline transforms (bold/italic/strike/inline-code) trigger after valid closing delimiter in `Packages/StickyCore/Tests/EditorCoreTests/MarkdownInlineTransformTests.swift`
- [X] T070 [P] [US5] EditorCore test: single Undo restores exact Markdown syntax + formatting; unmatched delimiters ignored; no conversion inside code blocks except closing fence in `Packages/StickyCore/Tests/EditorCoreTests/MarkdownUndoTests.swift`
- [X] T071 [P] [US5] EditorCore test: no corruption of Chinese IME marked text / mixed Chinese-English / emoji / partial syntax in `Packages/StickyCore/Tests/EditorCoreTests/IMECompositionTests.swift`
- [X] T072 [P] [US5] EditorCore test: canonical rich-text round-trip lossless for supported marks; unsupported attributes stripped in `Packages/StickyCore/Tests/EditorCoreTests/RichTextRoundTripTests.swift`

### Implementation for User Story 5

- [X] T073 [US5] Implement Markdown transformation state machine (line-level + inline, ignores unmatched, skips when IME marked text active, one undo group) in `Packages/StickyCore/Sources/EditorCore/MarkdownTransformer.swift`
- [X] T074 [US5] Implement editor command layer over `UndoManager` (cursor placement after conversion) in `Packages/StickyCore/Sources/EditorCore/EditorCommands.swift`
- [ ] T075 [US5] Wire Markdown transforms into rich-text block view with IME-safe transformation decisions in `App/Sources/Features/Editor/RichTextBlockView.swift`

**Checkpoint**: User Stories 1–5 work independently

---

## Phase 8: User Story 6 - Trash and Deletion Lifecycle (Priority: P1)

**Goal**: Delete → Trash → restore or permanently delete; 30-day recovery; empty-note auto-discard but previously-content note never auto-deleted when emptied.

**Independent Test**: Delete a note → Trash → restore; permanently delete another; empty a note's text after it had content → not auto-deleted.

### Tests for User Story 6 (write FIRST, must FAIL) ⚠️

- [X] T076 [P] [US6] Domain test: lifecycle transitions active→trashed→permanentlyDeleted; 30-day expiry; distinguish Trash/permanent/conflictCopy/active in `Packages/StickyCore/Tests/DomainTests/TrashLifecycleTests.swift`
- [X] T077 [P] [US6] Domain test: never-contained-content note auto-discardable on close; previously-content note NOT auto-deleted when text empty in `Packages/StickyCore/Tests/DomainTests/EmptyNoteDiscardTests.swift`
- [X] T078 [US6] Persistence test: Trash expiry scan + retention 30 days in `Packages/StickyCore/Tests/PersistenceTests/TrashExpiryTests.swift`

### Implementation for User Story 6

- [X] T079 [P] [US6] Implement lifecycle state machine + trash/restore/permanent-delete in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift`
- [ ] T080 [US6] Implement Trash UI (list, restore, permanently delete, distinguish states) in `App/Sources/Features/Trash/TrashView.swift`
- [ ] T081 [US6] Implement empty-note auto-discard logic on window close in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift`

**Checkpoint**: All P1 user stories (1–6) work independently → MVP complete

---

## Phase 9: User Story 7 - Screenshot Capture and Clipboard Images (Priority: P2)

**Goal**: Capture region/window into new/existing note; paste clipboard image; view screenshots full-size; select cover. Static only; no live monitoring; no controlling original app.

**Independent Test**: Capture region into new note; add window screenshot to existing note; paste clipboard image; open viewer to zoom/copy/navigate; select cover.

### Tests for User Story 7 (write FIRST, must FAIL) ⚠️

- [X] T082 [P] [US7] AssetStore test: atomic temp-write+rename, SHA-256 hash, verify-before-delete, orphan cleanup, dedup by contentHash in `Packages/StickyCore/Tests/AssetStoreTests/AssetStorageTests.swift`
- [X] T083 [P] [US7] AssetStore test: thumbnail generated async, no original decode in card grid; lossless preferred for text window captures in `Packages/StickyCore/Tests/AssetStoreTests/ThumbnailTests.swift`
- [X] T084 [P] [US7] Domain test: at most one cover screenshot per note (transactional); multiple screenshots allowed in `Packages/StickyCore/Tests/DomainTests/ScreenshotAssociationTests.swift`
- [X] T085 [US7] SystemBridge test: ScreenCaptureKit single-frame capture; cancel cleanly without creating note/asset; no Accessibility prompt for ordinary capture in `Packages/StickyCore/Tests/SystemBridgeTests/CaptureTests.swift`
- [ ] T086 [US7] Integration test: screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate); opening screenshot does not activate original app in `AppTests/ScreenshotIntegrationTests.swift`

### Implementation for User Story 7

- [X] T087 [P] [US7] Implement AssetStore: atomic writes, SHA-256, metadata transactions, cleanup queue, lazy loading, export/drag-out in `Packages/StickyCore/Sources/AssetStore/AssetStore.swift`
- [X] T088 [P] [US7] Implement thumbnail generation + original/thumbnail/appIcon separation in `Packages/StickyCore/Sources/AssetStore/ThumbnailGenerator.swift`
- [X] T089 [US7] Implement ScreenCaptureKit window capture via system content-sharing picker (single static frame, app name/icon/title/time, no retained stream) in `Packages/StickyCore/Sources/SystemBridge/WindowCapture.swift`
- [X] T090 [US7] Implement region capture (single-frame + transparent multi-display selection overlay; Retina/multi-display/rotation/coordinate conversion; clean cancel) in `Packages/StickyCore/Sources/SystemBridge/RegionCapture.swift`
- [ ] T091 [US7] Implement screenshot block view + association metadata + cover selection in `App/Sources/Features/Editor/ScreenshotBlockView.swift`
- [ ] T092 [US7] Implement screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate) in `App/Sources/Features/Capture/ScreenshotViewer.swift`
- [ ] T093 [US7] Implement pasted-image block (embedded original, view/larger/copy/drag-out/save/remove) in `App/Sources/Features/Editor/EmbeddedImageBlockView.swift`

**Checkpoint**: User Stories 1–7 work independently

---

## Phase 10: User Story 8 - Widgets, Global Shortcuts, Dock, and Permissions (Priority: P2)

**Goal**: Add widgets; toggle todos from widget; configure global shortcuts; hide Dock while keeping functions reachable; permissions on-demand only.

**Independent Test**: Add each widget form; mark todo from widget; configure shortcut; disable Dock icon; verify Settings/Help/About/sync/Quit reachable; permission-denied fallbacks.

### Tests for User Story 8 (write FIRST, must FAIL) ⚠️

- [X] T094 [P] [US8] Persistence test: widget reads App Group SQLite in short transactions; todo update atomic; schema-mismatch fallback without crash in `Packages/StickyCore/Tests/PersistenceTests/WidgetAccessTests.swift`
- [X] T095 [P] [US8] Domain test: widget-ineligible note exposes nothing in timelines/previews/placeholders/snapshots/logs in `Packages/StickyCore/Tests/DomainTests/WidgetPrivacyTests.swift`
- [X] T096 [US8] SystemBridge test: global shortcut registers/unregisters, fires while another app focused, detects registration failure, no Accessibility prompt in `Packages/StickyCore/Tests/SystemBridgeTests/GlobalShortcutTests.swift`
- [X] T097 [US8] SystemBridge test: Dock activation-policy switch runtime; Settings/Help/About/sync/Quit remain reachable; widget deep-link does NOT flip Dock policy in `Packages/StickyCore/Tests/SystemBridgeTests/DockActivationTests.swift`
- [ ] T098 [US8] Integration test: permission-denied fallbacks (screen-recording denied → notes usable + explanation + open settings; accessibility denied → only advanced window-id unavailable) in `AppTests/PermissionFallbackIntegrationTests.swift`

### Implementation for User Story 8

- [ ] T099 [P] [US8] Implement WidgetExtension target: WidgetKit + SwiftUI; families per spec (small-selected, small-recent, medium-multi, medium-todo, large-overview, quick-create) in `WidgetExtension/StickyWidgetBundle.swift`
- [ ] T100 [P] [US8] Implement AppIntents (toggle todo by UUID, create note, open note, quick-create action per FR-110) + deep-link routing per contracts/deep-links.md in `WidgetExtension/WidgetIntents.swift` and `App/Sources/App/DeepLinkRouter.swift`
- [ ] T101 [P] [US8] Implement privacy-safe widget placeholders/snapshots + graceful handling of deleted/trashed/conflicted/unavailable configured notes in `WidgetExtension/WidgetSnapshots.swift`
- [X] T102 [US8] Implement global shortcut adapter (native registration, no Accessibility, conflict detection, re-register) in `Packages/StickyCore/Sources/SystemBridge/GlobalShortcuts.swift`
- [X] T103 [US8] Implement Dock activation-policy switching (regular↔accessory runtime, menu-bar access preserved) in `Packages/StickyCore/Sources/SystemBridge/DockActivationBridge.swift`
- [X] T104 [US8] Implement permission service (screen-recording/accessibility status, feature explanation, request action, open-settings, denied recovery) in `Packages/StickyCore/Sources/SystemBridge/PermissionService.swift`
- [ ] T105 [US8] Implement Settings UI (global shortcuts config, Dock toggle, sync status entry, permissions) in `App/Sources/Features/Settings/SettingsView.swift`

**Checkpoint**: User Stories 1–8 work independently

---

## Phase 11: User Story 9 - Optional Encrypted Synchronization (Priority: P3)

**Goal**: Configure one WebDAV/S3 repo + sync password; notes replicate E2E-encrypted; provider cannot read content/metadata; local editing never waits.

**Independent Test**: Configure one repo → trigger manual sync → edit offline → reconnect → changes appear on another Mac; provider cannot read content.

### Tests for User Story 9 (write FIRST, must FAIL) ⚠️

- [X] T106 [P] [US9] SecurityCore test: encryption test vectors (correct/wrong password, modified ciphertext/nonce/AAD, wrong object ID/type/vault, unsupported version, password re-wrap, Keychain unavailable, corrupt bootstrap) in `Packages/StickyCore/Tests/SecurityCoreTests/EncryptionVectorTests.swift`
- [X] T107 [P] [US9] Provider contract test: shared suite both WebDAV + S3 pass (Put/Get/Head/conditional create/replace/failure/delete/missing/auth/server/timeout/cancellation/retry classification) in `Packages/StickyCore/Tests/SyncCoreTests/ProviderContractTests.swift`
- [X] T108 [P] [US9] SyncCore test: initial upload/download, incremental update, partial asset upload, interrupted manifest commit, repeated retry, wrong password, remote corruption, network loss/restoration in `Packages/StickyCore/Tests/SyncCoreTests/SyncEngineTests.swift`
- [X] T109 [US9] SyncCore test: no credentials/secrets, note content, file names/paths, window titles, screenshot captions, or todo text appear in logs or exported diagnostics (covers full FR-191 + SC-010 redaction scope) in `Packages/StickyCore/Tests/SyncCoreTests/DiagnosticsPrivacyTests.swift`
- [X] T110 [US9] Domain test: remote object names opaque/random; no semantic type in filenames; manifest carries only opaque names+sizes/times in `Packages/StickyCore/Tests/DomainTests/RemoteLayoutTests.swift`

### Implementation for User Story 9

- [X] T111 [P] [US9] Implement SecurityCore: Argon2id KEK, random master key, HKDF object keys, AES-GCM envelopes, Keychain access, secure random, fail-closed per contracts/vault-bootstrap.schema.json + encrypted-envelope.schema.json in `Packages/StickyCore/Sources/SecurityCore/`
- [X] T112 [P] [US9] Implement vault bootstrap + onboarding (enable sync, join vault, wrong password, another-vault repo, create empty vault, upload existing notes, password change re-wrap) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift`
- [X] T113 [P] [US9] Implement provider-neutral repository protocol per contracts/provider-protocol.md in `Packages/StickyCore/Sources/SyncCore/ProviderProtocol.swift`
- [X] T114 [P] [US9] Implement WebDAV adapter over URLSession (PROPFIND/MKCOL/GET/PUT/HEAD/DELETE, ETag/If-Match/If-None-Match, XML multistatus, HTTPS-only, self-signed pinning) in `Packages/StickyCore/Sources/SyncCore/WebDAVProvider.swift` — implemented + unit-tested (`AdapterTests`: WebDAV multistatus XML parsing, conditional create/replace semantics). Real-service compatibility is T139 (opt-in credentialed).
- [X] T115 [P] [US9] Implement S3 SigV4 adapter over URLSession (configurable endpoint, path-style/virtual-host, compatibility: AWS/R2/MinIO/B2) in `Packages/StickyCore/Sources/SyncCore/S3Provider.swift` — implemented + unit-tested (`AdapterTests`: SigV4 AWS-documented test vector cross-verified against Python `hmac`; `sigV4SignsPutWithPayloadHash`). Real-service compatibility is T139 (opt-in credentialed).
- [X] T116 [P] [US9] Implement normalized provider errors per contracts/provider-errors.md (fail-closed categories) in `Packages/StickyCore/Sources/SyncCore/ProviderErrors.swift`
- [X] T117 [US9] Implement single-vault SyncActor (one transaction per vault; triggers 2-4s debounce FR-152a/15min/startup/network-restore/manual/termination; idempotent steps; exponential backoff+jitter; conditional manifest commit) in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift`
- [X] T118 [US9] Implement remote manifest handling + conditional replace + retry-on-precondition-failure per contracts/encrypted-manifest.schema.json in `Packages/StickyCore/Sources/SyncCore/ManifestStore.swift`
- [ ] T119 [US9] Implement sync settings UI (configure/test/enable-disable/manual/last-success/errors/remove-without-deleting-local) + unrecoverable-password warning (FR-163) in `App/Sources/Features/Settings/SyncSettingsView.swift`
- [ ] T120 [US9] Implement sync status + non-blocking diagnostics in menu-bar library in `App/Sources/Features/Library/SyncStatusView.swift`

**Checkpoint**: User Stories 1–9 work independently

---

## Phase 12: User Story 10 - Synchronization Conflicts and Remote Deletion (Priority: P3)

**Goal**: Two Macs diverge → original + labeled conflict copy; delete-vs-edit → recovered conflict copy; deletions propagate safely with 30-day tombstone.

**Independent Test**: Edit same note on two offline Macs → sync → both versions survive as original + conflict copy; delete on one while edit offline on other → edited content survives as recovered conflict copy.

### Tests for User Story 10 (write FIRST, must FAIL) ⚠️

- [ ] T121 [P] [US10] SyncCore test: simultaneous edit → conflict copy; conflict deduplication (retry does not create unbounded duplicates) in `Packages/StickyCore/Tests/SyncCoreTests/ConflictCopyTests.swift`
- [ ] T122 [P] [US10] SyncCore test: delete-vs-edit → recovered conflict copy; not lost, not resurrected in `Packages/StickyCore/Tests/SyncCoreTests/DeleteEditConflictTests.swift`
- [ ] T123 [P] [US10] SyncCore test: tombstone lifecycle (offline <30d, >30d, device returning after remote cleanup, unknown devices, manual Trash empty) in `Packages/StickyCore/Tests/SyncCoreTests/TombstoneTests.swift`
- [ ] T124 [P] [US10] SyncCore test: long-offline device reconciles deletion history before uploading locally-deleted notes; not wall-clock last-modified-wins in `Packages/StickyCore/Tests/SyncCoreTests/LongOfflineTests.swift`
- [ ] T125 [US10] Domain test: distinguish Trash/permanent-deleted/recovered-conflict-copy/active in `Packages/StickyCore/Tests/DomainTests/NoteDistinguishabilityTests.swift`

### Implementation for User Story 10

- [ ] T126 [P] [US10] Implement note-level conflict model + deterministic dedup key `(originalNoteId, localVersionId, remoteVersionId)` per plan.md §Conflict model in `Packages/StickyCore/Sources/SyncCore/ConflictResolver.swift`
- [ ] T127 [P] [US10] Implement conflict-copy creation (new note UUID, label, preserve all blocks/assets/file-ref metadata, asset ref-count/dup, sync normally) in `Packages/StickyCore/Sources/SyncCore/ConflictCopyBuilder.swift`
- [ ] T128 [P] [US10] Implement tombstone store + 30-day sync-safety-gated retention per contracts/tombstone.schema.json + data-model.md §Tombstone lifecycle in `Packages/StickyCore/Sources/Persistence/Repositories/TombstoneRepository.swift`
- [ ] T129 [US10] Implement long-offline reconciliation (reconcile remote deletion history before upload; conservative unknown-remote handling) in `Packages/StickyCore/Sources/SyncCore/OfflineReconciler.swift`
- [ ] T130 [US10] Implement conflict-copy labeling + distinguishability UI in library/Trash in `App/Sources/Features/Library/ConflictCopyView.swift`

**Checkpoint**: All user stories (1–10) work independently

---

## Phase 13: Polish & Cross-Cutting Concerns

**Purpose**: Accessibility, localization, performance validation, documentation, release readiness (Milestone 4).

- [ ] T131 [P] Accessibility: VoiceOver labels/actions + keyboard navigation + focus order + keyboard alternatives for hover controls + block/todo keyboard reorder/indent in `App/Sources/Features/Editor/Accessibility.swift`
- [ ] T132 [P] Accessibility: announcements for todo-state changes + failed file access + failed capture; Increased Contrast + Reduce Motion + dynamic readable foreground in `App/Sources/Features/NoteWindow/AccessibilityAdaptations.swift`
- [ ] T133 [P] Localization: locale-aware date/file-size formatters; language-neutral persisted enums/sync schemas; no localized strings as protocol identifiers in `App/Sources/Features/Shared/Formatters.swift`
- [ ] T134 [P] Performance: lazy card-grid projections + bounded result loading + lazy thumbnail decode + signposts on measurable paths in `Packages/StickyCore/Sources/Persistence/CardProjection.swift` and `App/Sources/Features/Library/NoteCardView.swift`
- [ ] T135 Performance tests: warm menu-bar presentation (SC-001), initial card load (SC-002), note-window creation (SC-003), typing latency incl. Chinese IME composition (SC-004/SC-004a), search 10k (SC-005/FR-024a), idle CPU (SC-006), offline no-degradation vs online (SC-007), no full-resolution decode in card grid (SC-008), save latency, thumbnail decode, sync pass, large-asset encryption, card-browsing memory, end-to-end capture loop <30s (SC-011) in `Packages/StickyCore/Tests/PersistenceTests/PerformanceBaselineTests.swift`
- [ ] T135a [P] Independence gate test: verify SC-009 — run all P1 acceptance scenarios (US1-US6) with sync disabled, no widgets configured, no screenshots captured, no screen-recording permission granted; assert each P1 story is independently demonstrable without any P2/P3 feature configured in `AppTests/P1IndependenceGateTests.swift` per SC-009 / Constitution XIV
- [ ] T136 [P] Documentation: architecture docs, privacy document (constitution VI), security policy, protocol docs, license compliance in `Documentation/`
- [ ] T137 [P] Release: Developer ID signing + notarization workflow + GitHub release workflow; secrets in GitHub encrypted secrets only, never in repo files or fork PR workflows in `.github/workflows/release.yml`
- [ ] T138 [P] Regression tests for fixed defects accumulated across stories in `AppTests/RegressionTests.swift`
- [ ] T139 [P] Real-service compatibility tests (opt-in, credentialed): standards-compliant WebDAV, MinIO, one hosted S3-compatible, AWS S3 — never commit credentials per quickstart.md in `Packages/StickyCore/Tests/SyncCoreTests/RealServiceCompatibilityTests.swift`
- [ ] T141 [US1] [US6] XCUITest critical UI journeys: menu-bar open/dismiss/re-click (FR-009); note create/open/focus-existing-not-duplicate/close (FR-005/FR-006); Trash restore + permanent delete (FR-014); screenshot viewer open does not activate original app (FR-095) in `AppUITests/CriticalFlowsUITests.swift` per constitution XII
- [ ] T142 [P] [US3] Implement global font preference (Chinese + English with fallback) in Settings + Domain `FontPreference` model per FR-043 in `Packages/StickyCore/Sources/Domain/Models/FontPreference.swift` and `App/Sources/Features/Settings/FontPreferenceView.swift`
- [ ] T143 [P] [US1] [US5] Implement auto-link detection (web URLs, email addresses, telephone numbers) feeding canonical rich-text `link` mark per FR-050 in `Packages/StickyCore/Sources/EditorCore/AutoLinkDetector.swift`
- [ ] T144 [P] [US8] Implement About panel reachable from menu-bar interface (covers FR-008 About reachability when Dock disabled) in `App/Sources/Features/About/AboutView.swift`
- [ ] T145 [US8] Implement "new note from clipboard" global-shortcut handler (FR-120) reusing pasted-image logic in `Packages/StickyCore/Sources/SystemBridge/GlobalShortcuts.swift` and `App/Sources/App/DeepLinkRouter.swift`
- [ ] T146 [P] [US3] Configure `NSWindow.collectionBehavior` so note windows do not appear across every Space and do not force over full-screen applications (FR-035) in `Packages/StickyCore/Sources/SystemBridge/NoteWindowBridge.swift`
- [ ] T147 [P] [US3] Domain test: FontPreference persistence + Chinese/English fallback selection for unsupported glyphs per FR-043 in `Packages/StickyCore/Tests/DomainTests/FontPreferenceTests.swift`
- [ ] T148 [P] [US1] [US5] EditorCore test: auto-link detection recognizes web URLs, email addresses, telephone numbers; emits canonical rich-text `link` mark; no false positives inside code blocks per FR-050 in `Packages/StickyCore/Tests/EditorCoreTests/AutoLinkDetectorTests.swift`
- [ ] T149 [US8] Integration test: About panel reachable from menu-bar interface with Dock disabled (FR-008) in `AppTests/AboutReachabilityIntegrationTests.swift`
- [ ] T150 [US8] SystemBridge test: "new note from clipboard" global shortcut fires while another app is focused and creates a note with clipboard contents (FR-120) in `Packages/StickyCore/Tests/SystemBridgeTests/ClipboardNoteShortcutTests.swift`
- [ ] T151 [US3] SystemBridge test: note window `collectionBehavior` prevents appearance across every Space and prevents forcing over full-screen applications (FR-035) in `Packages/StickyCore/Tests/SystemBridgeTests/WindowSpaceBehaviorTests.swift`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **User Stories (Phase 3–12)**: All depend on Foundational completion.
  - P1 stories (US1–US6) can proceed in priority order or parallel (if staffed).
  - P2 stories (US7–US8) depend on Foundational + relevant P1 surface (US7 reuses AssetStore + note windows; US8 reuses Domain/Persistence + note windows).
  - P3 stories (US9–US10) depend on Foundational + Domain canonical types; US10 depends on US9 sync engine.
- **Milestone 0 Prototypes (Phase 2.5)**: HARD GATE after Foundational, before ANY user story — prototypes validate high-risk assumptions per plan.md §Milestone 0.
- **Polish (Phase 13)**: Depends on all desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational — no dependencies on other stories. **MVP**.
- **US2 (P1)**: After Foundational — may reuse US1 Note/Card views but independently testable.
- **US3 (P1)**: After Foundational — independent (note windows).
- **US4 (P1)**: After Foundational — independent (todos/code/file-refs).
- **US5 (P1)**: After Foundational — depends on US1 rich-text block view (RichTextAdapter).
- **US6 (P1)**: After Foundational — may reuse US1 lifecycle fields but independently testable.
- **US7 (P2)**: After Foundational + US1 (note windows/blocks) — reuses AssetStore.
- **US8 (P2)**: After Foundational + US1 (note open/deep-link) — reuses Domain/Persistence.
- **US9 (P3)**: After Foundational + Domain canonical types — independent of UI stories.
- **US10 (P3)**: After US9 (sync engine) — conflict/tombstone built on sync.

### Within Each User Story

- Tests written FIRST and must FAIL before implementation (constitution Principle XII).
- Models/domain before services; services before UI; core before integration.
- Story complete (and checkpoint reached) before moving to next priority.

### Parallel Opportunities

- All Phase 1 `[P]` setup tasks (different files) run in parallel.
- All Phase 2 `[P]` foundational domain/model/protocol tasks run in parallel.
- Within a story, all `[P]` test tasks run in parallel; `[P]` models run in parallel.
- Different user stories can be worked in parallel by different contributors once Foundational completes (mind US5→US1, US7→US1, US8→US1, US10→US9 couplings).
- Across stories, `[P]` tasks touching distinct modules (e.g., US9 SecurityCore/SyncCore vs US7 AssetStore) run in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories).
3. Complete Phase 2.5: Milestone 0 prototypes (hard risk gate per plan.md §Milestone 0).
4. Complete Phase 3: User Story 1 (capture/edit/reopen/no-save/one-window).
5. **STOP and VALIDATE**: Test User Story 1 independently — MVP delivered.

### Incremental Delivery

1. Setup + Foundational → Foundation ready.
2. Milestone 0 prototypes (Phase 2.5) → de-risk high-assumption areas.
3. Add US1 → Test → MVP.
4. Add US2–US6 (P1) → each tested independently → full local core (Milestone 1).
5. Add US7–US8 (P2) → system integration (Milestone 2).
6. Add US9–US10 (P3) → encrypted sync (Milestone 3).
7. Polish + release (Milestone 4).

### Parallel Team Strategy

With multiple contributors:

1. Team completes Setup + Foundational together.
2. Once Foundational done, assign stories by priority and coupling:
   - Contributor A: US1 → US5 (rich-text coupling).
   - Contributor B: US2 + US6 (lifecycle/search).
   - Contributor C: US3 + US4 (windows/todos/code/file-refs).
   - Contributor D: US7 (assets/capture) once US1 lands.
   - Contributor E: US8 (widgets/shortcuts/permissions) once US1 lands.
   - Contributor F: US9 → US10 (sync) — independent of UI stories, can start after Foundational.

---

## Notes

- `[P]` tasks = different files, no dependencies on incomplete tasks.
- `[Story]` label maps task to a user story for traceability to spec.md.
- Every story has tests written FIRST (constitution Principle XII; tests mandatory for this project, not optional).
- File paths reference the plan.md §Project Structure layout (App/, WidgetExtension/, Packages/StickyCore/Sources|Tests/).
- Verify each checkpoint before moving on; stop at any checkpoint to validate a story independently.
- Avoid: vague tasks, same-file conflicts, cross-story dependencies that break independence.
- Milestone 0 prototypes (T025a) validate high-risk assumptions per research.md R0–R18 before broad feature work depends on them.

---

## Phase 14: Convergence

- [X] T152 Enforce `Note.coverScreenshotBlockId → Block.id` foreign key in v1 schema per data-model.md:277 (partial) — the FK was dropped from `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` because GRDB's column-level `references("block")` queries the destination table's PK at CREATE time and `block` is created after `note` (circular dependency). Fix by either (a) creating the `note` table via raw SQL with `REFERENCES "block"("id") ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED` (verified to work — SQLite defers the FK target existence check), or (b) reordering table creation so `block` is created before `note` and the `block.noteId → note` FK is added via a subsequent table recreation. Add a migration test asserting the FK exists in `sqlite_master` and that deleting a cover screenshot block nulls `note.coverScreenshotBlockId`.
- [X] T153 Add migration-recovery tests covering `StickyMigrator` pre-migration backup creation, restore-on-migration-failure, `MigrationRecovery.recoverFromInterruptedMigration` (missing DB / corrupt DB / intact DB no-op / backup consumed after restore), and `currentSchemaVersion` fallback, in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift` per T022 and plan §Local storage (partial) — the recovery machinery in `Packages/StickyCore/Sources/Persistence/Migrations/Migrator.swift` is implemented but has zero test coverage and no call sites (Constitution XII mandates database migration tests; `MigrationTests.swift:21` claims "Interrupted-migration recovery restores the backup" but no such test exists)
- [X] T154 Wire `StickyMigrator` + `MigrationRecovery.recoverFromInterruptedMigration` into app startup so the migration framework is actually used (pre-migration backup + interrupted-migration recovery at launch) per plan §Local storage (partial) — currently only `InitialSchema.migrator()` is exercised by tests; `StickyMigrator`/`MigrationRecovery` are unreferenced outside `m0001_initial.swift` comments
- [X] T155 Complete the Milestone 0 prototype hard gate (T025a): build SwiftUI rich-text + Chinese IME, Markdown single-Undo, one-window-per-note, per-window floating, App Group GRDB widget access, ScreenCaptureKit single-frame, native global shortcut prototypes in `Prototypes/` (currently empty) and confirm feasibility per plan §Milestone 0 (contradicts) — user-story implementation tasks (T030, T031, T061, T073, T074) were marked complete while the hard gate remains unmet; gate must be satisfied and verified before further user-story implementation proceeds
- [X] T156 Review or justify `Packages/StickyCore/Sources/Persistence/TempDatabasePaths.swift` (unrequested) — a test-support temp-path registry not called for by any task; retain only if justified as CI test hygiene (used by `DatabaseStore.inMemory()`), otherwise remove
- [X] T157 Fix the stale FTS5 comment in `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` (contradicts) — the comment claims `synchronize(withTable:)` is NOT used and references "triggers below", but line 289 does use `t.synchronize(withTable: "note_fts_content")` and no triggers are defined in the migration; align the comment with the actual implementation
- [ ] T158 Interactive verification of Milestone 0 GUI prototypes (T025a gate remainder) — run `RichTextIMEPrototype` (Chinese IME typing + canonical NFC round-trip), `WindowCoordinatorPrototype` (one-window-per-note focus + per-window floating level), and `ScreenCapturePrototype` (region-drag capture + permission-on-invocation) on a Mac with a display under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run …` per `Prototypes/README.md`. Each prototype prints its own PASS/FAIL at the end of the interactive session. Record results in `Prototypes/README.md` and flip T025a's partial note to fully verified. This is the explicit gate for the GUI portion of T025a that could not be verified by headless compilation alone.

---

## Phase 15: Convergence

> **Note**: Tasks T159-T172 supersede and consolidate the corresponding
> Phase 3-12 tasks (T032-T119) that remain `[ ]`. The Phase 3-12 originals
> are retained for historical traceability; the convergence tasks are
> authoritative and should be executed in their place.

- [ ] T159 Implement SwiftUI `MenuBarLibraryScene.swift` (search/sort/new/Trash/sync-status/Settings/Help/Quit affordances) + FR-009 re-click behavior (focus if not focused, dismiss if focused, never second window) per FR-001/FR-003/FR-004/FR-009/US1/AC1,AC6 in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (missing) — `App/Sources/Features/Library/` is empty; `StickyNotesApp.swift:40-58` ships only a stub `MenuBarExtra` with "setup in progress" text
- [ ] T160 Implement `NoteWindowCoordinator.swift` (open by UUID, one window per note, focus existing not duplicate, flush pending edits before close, no reopen after relaunch) + `NoteWindowBridge.swift` (AppKit NSWindow registration/focus/level isolated in SystemBridge) per FR-005/FR-006/FR-007/US1/AC2-5 in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` and `Packages/StickyCore/Sources/SystemBridge/NoteWindowBridge.swift` (missing) — `App/Sources/Features/NoteWindow/` is empty; `StickyNotesApp.swift:64` defers this to T034 but it was never done; new-note-window focus per FR-007a (new note window immediately receives keyboard focus; library stays open without focus; global-shortcut creation activates the app)
- [ ] T161 Implement `RichTextBlockView.swift` (SwiftUI `TextEditor` + `AttributedString` rich-text block) + `RichTextAdapter.swift` (SwiftUI attributed ↔ canonical ↔ plain text, IME-safe Markdown transform wiring) per FR-050/FR-051/FR-052/FR-053/FR-060/FR-061/FR-062/FR-063/US1/AC3/US5 in `App/Sources/Features/Editor/RichTextBlockView.swift` and `Packages/StickyCore/Sources/EditorCore/RichTextAdapter.swift` (missing) — `App/Sources/Features/Editor/` is empty; EditorCore has Markdown/AutoSave/EditorCommands but no adapter connecting SwiftUI attributed state to the canonical rich-text model
- [ ] T162 Implement `NoteCardView.swift` (compact card-grid card: manual title / generated summary, short body preview, note color, last-modified, todo progress, screenshot/image/file-ref indicators, conflict/sync warning) per FR-002/FR-002a/FR-020/FR-021/US1/US2 in `App/Sources/Features/Library/NoteCardView.swift` (missing) — `App/Sources/Features/Library/` is empty; card-grid library surface absent
- [ ] T163a [P] [US1] Create `AppTests/NoteCaptureIntegrationTests.swift` per T029 — App-level integration test: create note → close without save → reopen → content preserved; one window per note, focus not duplicate; new note window receives keyboard focus immediately, library stays open without focus (FR-007a) per Constitution XII
- [ ] T163b [P] [US2] Create `AppTests/RetrievalIntegrationTests.swift` per T041 — Integration test: sort switch (modified/created/title/manual) + manual reorder persists per Constitution XII
- [ ] T163c [P] [US3] Create `Packages/StickyCore/Tests/SystemBridgeTests/WindowFrameCorrectionTests.swift` per T048 — SystemBridge test: window-frame correction moves off-screen window to visible display + preserves disconnected-display preferred frame per Constitution XII
- [ ] T163d [P] [US3] Create `AppTests/AppearanceIntegrationTests.swift` per T049 — Integration test: Always-on-Top per note; contrast readable across light/dark/custom-color/transparency/increased-contrast per Constitution XII
- [ ] T163e [P] [US4] Create `Packages/StickyCore/Tests/SystemBridgeTests/FileReferenceAccessTests.swift` per T059 — SystemBridge test: drag-out copies without deleting; explicit move requires command+destination+confirmation+verify; missing file preserves card + relink; no filesystem scan per Constitution XII
- [ ] T163f [P] [US4] Create `AppTests/TodoCodeFileRefIntegrationTests.swift` per T060 — Integration test: todo complete state communicated by more than color alone (strikethrough) per Constitution XII
- [ ] T163g [P] [US7] Create `AppTests/ScreenshotIntegrationTests.swift` per T086 — Integration test: screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate); opening screenshot does not activate original app per Constitution XII
- [ ] T163h [P] [US8] Create `AppTests/PermissionFallbackIntegrationTests.swift` per T098 — Integration test: permission-denied fallbacks (screen-recording denied → notes usable + explanation + open settings; accessibility denied → only advanced window-id unavailable) per Constitution XII
- [ ] T163i [P] Create `AppTests/RegressionTests.swift` per T138 — Regression tests for fixed defects accumulated across stories per Constitution XII
- [ ] T163j [P] Create `AppUITests/CriticalFlowsUITests.swift` per T141 — XCUITest critical UI journeys: menu-bar open/dismiss/re-click (FR-009); note create/open/focus-existing-not-duplicate/close (FR-005/FR-006); Trash restore + permanent delete (FR-014); screenshot viewer open does not activate original app (FR-095) per Constitution XII
- [ ] T163k [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/ConflictCopyTests.swift` per T121 — SyncCore test: simultaneous edit → conflict copy; conflict deduplication (retry does not create unbounded duplicates) per Constitution XII
- [ ] T163l [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/DeleteEditConflictTests.swift` per T122 — SyncCore test: delete-vs-edit → recovered conflict copy; not lost, not resurrected per Constitution XII
- [ ] T163m [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/TombstoneTests.swift` per T123 — SyncCore test: tombstone lifecycle (offline <30d, >30d, device returning after remote cleanup, unknown devices, manual Trash empty) per Constitution XII
- [ ] T163n [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/LongOfflineTests.swift` per T124 — SyncCore test: long-offline device reconciles deletion history before uploading locally-deleted notes; not wall-clock last-modified-wins per Constitution XII
- [ ] T163o [P] [US10] Create `Packages/StickyCore/Tests/DomainTests/NoteDistinguishabilityTests.swift` per T125 — Domain test: distinguish Trash/permanent-deleted/recovered-conflict-copy/active per Constitution XII
- [ ] T163p [P] Create `Packages/StickyCore/Tests/PersistenceTests/PerformanceBaselineTests.swift` per T135 — Performance tests: SC-001-SC-008, SC-011 per Constitution XII
- [ ] T163q [P] Create `Packages/StickyCore/Tests/DomainTests/FontPreferenceTests.swift` per T147 — Domain test: FontPreference persistence + Chinese/English fallback selection per FR-043 per Constitution XII
- [ ] T163r [P] Create `Packages/StickyCore/Tests/EditorCoreTests/AutoLinkDetectorTests.swift` per T148 — EditorCore test: auto-link detection recognizes web URLs, email addresses, telephone numbers; emits canonical rich-text `link` mark; no false positives inside code blocks per FR-050 per Constitution XII
- [ ] T164 Implement `LibrarySearchView.swift` (search field + sort switcher among Recently Modified/Created/Title/Manual with prompt result updates) per FR-022/FR-022a/FR-023/FR-023a/FR-024/FR-024a/US2/AC1,AC2 in `App/Sources/Features/Library/LibrarySearchView.swift` (missing) — `App/Sources/Features/Library/` is empty; SearchService exists in Persistence but no UI consumes it
- [ ] T165 Implement `NoteControlsView.swift` (upper control area: title/color/transparency/textSize/Always-on-Top/screenshot/file-ref/actions/close, hidden until pointer enter) + `WindowLevelBridge.swift` (per-window floating level via AppKit) + `DisplayChangeBridge.swift` (display connect/disconnect handling + frame restoration + fallback frame preserving disconnected-display preferred frame) + `ReadableTheme.swift` (dynamic readable foreground colors + contrast adaptation, reject/adjust custom colors failing contrast) per FR-030/FR-030a/FR-031/FR-032/FR-033/FR-034/FR-035/FR-042/FR-044/US3 in `App/Sources/Features/NoteWindow/{NoteControlsView,ReadableTheme}.swift` and `Packages/StickyCore/Sources/SystemBridge/{WindowLevelBridge,DisplayChangeBridge}.swift` (missing) — `App/Sources/Features/NoteWindow/` is empty; SystemBridge has no window-level/display-change bridges
- [ ] T166 Implement `TodoBlockView.swift` (complete/incomplete with strikethrough beyond color alone, drag reorder, indent/outdent, edit, delete) + `CodeBlockView.swift` (monospaced, preserved whitespace, copy button copying only code, optional language label, wrap-or-scroll) + `FileReferenceCardView.swift` (name/icon/size/date/availability/origin device + open/reveal/copy-path/drag-out/move/relink/remove) + `SecurityScopedBookmarks.swift` (balanced start/stop security-scoped access + availability status + relink) + `FileDragOutBridge.swift` (drag-out copies never move/delete + explicit move with destination picker + confirmation + verify-before-replace-bookmark) per FR-070/FR-072a/FR-080/FR-081/FR-082/FR-100/FR-101/FR-102/FR-103/FR-104/FR-105/US4 in `App/Sources/Features/Editor/{TodoBlockView,CodeBlockView,FileReferenceCardView}.swift` and `Packages/StickyCore/Sources/SystemBridge/{SecurityScopedBookmarks,FileDragOutBridge}.swift` (missing) — `App/Sources/Features/Editor/` is empty; SystemBridge has no security-scoped bookmark or drag-out bridge
- [ ] T167 Implement `TrashView.swift` (list Trash, restore, permanently delete, distinguish Trash/permanent-deleted/recovered-conflict-copy/active states) + wire empty-note auto-discard logic on window close in `NoteWindowCoordinator` (a never-contained-meaningful-content note MAY be auto-removed; a previously-content note MUST NOT be auto-deleted when text becomes empty) per FR-014/FR-014a/FR-175/US6/AC3,AC4,AC5 in `App/Sources/Features/Trash/TrashView.swift` and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` (missing) — `App/Sources/Features/Trash/` is empty; NoteWindowCoordinator (T160) does not yet exist to host the auto-discard hook (lifecycle operations per FR-011)
- [ ] T168 Implement `ScreenshotBlockView.swift` (screenshot association metadata + cover selection, at most one cover per note transactional) + `ScreenshotViewer.swift` (zoom/actual-size/fit-to-window/copy/drag-out/Save-As/delete-association/edit-caption/navigate between screenshots of same note; viewer MUST NOT auto-start/switch/control original app) + `EmbeddedImageBlockView.swift` (embedded clipboard image original: view/larger/copy/drag-out/save-elsewhere/remove) per FR-090/FR-090a/FR-091/FR-092/FR-093/FR-094/FR-094a/FR-095/FR-096/US7 in `App/Sources/Features/Editor/{ScreenshotBlockView,EmbeddedImageBlockView}.swift` and `App/Sources/Features/Capture/ScreenshotViewer.swift` (missing) — `App/Sources/Features/Editor/` and `App/Sources/Features/Capture/` are empty
- [ ] T169 Implement WidgetExtension target sources: `StickyWidgetBundle.swift` (WidgetKit + SwiftUI; families per spec: small-selected, small-recent, medium-multi, medium-todo, large-overview, quick-create action) + `WidgetIntents.swift` (AppIntents: toggle todo by UUID, create note, open note, quick-create per FR-110) + `WidgetSnapshots.swift` (privacy-safe placeholders/snapshots + graceful handling of deleted/trashed/conflicted/unavailable configured notes) + `DeepLinkRouter.swift` in App (URL routing `stickynotes://note/<uuid>`, `stickynotes://new`, `stickynotes://search` per contracts/deep-links.md) + `SettingsView.swift` (global shortcuts config, Dock toggle, sync status entry, permissions) per FR-110/FR-111/FR-112/FR-120/FR-121/FR-130/FR-131/FR-132/FR-133/FR-134/US8 in `WidgetExtension/{StickyWidgetBundle,WidgetIntents,WidgetSnapshots}.swift` and `App/Sources/App/DeepLinkRouter.swift` and `App/Sources/Features/Settings/SettingsView.swift` (missing) — `WidgetExtension/` has only Info.plist + entitlements; `App/Sources/Features/Settings/` is empty
- [ ] T170 Implement `SyncSettingsView.swift` (configure/test/enable-disable automatic/manual sync/view last-successful-time/view actionable errors/remove local config without deleting local notes + clear unrecoverable-password warning per FR-163) + `SyncStatusView.swift` (non-blocking sync status + sanitized diagnostics in menu-bar library; credentials/unlocked secrets never in logs or exported diagnostics per FR-165) per FR-150/FR-151/FR-152/FR-152a/FR-153/FR-154/FR-160/FR-162/FR-163/FR-164/FR-165/US9/AC1,AC4 in `App/Sources/Features/Settings/SyncSettingsView.swift` and `App/Sources/Features/Library/SyncStatusView.swift` (missing) — `App/Sources/Features/Settings/` and `App/Sources/Features/Library/` are empty; SyncEngine exists in SyncCore but no UI consumes it
- [ ] T171 Implement `ConflictResolver.swift` (note-level conflict model + deterministic dedup key `(originalNoteId, localVersionId, remoteVersionId)` so retry does not create unbounded duplicates; NO automatic character/block merging) + `ConflictCopyBuilder.swift` (create new note UUID for divergent version, label with origin/time, preserve text/todos/code/images/screenshots/file-reference metadata, asset ref-count/dup, sync normally) + `TombstoneRepository.swift` (tombstone store + 30-day sync-safety-gated retention per contracts/tombstone.schema.json) + `OfflineReconciler.swift` (long-offline device reconciles remote deletion history before uploading locally-deleted notes; conservative unknown-remote handling; not wall-clock last-modified-wins) + `ConflictCopyView.swift` (conflict-copy labeling + distinguishability in library/Trash) per FR-170/FR-171/FR-172/FR-173/FR-174/FR-175/US10 in `Packages/StickyCore/Sources/SyncCore/{ConflictResolver,ConflictCopyBuilder,OfflineReconciler}.swift`, `Packages/StickyCore/Sources/Persistence/Repositories/TombstoneRepository.swift`, and `App/Sources/Features/Library/ConflictCopyView.swift` (missing) — none of these files exist; US10 implementation is entirely absent
- [ ] T172 Implement Phase 13 polish & cross-cutting tasks: `Accessibility.swift` (VoiceOver labels/actions, keyboard navigation, focus order, keyboard alternatives for hover controls, block/todo keyboard reorder/indent) + `AccessibilityAdaptations.swift` (announcements for todo-state changes/failed file access/failed capture; Increased Contrast + Reduce Motion + dynamic readable foreground) + `Formatters.swift` (locale-aware date/file-size formatters; language-neutral persisted enums/sync schemas) + `CardProjection.swift` (lazy card-grid projections + bounded result loading in Persistence) + lazy thumbnail decode + signposts on measurable paths in `NoteCardView.swift` + `AboutView.swift` (About panel reachable from menu-bar interface, covers FR-008 when Dock disabled) + `FontPreference.swift` Domain model + `FontPreferenceView.swift` (global font preference Chinese+English with fallback per FR-043) + `AutoLinkDetector.swift` (auto-link detection for web URLs/email/telephone feeding canonical rich-text `link` mark per FR-050) + `.github/workflows/release.yml` (Developer ID signing + notarization + GitHub release workflow; secrets in GitHub encrypted secrets only) per FR-008/FR-043/FR-050/FR-051/FR-052/FR-052a/FR-053/FR-061/FR-062/FR-180/FR-181/FR-182/SC-001-SC-011/Constitution VI/XII in `App/Sources/Features/{Editor/Accessibility,NoteWindow/AccessibilityAdaptations,Shared/Formatters,About/AboutView,Settings/FontPreferenceView}.swift`, `Packages/StickyCore/Sources/{Persistence/CardProjection,Domain/Models/FontPreference,EditorCore/AutoLinkDetector}.swift`, and `.github/workflows/release.yml` (missing) — `App/Sources/Features/{About,Shared,Editor,NoteWindow}/` are empty; CardProjection/FontPreference/AutoLinkDetector absent; release workflow absent
- [X] T173 Reconciled: T001 updated to reflect `project.yml` as source of truth; `StickyNotes.xcodeproj` generated at build time; CI bootstrap and quickstart.md updated per FR-008/US1/plan §Project Structure in `project.yml` + `.github/workflows/ci.yml` + `specs/001-sticky-notes-app/quickstart.md`
- [ ] T174 Reconcile T025a/T158 status: T025a is marked `[X]` (partial — headless prototypes PASS, GUI prototypes compile but unverified) while T158 (the explicit interactive GUI verification gate) remains `[ ]`. Either (a) complete T158 and flip T025a's partial note to fully verified in `Prototypes/README.md`, or (b) document why the GUI portion is deferred and update T025a's status to reflect the deferral rather than implying completion per Constitution XII/plan §Milestone 0 in `Prototypes/README.md` and `specs/001-sticky-notes-app/tasks.md` (partial) — task status is internally inconsistent: T025a implies the gate is met (with a partial caveat) while the dedicated verification task T158 is still open
- [ ] T175 Reconcile SystemBridge test task→file traceability: T096 (`GlobalShortcutTests.swift`) and T097 (`DockActivationTests.swift`) are marked `[X]` but no files with those names exist in `Packages/StickyCore/Tests/SystemBridgeTests/` (only `CaptureTests.swift` + `ShortcutDockTests.swift` present). Either (a) split `ShortcutDockTests.swift` into the named files matching T096/T097, or (b) update T096/T097 file paths to point at `ShortcutDockTests.swift` and note the consolidation per Constitution XII/plan §Testing in `Packages/StickyCore/Tests/SystemBridgeTests/` (partial) — task→file traceability is broken; coverage may be present under a different filename

---

## Phase 16: Convergence — 2026-08-07 Clarification Propagation

**Purpose**: Propagate the five requirements clarified in the 2026-08-07
`/speckit-clarify` session (FR-154 repository replacement, FR-162a remember-
unlock lifetime, FR-174 long-offline tombstone purge, FR-191 diagnostic-bundle
content boundary, wrong-vault-selected edge case) into test + implementation
tasks. These clarifications are encoded in spec.md, plan.md, research.md
(R15-refined, R19–R22), data-model.md (VaultConfiguration, DiagnosticSnapshot,
Tombstone lifecycle, Constraints), contracts/ (`diagnostic-bundle.schema.json`,
`provider-errors.md` `wrongVault` category, `vault-bootstrap.schema.json`
description), and checklists/security.md. Tests are written FIRST and must FAIL
before implementation (Constitution XII).

### Tests for Phase 16 (write FIRST, must FAIL) ⚠️

- [X] T176 [P] [US9] SecurityCore test: wrong-vault-selected fail-closed — bootstrap fetch returns a `vaultId` ≠ locally-configured `vaultId` (or a bootstrap already exists under the chosen locator for a new vault) → app returns a typed `Encryption.wrongVaultContext` / `Credentials.wrongVault` error (per `contracts/provider-errors.md` `wrongVault` category); no PUT/DELETE issued to the remote (verified via provider test double); no local config mutation; user-facing message is localized and actionable; starting a new empty vault on a repo that already contains a different vault's bootstrap bootstraps under a new random locator without overwriting the existing one in `Packages/StickyCore/Tests/SecurityCoreTests/WrongVaultDetectionTests.swift` per FR edge case (clarified 2026-08-07) / research R20 / Constitution VII/VIII
- [X] T177 [P] [US9] SecurityCore test: remember-unlock lifetime — remember-unlock enabled → relaunch app → vault still unlocked without password re-entry; logout or restart → vault locked, password required; explicit lock → Keychain item cleared (referenced by `VaultConfiguration.rememberedUnlockKeychainRef`); password forgotten → unrecoverable even with remember-unlock on (FR-163); the application MUST NOT behave as a login-item-bound daemon that keeps the vault unlocked across system restarts in `Packages/StickyCore/Tests/SecurityCoreTests/RememberUnlockLifetimeTests.swift` per FR-162a (clarified 2026-08-07) / research R21 / data-model §VaultConfiguration / Constitution VII
- [X] T178 [P] [US9] SyncCore test: repository replacement — after confirmed replace (WebDAV→S3 or different endpoint): local notes preserved (count + content unchanged); new vault bootstraps fresh (new `vaultId` + `vaultLocator`); prior remote data untouched (verified via provider test double that no DELETE was issued against the old locator); `VaultConfiguration.replacedFromVaultLocator` records the prior locator for user reference; wrong-vault detection still fires if the new repo already contains a different vault in `Packages/StickyCore/Tests/SyncCoreTests/RepositoryReplacementTests.swift` per FR-154 (clarified 2026-08-07) / research R19 / Constitution III/VIII
- [ ] T179 [P] [US10] SyncCore test: long-offline tombstone purge reconciliation — returning device (offline >30 d, remote tombstone already purged by another device's cleanup) syncs: (a) MUST NOT auto-delete any local content; (b) reconciles remote deletion history before upload; (c) if no remote tombstone found for a note, treats as "no remote deletion record found" and preserves it locally; (d) notes the user deleted on the returning device MUST NOT be re-uploaded unless explicitly restored; (e) user is informed that some sync history has aged out; (f) if local version diverged from last known common ancestor, a conflict copy is created on next sync in `Packages/StickyCore/Tests/SyncCoreTests/LongOfflineTombstonePurgeTests.swift` per FR-174 (clarified 2026-08-07) / research R15-refined / data-model §Tombstone lifecycle / Constitution VIII
- [X] T180 [P] [US9] SyncCore/Diagnostics test: diagnostic-bundle field-boundary verification — generate a diagnostic bundle from a fixture vault with known note/asset content; assert the bundle contains EXACTLY the fields enumerated in `contracts/diagnostic-bundle.schema.json` (appVersion, osVersion, schemaVersionLocal, providerType, recentErrorEvents, syncRunCounts, objectCounts, vaultState, permissionStatuses, generatedAt) and NOTHING else; assert no note content, titles, summaries, captions, file names/paths, window titles, credentials, passwords, key material, raw server responses, or remote object names appear anywhere in the bundle; validate the bundle against the JSON Schema in `Packages/StickyCore/Tests/SyncCoreTests/DiagnosticBundleBoundaryTests.swift` (extends T109 `DiagnosticsPrivacyTests`) per FR-191 (clarified 2026-08-07) / research R22 / contracts/diagnostic-bundle.schema.json / Constitution VI/VII/SC-010

### Implementation for Phase 16

- [X] T181 [US9] Implement wrong-vault detection in VaultBootstrap — when fetching/bootstrap-checking a repository: compare the bootstrap object's `vaultId` against the locally-configured `VaultConfiguration.vaultId`; if mismatched (or a bootstrap already exists under the chosen locator for a new vault), return a typed `wrongVault` error per `contracts/provider-errors.md`; MUST NOT modify any local or remote data; MUST NOT issue PUT/DELETE to the remote; prompt user to choose a different repository or start a new empty vault under a fresh random locator (which bootstraps alongside the existing one without overwriting it) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` per FR edge case (clarified 2026-08-07) / research R20 / contracts/vault-bootstrap.schema.json / Constitution VII/VIII — VaultBootstrap exists (T112) but lacks the wrong-vault-id mismatch check and fail-closed path
- [X] T182 [US9] Implement remember-unlock lifetime in SecurityCore — add `rememberedUnlock` enum (disabled / enabledUntilLockOrRestart) + `rememberedUnlockKeychainRef` to `VaultConfiguration`; when enabled, store the unwrapped vault key in a Keychain item (referenced by `rememberedUnlockKeychainRef`) so ordinary app relaunches do not re-prompt; clear the Keychain item on explicit lock; MUST NOT survive logout/restart (not a login-item daemon); after logout/restart the password is required again; forgetting the sync password remains unrecoverable regardless of this setting (FR-163); exact "logout/restart detection" mechanism confirmed in M0 per research R21 in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` and `Packages/StickyCore/Sources/SecurityCore/KeychainAccess.swift` per FR-162a (clarified 2026-08-07) / research R21 / data-model §VaultConfiguration / Constitution VII
- [X] T183 [US9] Implement repository replacement flow in VaultBootstrap + SyncSettingsView — replacing an existing sync repository with a new one requires explicit user action with a clear warning and confirmation; upon confirmed replacement: local notes preserved; new vault bootstraps fresh (new `vaultId` + `vaultLocator`); the application MUST NOT automatically delete the prior repository's remote data (server-side cleanup of the old vault remains a manual user responsibility); record the prior locator in `VaultConfiguration.replacedFromVaultLocator` for user reference; wire the replacement UI (warning + confirmation + test-connection + bootstrap) into `SyncSettingsView` (extends T119) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` and `App/Sources/Features/Settings/SyncSettingsView.swift` per FR-154 (clarified 2026-08-07) / research R19 / data-model §VaultConfiguration / Constitution III/VIII
- [ ] T184 [US10] Refine OfflineReconciler for long-offline tombstone purge — when a returning device (offline >30 d) syncs and the remote tombstone was already purged by another device's cleanup: (a) reconcile remote deletion history BEFORE uploading local notes; (b) if no remote tombstone is found for a note, treat as "no remote deletion record found" and preserve it locally; (c) notes the user deleted on the returning device MUST NOT be re-uploaded unless the user explicitly restores them; (d) inform the user that some synchronization history has aged out; (e) if the local version diverged from the last known common ancestor, create a conflict copy on next sync; MUST NOT auto-delete any local content (refines T129 OfflineReconciler which currently has the generic long-offline handling but not the specific tombstone-purge-reconciliation behavior) in `Packages/StickyCore/Sources/SyncCore/OfflineReconciler.swift` per FR-174 (clarified 2026-08-07) / research R15-refined / data-model §Tombstone lifecycle / Constitution VIII
- [X] T185 [US9] Implement diagnostic-bundle export — generate the user-exportable diagnostic bundle from the `DiagnosticSnapshot` entity (data-model.md): collect app version, OS version, local schema version, sync provider type (WebDAV/S3 — never endpoint/hostname/credentials), normalized provider error categories + timestamps for the last 30 days (never raw server responses/bodies), sync run counts + durations (never payloads/object names), aggregate counts of notes/blocks/assets (never titles/summaries/captions/content), vault state (locked/unlocked/unconfigured — never password/derived key), permission statuses (screen-recording/accessibility booleans); any field not in the positive enumeration is excluded by default; validate the output against `contracts/diagnostic-bundle.schema.json` in `Packages/StickyCore/Sources/SyncCore/DiagnosticBundle.swift` (or `Packages/StickyCore/Sources/Domain/DiagnosticBundle.swift` if Domain-only) per FR-191 (clarified 2026-08-07) / research R22 / contracts/diagnostic-bundle.schema.json / data-model §DiagnosticSnapshot / Constitution VI/VII/SC-010
- [ ] T186 [US9] Wire diagnostic-bundle export into Settings UI — add an "Export Diagnostic Bundle" action in `SyncSettingsView` (or `SettingsView`) that generates the bundle via T185 and presents a save-panel (NSSavePanel via SystemBridge) so the user can save/share the JSON file for support; the filename is opaque (e.g. `stickynotes-diagnostics-<date>.json`); the exported file MUST validate against `contracts/diagnostic-bundle.schema.json` and MUST NOT contain any FR-191-excluded data; user-facing message explains what is included and that no note content/credentials are present in `App/Sources/Features/Settings/SyncSettingsView.swift` (or `App/Sources/Features/Settings/SettingsView.swift`) per FR-191 (clarified 2026-08-07) / SC-010 / Constitution VI

**Checkpoint**: All five 2026-08-07 clarifications have test + implementation tasks. Tests T176–T180 must FAIL before T181–T186 are implemented (Constitution XII). Phase 16 tasks depend on: T112 (VaultBootstrap), T117 (SyncEngine), T119 (SyncSettingsView — extended by T183), T129 (OfflineReconciler — refined by T184), T109 (DiagnosticsPrivacyTests — extended by T180). None of these block Phase 3–13 work; they are additive convergence tasks for the clarified encryption/privacy/sync requirements.

---

## Phase 17: Convergence — 2026-08-07 Clarification Propagation (Sessions 2 & 3)

**Purpose**: Propagate the eleven binding FRs added in the second and third
`/speckit-clarify` sessions (FR-022a, FR-023a, FR-072a, FR-090a, FR-094a,
FR-140a, FR-152a, FR-160a, FR-160b, FR-160c, FR-160d) into test +
implementation tasks. These promote previously-illustrative values into
binding spec requirements. Tests are written FIRST and must FAIL before
implementation (Constitution XII).

**Implementation audit (2026-08-07)**: Several values are already implemented
in the codebase and need only verification tests; three require implementation
changes (FR-094a thumbnail 512→256, FR-152a sync debounce, FR-160d exhaustive
fail-closed test vectors).

### Tests for Phase 17 (write FIRST, must FAIL) ⚠️

- [X] T187 [P] [US2] Domain/Persistence test: verify sort-key gap = 1024 and renormalization threshold = 64 per FR-022a — assert `VersionLineage.standardGap == 1024`, `VersionLineage.normalizationThreshold == 64`; assert inserting a note between two keys uses the midpoint; assert that when any adjacent gap in a contiguous run falls below 64, the run is renormalized with 1024 gaps within a single transaction (verify no intermediate ordering is observable) in `Packages/StickyCore/Tests/DomainTests/SortKeyBindingTests.swift` per FR-022a / data-model §Conventions / Constitution IV
- [X] T188 [P] [US2] Persistence test: verify FTS5 `notes_fts` is an external-content table backed by canonical note rows with an explicit rowid-to-Note.id mapping per FR-023a — assert the table uses external-content mode (not contentless); assert deleting a note cascades to remove its FTS5 entry automatically; assert a drift-detection + rebuild-from-canonical path exists; assert the rowid-to-Note.id mapping is deterministic and stable across migrations in `Packages/StickyCore/Tests/PersistenceTests/FTS5ExternalContentTests.swift` per FR-023a / data-model §SearchDocument / Constitution IV
- [X] T189 [P] [US4] Domain/EditorCore test: verify todo nesting max depth = 6 per FR-072a — assert `TodoHierarchyMaxDepth == 6`; assert indent is disabled when the active todo is at depth 6; assert validation rejects any todo hierarchy deeper than 6 levels; assert depth is counted from a top-level todo at depth 1 in `Packages/StickyCore/Tests/EditorCoreTests/TodoDepthBindingTests.swift` per FR-072a / data-model §TodoItem / Constitution V
- [X] T190 [P] [US9] SyncCore test: verify assets are synchronized as independent encrypted objects per FR-090a — assert each asset (original, thumbnail, app icon) is uploaded as its own encrypted envelope (never bundled inside a note envelope); assert each asset object carries a SHA-256 integrity hash; assert a failed asset upload does NOT block synchronization of the referencing note's metadata; assert the asset's sync state is set to `partialAssetSyncFailure` and retried independently on a subsequent sync run without re-encrypting or re-uploading already-succeeded note metadata in `Packages/StickyCore/Tests/SyncCoreTests/IndependentAssetSyncTests.swift` per FR-090a / data-model §Asset / Constitution IV/VIII
- [X] T191 [P] [US7] AssetStore test: verify thumbnail longest edge = 256px per FR-094a — assert `ThumbnailGenerator.defaultLongestEdge == 256`; assert generated thumbnails have a longest edge of exactly 256 pixels preserving aspect ratio; assert full-resolution screenshots and embedded images are NOT decoded for card-grid or widget rendering; assert thumbnail generation is lazy, off the main actor, and produces a stable hash for dedup in `Packages/StickyCore/Tests/AssetStoreTests/Thumbnail256BindingTests.swift` per FR-094a / plan §Asset storage / Constitution XI/SC-008
- [X] T192 [P] Persistence test: verify bounded busy timeout = 5 seconds per FR-140a — assert `DatabaseStore` default `busyTimeout == 5.0`; assert widget read transactions are short enough to complete within the timeout; assert that on timeout the widget reports a sanitized "temporarily unavailable" status (never a raw error or note content) and retries on next refresh in `Packages/StickyCore/Tests/PersistenceTests/BusyTimeoutBindingTests.swift` per FR-140a / research R26 / Constitution XI
- [X] T193 [P] [US9] SyncCore test: verify sync debounce window = 2-4 seconds after last local change per FR-152a — assert the sync engine does NOT fire while local edits are still arriving within the window; assert it fires once 2-4 seconds have elapsed since the most recent change; assert the chosen value is deterministic for a given build (no random jitter that could starve sync indefinitely); assert the debounce is cancelable by a manual-sync trigger, application shutdown, or network change; assert the debounce does NOT block local editing (FR-153) in `Packages/StickyCore/Tests/SyncCoreTests/SyncDebounceBindingTests.swift` per FR-152a / research R25 / Constitution VIII/XI
- [X] T194 [P] [US9] SecurityCore test: verify meaningful-metadata positive enumeration per FR-160a — assert every field in the FR-160a enumeration (user-content fields from FR-161, semantic object types, structural metadata, note appearance/behavior choices, version-lineage fields) is encrypted before upload; assert a negative test: no field outside the FR-160b observable-leakage bound is left unencrypted; assert any newly added synchronized field is evaluated against the enumeration in `Packages/StickyCore/Tests/SecurityCoreTests/MeaningfulMetadataEnumerationTests.swift` per FR-160a/FR-160b / research R23 / Constitution VII
- [X] T195 [P] [US9] SecurityCore test: verify Argon2id production minimums per FR-160c — assert production vault bootstrapping rejects parameter sets weaker than memory ≥ 19456 KiB (19 MiB), iterations ≥ 2, parallelism ≥ 1; assert the schema minimums (8/1/1) are accepted ONLY for test fixtures; assert parameter values used at vault creation are stored alongside the wrapped master key so future unlocks reproduce the derivation exactly in `Packages/StickyCore/Tests/SecurityCoreTests/Argon2idProductionMinimumTests.swift` per FR-160c / research R9-refined / contracts/vault-bootstrap.schema.json / Constitution VII
- [X] T196 [P] [US9] SecurityCore test: exhaustive fail-closed input vectors per FR-160d — assert each of the eight enumerated inputs triggers fail-closed: (a) wrong password; (b) modified ciphertext (bit-flip/truncation/extension); (c) invalid/mismatched AES-GCM auth tag; (d) mismatched object ID; (e) mismatched object type; (f) mismatched vault ID; (g) unsupported envelope schema version; (h) corrupted/truncated envelope structure. For each: assert the object is rejected without writing local data, without accepting the remote object, and without overwriting a local version. Assert the list is exhaustive for the initial release in `Packages/StickyCore/Tests/SecurityCoreTests/FailClosedVectorTests.swift` per FR-160d / research R24 / contracts/encrypted-envelope.schema.json / Constitution VII/XII

### Implementation for Phase 17

- [X] T197 [US7] Change `ThumbnailGenerator.defaultLongestEdge` from 512 to 256 per FR-094a — update the default longest-edge pixel size to 256 for both card and widget thumbnails; update any call sites that pass a custom value to use 256 unless they are app-icon generation (which remains 128); update `ThumbnailTests.swift` expected dimensions; verify no full-resolution decode occurs in card-grid or widget paths in `Packages/StickyCore/Sources/AssetStore/ThumbnailGenerator.swift` per FR-094a / plan §Asset storage / Constitution XI/SC-008 — **current value is 512; must change to 256**
- [X] T198 [US9] Implement sync debounce window (2-4 seconds) in SyncEngine per FR-152a — add a debounce mechanism that coalesces local-change notifications and fires the sync engine once 2-4 seconds have elapsed since the most recent change; the chosen value MUST be deterministic for a given build (no random jitter that could starve sync indefinitely); MUST be cancelable by manual-sync trigger, application shutdown, or network change; MUST NOT block local editing (FR-153); wire the debounce into the existing sync trigger list (replacing the current `~3s` placeholder if present) in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` per FR-152a / research R25 / plan §Synchronization engine / Constitution VIII/XI — **no debounce logic currently exists in SyncEngine.swift**
- [X] T199 [US9] Enforce Argon2id production-minimum rejection in KeyDerivation per FR-160c — add a validation function that rejects parameter sets weaker than memory ≥ 19456 KiB, iterations ≥ 2, parallelism ≥ 1 when called in a production (non-test-fixture) context; the current defaults (65536/3/4) already exceed the minimums, but the rejection guard MUST be explicit so a future caller cannot accidentally use weaker params; store the parameter values used at vault creation in the bootstrap object alongside the wrapped master key in `Packages/StickyCore/Sources/SecurityCore/KeyDerivation.swift` per FR-160c / research R9-refined / contracts/vault-bootstrap.schema.json / Constitution VII — **current defaults are stronger than minimums but no explicit rejection guard exists**
- [X] T200 [US9] Extend fail-closed test vectors to exhaustive FR-160d list in SecurityCore — verify that the existing fail-closed error categories in `Domain/Errors.swift` (wrongPassword, modifiedCiphertext, invalidTag, wrongObjectContext, unsupportedEnvelopeVersion) cover all eight FR-160d inputs; split `wrongObjectContext` into the distinct mismatch cases (object ID, object type, vault ID) if not already distinguished; add the corrupted/truncated-envelope-structure case if missing; ensure each input has a deterministic test vector (T196) that asserts fail-closed behavior in `Packages/StickyCore/Sources/SecurityCore/EncryptedEnvelope.swift` and `Packages/StickyCore/Sources/Domain/Errors.swift` per FR-160d / research R24 / contracts/encrypted-envelope.schema.json / Constitution VII/XII — **error categories partially exist but are not exhaustive against the FR-160d list; `wrongObjectContext` may need splitting into distinct cases**
- [X] T201 [P] [US9] Verify FTS5 external-content mode in Persistence — inspect the existing FTS5 migration in `m0001_initial.swift` to confirm `notes_fts` is created as an external-content table (using `synchronize(withTable:)` or contentless-with-external-content); if the current implementation is contentless-with-rowid rather than external-content, refactor to external-content backed by canonical note rows with an explicit rowid-to-Note.id mapping per FR-023a; ensure note deletion cascades to the FTS5 entry automatically; add a drift-detection + rebuild-from-canonical path if absent in `Packages/StickyCore/Sources/Persistence/FullTextSearch.swift` and `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` per FR-023a / research R25 / data-model §SearchDocument / Constitution IV — **T157 fixed a stale FTS5 comment referencing `synchronize(withTable:)`; verify the actual mode matches FR-023a**
- [X] T202 [P] [US9] Verify independent-asset sync granularity in SyncEngine — inspect the existing sync engine to confirm assets are uploaded as independent encrypted objects (not bundled in note envelopes); if assets are currently bundled, refactor to independent per-object upload with SHA-256 integrity hash and independent partial-failure retry; ensure the `partialAssetSyncFailure` sync state is set when an asset upload fails and the asset is retried independently without re-uploading note metadata in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` per FR-090a / research R27 / data-model §Asset / Constitution IV/VIII — **`partialAssetSyncFailure` enum exists; verify the sync engine actually uses independent asset objects**

**Checkpoint**: All eleven binding FRs from clarify sessions 2 & 3 have test +
implementation tasks. Tests T187–T196 must FAIL before T197–T202 are
implemented (Constitution XII). Phase 17 tasks depend on: T013 (VersionLineage
— verified by T187), T020 (FTS5 — verified/refactored by T201), T061
(TodoRepository — verified by T189), T087/T088 (AssetStore/ThumbnailGenerator
— changed by T197, verified by T190/T191), T017 (DatabaseStore — verified by
T192), T117 (SyncEngine — extended by T198, verified by T193), T111
(SecurityCore — extended by T199/T200, verified by T194/T195/T196). None of
these block Phase 3–13 work; they are additive convergence tasks for the
binding values clarified in sessions 2 & 3.

**Implementation audit summary** (informs which tasks are verify-only vs
require changes):
- FR-022a (sort gap=1024, renorm<64): ✓ already implemented — T187 verify only
- FR-023a (FTS5 external-content): ⚠ verify mode — T201 verify/refactor
- FR-072a (todo maxDepth=6): ✓ already implemented — T189 verify only
- FR-090a (independent encrypted assets): ⚠ verify granularity — T202 verify/refactor
- FR-094a (256px thumbnail): ✗ currently 512px — T197 requires change
- FR-140a (5s busy timeout): ✓ already implemented — T192 verify only
- FR-152a (2-4s sync debounce): ✗ not implemented — T198 requires implementation
- FR-160a (meaningful-metadata enum): ⚠ verify encryption scope — T194 verify
- FR-160b (observable-leakage bound): ⚠ verify manifest — T194 verify
- FR-160c (Argon2id minimums): ✓ already stronger — T199 add explicit guard
- FR-160d (fail-closed inputs): ⚠ partial — T200 extend to exhaustive list

## Phase 18: Convergence — 2026-08-07 UX Requirements (FR-014a, SC-004a)

**Purpose**: Propagate the two binding spec requirements added after a
`checklists/ux.md` coverage review (CHK058): **FR-014a** (first-launch
experience: empty library with a clear create-first-note call to action; no
permission prompts on first launch unless the user invokes a feature requiring
them; sync-status area shows "not configured" rather than an error when sync is
unconfigured; a brief, dismissible onboarding hint explaining auto-save and the
menu-bar-primary model, never shown again after the first note is created) and
**SC-004a** (keystroke-to-glyph latency <16 ms during normal editing including
with Chinese IME composition active, measured via OSLog signposts/Instruments).
Both are UI/UX-facing; no impact on contracts or the sync protocol. Tests are
written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: `StickyLogger` already provides
`signpostBegin`/`signpostEnd` (OSSignposter) in `Domain/Logging.swift` — SC-004a
needs the editor keystroke path wired through them and a latency assertion.
FR-014a has no existing implementation: `App/Sources/Features/Library/` and
`App/Sources/Features/Editor/` are empty, `StickyNotesApp.swift` ships only a
stub `MenuBarExtra`, and `PermissionService` (T104) exists but has no
startup-path guard.

### Tests for Phase 18 (write FIRST, must FAIL) ⚠️

- [X] T203 [P] [US1] Domain test: first-launch hint state machine per FR-014a — assert `FirstLaunchState` returns `shouldShowOnboardingHint == true` on a fresh state (seen=false, dismissed=false, hasCreatedFirstNote=false); returns `false` once `hasCreatedFirstNote` is set (never shown again after the first note is created); returns `false` once `dismissed` is set; returns `false` when dismissed even if `seen`; assert the state never carries sync/canonical-JSON exposure (pure value type, no UserDefaults dependency) in `Packages/StickyCore/Tests/DomainTests/FirstLaunchStateTests.swift` per FR-014a / research R28 / data-model §LocalPreferences / Constitution X/IV
- [ ] T204 [P] [US1] App integration test: first-launch experience end-to-end per FR-014a — on a fresh App Group container with no Keychain credentials: launch → the menu-bar library shows an empty card grid with a clear call-to-action to create the first note (button + keyboard shortcut); the sync-status area shows "not configured" (never an error); NO permission prompt fires during launch (assert `PermissionService` records no request on the startup path); a dismissible onboarding hint explaining auto-save and the menu-bar-primary model is visible; after creating the first note the hint is never shown again across relaunches; dismissing the hint also hides it permanently in `AppTests/FirstLaunchExperienceIntegrationTests.swift` per FR-014a / research R28 / data-model §LocalPreferences / Constitution VI/X/III
- [ ] T205 [P] [US1] EditorCore performance test: keystroke-to-glyph latency <16 ms per SC-004a — signpost-bracket the editor input path (keystroke event → attributed-state mutation → glyph commit) via `StickyLogger.signpostBegin`/`signpostEnd`; assert the interval stays below 16 ms (one frame at 60 Hz) for plain English, Chinese IME marked-text, mixed CJK/Latin, and emoji input sequences; assert signposts carry timing and sanitized op names only (no note content, per FR-191/Constitution VI) in `Packages/StickyCore/Tests/EditorCoreTests/KeystrokeLatencyTests.swift` per SC-004a / research R29 / plan §Keystroke latency instrumentation / Constitution XI/XII/VI

### Implementation for Phase 18

- [X] T206 [US1] Implement `FirstLaunchState` value type in `Packages/StickyCore/Sources/Domain/Models/FirstLaunchState.swift` — pure Foundation-only state machine (seen/dismissed/hasCreatedFirstNote) with `shouldShowOnboardingHint` per FR-014a; no UserDefaults or App Group references in Domain (storage lives in the App layer, T207); satisfies T203 per FR-014a / research R28 / data-model §LocalPreferences / Constitution X/IV
- [X] T207 [US1] Implement device-local persistence of first-launch state in `App/Sources/Features/Library/LocalPreferences.swift` — store `onboardingHintSeen`, `onboardingHintDismissed`, `hasCreatedFirstNote` in App Group UserDefaults (device-local only; NEVER synchronized, NEVER in canonical JSON, NEVER in exported diagnostics per FR-191/data-model §LocalPreferences); set `hasCreatedFirstNote` on first-note creation; wire into `AppEnvironment` per FR-014a / research R28 / data-model §LocalPreferences / Constitution IV/VI
- [ ] T208 [US1] Implement empty-library CTA + onboarding hint UI in `App/Sources/Features/Library/EmptyLibraryView.swift` — empty card-grid state with a clear call-to-action to create the first note (button + keyboard shortcut); a brief, dismissible onboarding hint explaining auto-save and the menu-bar-primary model; the hint is never shown again once `hasCreatedFirstNote` or `dismissed` is set (T207); wire into `MenuBarLibraryScene.swift` (extends T032/T159) per FR-014a / research R28 / Constitution X/III
- [ ] T209 [US1] Implement "not configured" sync status in `App/Sources/Features/Library/SyncStatusView.swift` — when no `VaultConfiguration` exists, the sync-status area shows "not configured" (never an error); only show error/status states when sync is actually configured (extends T120/T170) per FR-014a / plan §First-launch experience / Constitution III
- [X] T210 [US1] Enforce no-permission-prompts-on-first-launch guard — verify `PermissionService` (T104) is invoked ONLY when the user invokes the feature requiring it (screen-recording on capture invocation, accessibility never on startup); assert the startup path (`AppEnvironment`/`StickyNotesApp.swift`) performs no permission request; any request during launch is a regression per FR-014a/FR-131 in `App/Sources/App/AppEnvironment.swift` and `Packages/StickyCore/Sources/SystemBridge/PermissionService.swift` per FR-014a / Constitution VI
- [ ] T211 [US1] Instrument keystroke-to-glyph path with OSLog signposts per SC-004a — wire `StickyLogger.signpostBegin`/`signpostEnd` (already provided in `Packages/StickyCore/Sources/Domain/Logging.swift`) around keystroke event → attributed-state commit → glyph commit in the editor input path; signposts carry timing and sanitized op names only (no note content per FR-191); verify the interval appears in the Instruments Signpost Logging track and stays below 16 ms per T205 in `App/Sources/Features/Editor/RichTextBlockView.swift` (extends T036) per SC-004a / research R29 / plan §Keystroke latency instrumentation / Constitution XI/VI

**Checkpoint**: FR-014a and SC-004a have test + implementation tasks. Tests
T203–T205 must FAIL before T206–T211 are implemented (Constitution XII).
Phase 18 tasks depend on: T032/T159 (MenuBarLibraryScene — extended by T208,
T209), T104 (PermissionService — guarded by T210), T036 (editor input path —
instrumented by T211), Domain/Logging.swift signpost helpers (already
implemented). None of these block Phase 3–13 work; they are additive
convergence tasks for the UX requirements clarified 2026-08-07.

**Implementation audit summary** (informs which tasks are verify-only vs
require changes):
- FR-014a (first-launch experience): ✗ not implemented — T203/T204 verify, T206–T210 implement
- SC-004a (keystroke-to-glyph <16 ms): ⚠ signpost helpers exist; editor path not instrumented — T205 verify, T211 implement

## Phase 19: Convergence — 2026-08-07 Third Clarify Session (FR-012a, FR-160e, FR-022a Trash-restore, FR-162a Launch + Toggle)

**Purpose**: Propagate the five binding clarifications added in the third
`/speckit-clarify` session: **FR-012a** (precise "meaningful text" definition
for empty-note auto-removal: ≥1 non-whitespace Unicode character in the title
or any rich-text block, OR the presence of any todo/image/screenshot/code-
block/file-reference block; a single character qualifies, whitespace-only does
not), **FR-160e** (wrong-password unlock attempts MUST NOT be rate-limited,
throttled, or lockout-bounded; Argon2id KDF cost is the rate limiter; no
cached password/derived key), **FR-022a Trash-restore** (restoring a note
from Trash resets its `manualSortKey` to max(active)+1024, placing it at the
end of Manual order; pre-deletion key not retained), and **FR-162a launch +
toggle** (app-launch unlock via boot-timestamp comparison — remember enabled +
no restart → silent restore + startup sync, otherwise prompt; toggle-off while
unlocked clears Keychain immediately but preserves the current unlocked
session until explicit lock/exit). Tests are written FIRST and must FAIL
before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: T077/T081 cover the basic auto-
discard concept but do not pin the FR-012a one-non-whitespace-character
threshold. T112 covers vault bootstrap but has no FR-160e no-lockout guard or
FR-162a boot-timestamp/toggle logic. T079 covers the lifecycle state machine
but not the FR-022a Trash-restore sort-key reset.

### Tests for Phase 19 (write FIRST, must FAIL) ⚠️

- [X] T212 [P] [US6] Domain test: FR-012a meaningful-text boundary — assert a note is auto-removable on close ONLY when it has never contained meaningful content, where "meaningful content" = (a) at least one non-whitespace Unicode character in the title field, OR (b) at least one non-whitespace Unicode character in any rich-text block, OR (c) the presence of any todo/image/screenshot/code-block/file-reference block regardless of text length. Test matrix: whitespace-only title+body → auto-removable; single Latin letter in body → NOT auto-removable; single CJK character → NOT auto-removable; single emoji → NOT auto-removable; single punctuation char → NOT auto-removable; empty todo block present → NOT auto-removable (structural block); note that previously held content, now emptied → NOT auto-deleted (FR-013). Assert the rule is Unicode-whitespace-aware (spaces, tabs, newlines, U+3000 ideographic space, etc. do NOT qualify) in `Packages/StickyCore/Tests/DomainTests/MeaningfulTextBoundaryTests.swift` per FR-012a / research R30 / Constitution III/XII
- [X] T213 [P] [US9] SecurityCore test: FR-160e no-rate-limit on wrong-password unlock — assert any number of consecutive wrong-password unlock attempts yields the same fail-closed behavior (per FR-160d (a)) with NO state accumulation, NO increasing delay, NO lockout, NO attempt counter, and NO caching of the supplied password or derived key; assert a correct password succeeds immediately after N wrong attempts with no residual throttle; assert a single Argon2id derivation with FR-160c production minimums takes ≥100 ms on reference hardware (sanity bound confirming KDF-cost rate limiting) in `Packages/StickyCore/Tests/SecurityCoreTests/NoLockoutPolicyTests.swift` per FR-160e / research R31 / contracts/encrypted-envelope.schema.json / Constitution VII/VI
- [X] T214 [P] [US6] Persistence test: FR-022a Trash-restore sort-key reset — delete a note from the middle of Manual order (sort-key S_mid); insert a new note (which may reuse the freed position); restore the deleted note → assert the restored note's `manualSortKey` equals (max(active sort-key) + 1024), NOT S_mid; assert it appears at the end of Manual order; assert no renormalization is triggered by restore alone (the new key is strictly greater than all existing keys); assert ordering of other notes is unchanged in `Packages/StickyCore/Tests/PersistenceTests/TrashRestoreSortKeyTests.swift` per FR-022a (clarified 2026-08-07) / research R32 / data-model §Conventions/Note lifecycle / Constitution IV/XII/X
- [X] T215 [P] [US9] SecurityCore test: FR-162a app-launch unlock via boot timestamp — assert when `rememberedUnlock = enabledUntilLockOrRestart` AND `rememberedUnlockBootTimestamp` equals the current system boot timestamp AND vault not explicitly locked → app launch silently restores the unlocked vault state from Keychain and triggers startup sync per FR-152a without prompting; assert when boot timestamp differs (simulated restart) → launch prompts for password; assert when `rememberedUnlock = disabled` → launch prompts; assert when vault explicitly locked → launch prompts; assert the boot-timestamp comparison is the sole restart-detection mechanism (no login-item/daemon dependency) in `Packages/StickyCore/Tests/SecurityCoreTests/AppLaunchUnlockTests.swift` per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/XII
- [X] T216 [P] [US9] SecurityCore test: FR-162a toggle-off while unlocked — assert toggling `rememberedUnlock` from `enabledUntilLockOrRestart` to `disabled` while the vault is currently unlocked: (a) immediately removes the remembered key from Keychain (clears `rememberedUnlockKeychainRef` and `rememberedUnlockBootTimestamp`); (b) preserves the current unlocked vault state in memory (no re-prompt, no forced lock); (c) a subsequent app launch (without restart) prompts for the password (Keychain item gone); (d) explicit lock still works and clears the in-memory key. Assert the application MUST NOT force a re-prompt merely because the setting was toggled off in `Packages/StickyCore/Tests/SecurityCoreTests/RememberUnlockToggleTests.swift` per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/X

### Implementation for Phase 19

- [X] T217 [US6] Pin FR-012a meaningful-text threshold in auto-discard logic — define a `Note.hasMeaningfulContent(for autoDiscard:)` predicate (or equivalent) in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` (extends T079) that returns `true` when the title or any rich-text block contains ≥1 non-whitespace Unicode character OR any todo/image/screenshot/code-block/file-reference block is present; wire it into the empty-note auto-discard hook in `NoteWindowCoordinator` (T081/T167) so the auto-removal decision uses this exact rule; update `EmptyNoteDiscardTests.swift` (T077) expected cases to match FR-012a if they currently use a looser/stiffer threshold in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` per FR-012a / research R30 / Constitution III/XII — **T077/T081 cover the concept but do not pin the one-non-whitespace-character threshold; this task makes it exact**
- [X] T218 [US9] Enforce FR-160e no-lockout policy in SecurityCore — audit `Packages/StickyCore/Sources/SecurityCore/` (VaultBootstrap.swift, KeyDerivation.swift, and any unlock entry point) to confirm there is NO attempt counter, NO timed backoff, NO lockout state, and NO caching of the supplied wrong password or derived key; if any such mechanism exists, remove it; add an explicit invariant comment + guard that wrong-password unlock is stateless and relies solely on the Argon2id KDF cost (FR-160c) for rate limiting; verify the unlock path calls the Argon2id derivation on every attempt (no short-circuit) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` per FR-160e / research R31 / contracts/encrypted-envelope.schema.json / Constitution VII/VI — **audit + guard; remove any latent lockout logic if present**
- [X] T219 [US6] Implement FR-022a Trash-restore sort-key reset in NoteLifecycle/NoteRepository — when a note transitions trashed → active (restore), set its `manualSortKey` to (current maximum `manualSortKey` among active notes) + 1024 within the same restore transaction; do NOT retain the pre-deletion sort-key; verify the new key is strictly greater than all existing active keys so no renormalization is triggered by restore alone in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` (extends T079) and `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift` (extends T030) per FR-022a (clarified 2026-08-07) / research R32 / data-model §Conventions/Note lifecycle / Constitution IV/XII/X — **restore path exists (T079) but does not reset the sort-key; this task adds the reset**
- [X] T220 [US9] Implement FR-162a app-launch unlock + boot-timestamp detection in SecurityCore/VaultConfiguration — add `rememberedUnlockBootTimestamp: Int?` field to `VaultConfiguration` (device-local); at remember-time, capture the system boot timestamp (via `sysctl kern.boottime` or equivalent — exact API confirmed in M0 per research R33) and store it alongside the Keychain reference; at app launch with auto-sync enabled, compare the stored timestamp against the current boot timestamp: if `rememberedUnlock = enabledUntilLockOrRestart` AND timestamps match AND vault not explicitly locked → silently restore the unlocked vault state from Keychain and trigger startup sync per FR-152a without prompting; otherwise prompt for the password. Add a migration for the new `VaultConfiguration` column if the table already exists in `Packages/StickyCore/Sources/SecurityCore/VaultConfiguration.swift` (or Domain model per T011), `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` (extends T112), and `Packages/StickyCore/Sources/Persistence/Migrations/` per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/XII — **no boot-timestamp detection exists; this task implements it**
- [X] T221 [US9] Implement FR-162a toggle-off behavior in SecurityCore/Settings — when the user toggles `rememberedUnlock` from `enabledUntilLockOrRestart` to `disabled` while the vault is currently unlocked: immediately remove the remembered key from Keychain (clear `rememberedUnlockKeychainRef` and `rememberedUnlockBootTimestamp`); preserve the current unlocked vault state in memory until the user explicitly locks the vault or the application exits; do NOT force a re-prompt or forced lock; wire the toggle handler into the sync Settings UI (T119) in `Packages/StickyCore/Sources/SecurityCore/VaultConfiguration.swift` and `App/Sources/Features/Settings/SyncSettingsView.swift` (extends T119) per FR-162a (clarified 2026-08-07) / research R33 / data-model §VaultConfiguration / Constitution VII/VI/X — **no toggle-off-specific behavior exists; this task adds immediate Keychain clearance + session preservation**

**Checkpoint**: All five binding clarifications from the third clarify
session have test + implementation tasks. Tests T212–T216 must FAIL before
T217–T221 are implemented (Constitution XII). Phase 19 tasks depend on:
T079 (NoteLifecycle — extended by T217, T219), T081/T167 (NoteWindowCoordinator
auto-discard hook — wired by T217), T030 (NoteRepository — extended by T219),
T112 (VaultBootstrap — extended by T218, T220), T011 (VaultConfiguration
Domain model — extended by T220), T119 (SyncSettingsView — extended by T221).
None of these block Phase 3–13 work; they are additive convergence tasks for
the clarifications added in the third 2026-08-07 `/speckit-clarify` session.

**Implementation audit summary** (informs which tasks are verify-only vs
require changes):
- FR-012a (meaningful-text threshold): ⚠ concept covered by T077/T081, threshold not pinned — T212 verify, T217 pin exact rule
- FR-160e (no-lockout policy): ⚠ audit + guard — T213 verify, T218 audit/remove latent logic
- FR-022a Trash-restore (sort-key reset): ✗ restore path exists but no reset — T214 verify, T219 implement reset
- FR-162a launch (boot-timestamp): ✗ not implemented — T215 verify, T220 implement
- FR-162a toggle-off (Keychain clearance + session preserve): ✗ not implemented — T216 verify, T221 implement

## Phase 20: Convergence — 2026-08-07 Clarify Sessions 4 & 5 (FR-031a, FR-180a, FR-090b, FR-141a, FR-022b, FR-014b, FR-040a, FR-041a, FR-050a, FR-110a)

**Purpose**: Propagate the ten binding clarifications added in the fourth and
fifth `/speckit-clarify` sessions into test + implementation tasks:
**FR-031a** (single-note JSON export/import reusing the canonical
note-envelope schema; round-trip faithful; file references export generic
metadata only; import fails closed), **FR-180a** (zh-Hans + en UI
localization, system-language switch), **FR-090b** (scale limits: asset
≤ 50 MB / ≤ 16,384 px longest edge; note structured content ≤ 5 MB; oversize
insertions rejected), **FR-141a** (auto-save debounce 500 ms; flush before
close/delete/quit; crash-loss window ≤ one debounce window), **FR-022b**
(manual-order sort-key divergence reconciled per-note by last-writer-wins,
no conflict copies), **FR-014b** (Empty Trash batch permanent delete with
explicit confirmation), **FR-040a** (canonical sRGB hex per built-in color),
**FR-041a** (opacity 40%–100%, 5-pt steps, default 100%), **FR-050a**
(emptied blocks removed on cursor exit, final block preserved, single-Undo,
IME-safe), **FR-110a** (change-driven widget refresh, no fixed polling).
Whole-library bulk export/import is a declared non-goal. Tests are written
FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: FR-040a/FR-041a/FR-090b/FR-014b/
FR-031a have no existing implementation (colors/opacity are unbound values,
no size caps, no Empty Trash, no export/import path). FR-141a has a
debounce concept (T037) but no pinned 500 ms value or crash-loss contract.
FR-050a block deletion exists but has no cursor-exit/merge rule. FR-110a
widget reload exists (Phase 10) but is not change-driven. FR-180a string
catalogs are planned (T008) but not bound to zh-Hans+en completeness.
FR-022b has no sync-side sort-key coordination.

### Tests for Phase 20 (write FIRST, must FAIL) ⚠️

- [ ] T222 [P] [US6] Persistence test: Empty Trash batch permanent delete per FR-014b — with N notes in Trash, invoking Empty Trash without confirmation deletes nothing; after confirmation, ALL trashed notes transition trashed → permanentlyDeleted in a single transaction (no intermediate observable state); readable local content removed when safe; a Tombstone is retained per note for sync (FR-174 sync-safety applies); the confirmation states immediate permanent deletion and loss of the 30-day recoverability guarantee in `Packages/StickyCore/Tests/PersistenceTests/EmptyTrashTests.swift` per FR-014b / research R38 / data-model §Note lifecycle / Constitution X/VIII
- [ ] T223 [P] [US10] SyncCore test: sort-key-only divergence → per-note LWW, no conflict copy per FR-022b — (a) two devices reorder the same notes differently with NO content change → sync applies the most recently written sort key per note (deterministic via version timestamp/sequence), NO conflict copy is created; (b) crossed reorder (A moves X above Y while B moves Y above X) resolves deterministically per-note by version recency; (c) sort-key divergence combined with real content divergence → a content conflict copy IS still created; (d) assert content fields are the ONLY divergence trigger in `Packages/StickyCore/Tests/SyncCoreTests/SortKeyLastWriterWinsTests.swift` per FR-022b / research R35 / plan §Conflict model / Constitution VIII/IV/XII
- [ ] T224 [P] [US1] Domain/Persistence test: note JSON export/import round-trip per FR-031a — export a note containing every block kind (rich text with all supported attributes, todos incl. nesting/state/order, code block, file reference, embedded image, screenshot) → import the JSON → assert byte-level semantic equality of text, rich-text attributes, todo identity/text/state/nesting/order, code text, image/screenshot asset payloads, and appearance (color, transparency, text size, Always-on-Top); assert file-reference blocks import with generic metadata only (display name, content type, size, origin device, added date — NEVER bookmark bytes or absolute paths per FR-105); assert importing an unsupported schema version or corrupted envelope fails closed with NO partial note created; assert the exported document validates against `contracts/note-document.schema.json` in `Packages/StickyCore/Tests/DomainTests/NoteExportImportRoundTripTests.swift` per FR-031a / research R34 / contracts/note-document.schema.json / Constitution IV/XII
- [ ] T225 [P] [US3] Domain test: canonical color hexes + opacity range per FR-040a/FR-041a — assert the six built-in colors resolve to EXACTLY the canonical sRGB hexes (yellow #FFE08A, pink #F9A8C4, purple #C9A8E8, blue #A8CFF9, green #A8E8B8, gray #D8D8DC) shared across light/dark; assert opacity is constrained to 0.40–1.00 in 0.05 steps with default 1.00; assert FR-042 WCAG 2.2 contrast (≥4.5:1 normal, ≥3:1 large/controls) holds for the full matrix: 6 colors × 13 opacity steps × light/dark, computed against the effective composited background (note color at chosen opacity over a desktop sample), with automatic foreground adjustment as the fallback in `Packages/StickyCore/Tests/DomainTests/NoteAppearanceBindingTests.swift` per FR-040a/FR-041a / research R37 / data-model §Note / Constitution X/XI/XII
- [ ] T226 [P] [US1] EditorCore test: empty-block removal per FR-050a — (a) an emptied block (paragraph/list item/todo/heading) stays in place while the cursor remains within it; (b) on cursor exit the block is removed by merging with the adjacent block (or deleted when no merge is possible); (c) the final block of a note is NEVER removed this way (remains an empty paragraph); (d) a single Undo restores the removed block and its content; (e) removal does NOT fire while an input-method marked-text composition is active (FR-063) in `Packages/StickyCore/Tests/EditorCoreTests/EmptyBlockRemovalTests.swift` per FR-050a / research R38 / plan §Editor architecture / Constitution V/X/XII
- [ ] T227 [P] [US7] AssetStore/Persistence test: scale limits per FR-090b — assert constants: max asset bytes = 50 MB, max asset longest edge = 16,384 px, max note structured content = 5 MB; pasting/inserting an image over any asset limit is rejected with a localized explanation and NO partial asset write (no orphan temp file, no metadata record); a content change that would push note structured content over 5 MB is refused while the last valid saved state is preserved intact; assets within limits still sync as independent objects (FR-090a) in `Packages/StickyCore/Tests/AssetStoreTests/ScaleLimitTests.swift` per FR-090b / research R39 / contracts/asset-metadata.schema.json / Constitution XI/IV/XII
- [ ] T228 [P] [US8] App/Widget test: change-driven widget refresh per FR-110a — after a local change affecting a widget (note created/edited/deleted/trashed/restored, todo toggled, widget-eligibility changed, conflict copy created), assert the main app triggers a WidgetKit timeline reload for the affected widget kind(s) (via WidgetCenter test double) and does NOT reload unaffected kinds; a widget action (todo toggle, quick-create) also triggers refresh of affected widgets; assert the widget process contains NO fixed-interval polling timer (no `Timer`/repeating refresh scheduling) in `AppTests/WidgetChangeDrivenRefreshTests.swift` per FR-110a / research R36 / plan §Widgets / Constitution XI/VI/SC-006
- [ ] T229 [P] [US1] Persistence test: auto-save debounce + crash-loss contract per FR-141a — assert ordinary text changes persist in a single transaction once 500 ms elapse without further changes (deterministic per build); structural ops/todo completion persist immediately; flush happens before window close, note deletion, auto-removal decision (FR-012), and application quit; crash-recovery: terminate the process mid-edit (within the debounce window), relaunch, assert at most the input from the last debounce window is lost and content persisted by a completed autosave is always recovered in `Packages/StickyCore/Tests/PersistenceTests/AutosaveCrashConsistencyTests.swift` per FR-141a / research R17-refined / plan §Auto-save / Constitution III/XII
- [ ] T230 [P] [US1] App test: zh-Hans + en localization completeness per FR-180a — assert every user-visible string (menus, buttons, tooltips, toasts, settings, Help, accessibility labels, error/sync status) is resolved from the localization catalogs with NO hard-coded UI strings (source scan for string literals in `App/Sources/`); assert both zh-Hans and en variants exist for every catalog key; assert the deletion toast announced by VoiceOver (FR-009a) respects the active locale; assert the SC-011 core capture loop is operable in either language in `AppTests/LocalizationCompletenessTests.swift` per FR-180a / plan §Localization / Constitution X/II/XII

### Implementation for Phase 20

- [ ] T231 [US6] Implement Empty Trash in Trash view + NoteRepository per FR-014b — add an "Empty Trash" action to the Trash UI (`App/Sources/Features/Trash/TrashView.swift`, extends T167): the action opens a confirmation dialog stating that all notes in Trash will be permanently deleted immediately and that the 30-day recoverability guarantee (FR-014) no longer applies (localized per FR-180a, keyboard-accessible per FR-181); on confirmation, transition every trashed note to permanentlyDeleted in a single transaction with tombstone retention per FR-174 (`Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift`, extends T030) per FR-014b / research R38 / data-model §Note lifecycle / Constitution X/VIII
- [ ] T232 [US10] Implement per-note sort-key last-writer-wins in SyncCore per FR-022b — in the divergence detection path (`Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` or the divergence detector), when comparing local vs remote note versions: if the ONLY differing field is `manualSortKey`, accept the newer version's sort key (deterministic per-note by version timestamp/sequence) WITHOUT recording divergence and WITHOUT creating a conflict copy; if any content field also differs, the normal conflict-copy path applies; crossed reorders resolve per-note by version recency (no global order arbitration) per FR-022b / research R35 / plan §Conflict model / Constitution VIII/IV — **no per-field divergence classification exists; this task adds it**
- [ ] T233 [US1] Implement single-note JSON export/import per FR-031a — export: serialize the note (blocks + embedded asset payloads + appearance) into the canonical note-document form (`Packages/StickyCore/Sources/Domain/NoteDocumentSerializer.swift`), write via NSSavePanel (SystemBridge, sandbox user-selected location); import: read via NSOpenPanel, validate `schemaVersion` and envelope structure, fail closed on unsupported/corrupted documents with NO partial note, insert through the same repository path as new notes (T030); file-reference blocks export/import generic metadata only — never bookmark bytes or absolute paths (FR-105); wire both actions into the note contextual menu (extends T031) and library (import) in `App/Sources/Features/NoteWindow/NoteExportImport.swift` and `Packages/StickyCore/Sources/Domain/NoteDocumentSerializer.swift` per FR-031a / research R34 / contracts/note-document.schema.json / Constitution IV/X — **no export/import path exists**
- [ ] T234 [US3] Implement canonical colors + bounded opacity per FR-040a/FR-041a — define the six canonical sRGB hex constants in `Packages/StickyCore/Sources/Domain/Models/NoteAppearance.swift` (yellow #FFE08A, pink #F9A8C4, purple #C9A8E8, blue #A8CFF9, green #A8E8B8, gray #D8D8DC); constrain note background opacity to 0.40–1.00 in 0.05 steps with default 1.00 (replacing any unbounded value in T034); apply FR-042 contrast validation and automatic foreground adjustment against the effective composited background whenever opacity < 1.00; any hex change must update the T225 contrast matrix in the same change (Constitution IV) per FR-040a/FR-041a / research R37 / data-model §Note / Constitution X/XI — **colors/opacity currently unbound; this task pins them**
- [ ] T235 [US1] Implement empty-block removal in EditorCore per FR-050a — when the cursor leaves an emptied block (paragraph/list item/todo/heading): remove it by merging with the adjacent block (or deleting when no merge is possible); never remove the final block of a note (it remains an empty paragraph); group the removal as ONE undo operation (single Undo restores block + content); suppress removal while an input-method marked-text composition is active (FR-063) in `Packages/StickyCore/Sources/EditorCore/BlockMergeOperation.swift` (new) wired into the editor focus/movement path (`App/Sources/Features/Editor/RichTextBlockView.swift`, extends T036) per FR-050a / research R38 / plan §Editor architecture / Constitution V/X — **block deletion exists (T036) but has no cursor-exit/merge rule; this task adds it**
- [ ] T236 [US7] Implement scale limits in AssetStore/Persistence per FR-090b — add explicit constants (maxAssetBytes = 50 MB, maxAssetLongestEdge = 16,384 px, maxNoteContentBytes = 5 MB) enforced at the asset-store and persistence boundaries: oversize paste/capture insertions are rejected with a localized explanation and NO partial asset write (no orphan temp files, no metadata record); content changes that would exceed the 5 MB note-content cap are refused while the last valid saved state is preserved; constants documented and covered by T227 in `Packages/StickyCore/Sources/AssetStore/AssetStore.swift` and `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift` per FR-090b / research R39 / contracts/asset-metadata.schema.json / Constitution XI/IV — **no size caps exist**
- [ ] T237 [US8] Implement change-driven widget refresh per FR-110a — add a `WidgetRefreshCoordinator` (`App/Sources/App/WidgetRefreshCoordinator.swift`): after any persistence write affecting widget surface (note created/edited/deleted/trashed/restored, todo toggled, widget-eligibility changed, conflict copy created), call `WidgetCenter.shared.reloadTimelines(ofKind:)` for the affected kinds only; widget actions (todo toggle, quick-create) trigger refresh of affected widgets; ensure NO fixed-interval polling timer exists in the widget process (SC-006); when the app is not running, widgets may show last-known content until the app next runs or the system refreshes (FR-140a "temporarily unavailable" on read failure) per FR-110a / research R36 / plan §Widgets / Constitution XI/VI — **widget reload exists (Phase 10) but is not change-driven**
- [ ] T238 [US1] Implement 500 ms auto-save debounce + crash-loss contract per FR-141a — replace the current debounce value (~300 ms placeholder in `Packages/StickyCore/Sources/Persistence/NoteAutosaveDebouncer.swift` or the editor autosave path) with a deterministic 500 ms debounce persisting in a single transaction, decoupled from the 2-4 s sync debounce (T198); flush synchronously before window close, note deletion, auto-removal decisions (FR-012), and application quit; keep the revision-token/serialized-edit-session protection so a stale debounced write cannot clobber a newer structural edit; crash-loss contract per FR-141a verified by T229 per FR-141a / research R17-refined / plan §Auto-save / Constitution III/XII — **debounce exists (~300 ms); must be pinned to 500 ms with flush guarantees**
- [ ] T239 [US1] Implement zh-Hans + en localization per FR-180a — populate the String Catalogs (`App/Sources/Resources/` Localizable.xcstrings for zh-Hans + en) with ALL user-visible strings (menus, buttons, tooltips, toasts, settings, Help, accessibility labels, error/sync status text); switch follows the system language preference; note content is never translated; the deletion toast announced by VoiceOver (FR-009a) resolves from the active locale; audit `App/Sources/` for hard-coded UI strings and move them into the catalogs; localization completeness verified by T230 and SC-011 operability in both languages per FR-180a / plan §Localization / Constitution X/II — **catalogs planned (T008) but not bound to zh-Hans+en completeness**

**Checkpoint**: All ten binding clarifications from clarify sessions 4 & 5 have
test + implementation tasks. Tests T222–T230 must FAIL before T231–T239 are
implemented (Constitution XII). Phase 20 tasks depend on: T030 (NoteRepository
— extended by T231, T236), T167 (TrashView — extended by T231), T117
(SyncEngine — extended by T232), T031 (note contextual menu — extended by
T233), T034/T036 (note appearance/editor — extended by T234/T235), T087
(AssetStore — extended by T236), WidgetExtension (Phase 10 — refreshed by
T237), T037 (autosave path — pinned by T238), T008 (string catalogs — extended
by T239). None of these block Phase 3–13 work; they are additive convergence
tasks for the clarifications added in the fourth and fifth 2026-08-07
`/speckit-clarify` sessions.

**Implementation audit summary** (informs which tasks are verify-only vs
require changes):
- FR-014b (Empty Trash): ✗ not implemented — T222 verify, T231 implement
- FR-022b (sort-key LWW): ✗ no per-field divergence classification — T223 verify, T232 implement
- FR-031a (export/import): ✗ not implemented — T224 verify, T233 implement
- FR-040a (canonical hexes): ✗ colors unbound — T225 verify, T234 pin values
- FR-041a (opacity 40–100%): ✗ unbounded value — T225 verify, T234 constrain
- FR-050a (empty-block removal): ⚠ block deletion exists, no cursor-exit rule — T226 verify, T235 implement
- FR-090b (scale limits): ✗ no size caps — T227 verify, T236 implement
- FR-110a (change-driven refresh): ⚠ reload exists, not change-driven — T228 verify, T237 implement
- FR-141a (500 ms autosave): ⚠ debounce exists ~300 ms — T229 verify, T238 pin 500 ms + flush guarantees
- FR-180a (zh-Hans + en): ⚠ catalogs planned, not bound — T230 verify, T239 implement

## Phase 21: Convergence — FR-072b Large Todo Lists (virtualized + 99+)

**Purpose**: Cover the binding spec requirement **FR-072b** (editor + note-card
surfaces MUST gracefully handle notes with 100+ todo items: virtualized/lazy
rendering of the todo block view; the note card shows todo progress as
"completed/total", switching to "99+ completed" when the total exceeds 99;
sync handles large todo payloads with encryption/decryption off the main
actor). This FR was identified by `/speckit-analyze` as a coverage gap (zero
tasks referenced it). Tests are written FIRST and must FAIL (Constitution XII).

### Tests for Phase 21 (write FIRST, must FAIL) ⚠️

- [ ] T240 [P] [US4] EditorCore test: large todo list rendering per FR-072b — a note with 100+ (and 1,000+) todo items: assert the todo block view realizes only visible rows (bounded row-realization count regardless of total, virtualized/lazy rendering); assert scrolling remains smooth (no full-list re-render per frame) in `Packages/StickyCore/Tests/EditorCoreTests/LargeTodoListTests.swift` per FR-072b / spec §FR-072b / Constitution V/XI — **no existing task covers FR-072b**
- [ ] T241 [P] [US2] Domain test: card todo-progress format per FR-072b — assert the card progress string is "completed/total" (e.g. "12/45"); assert totals > 99 render as "99+ completed"; assert 0-completed and all-completed edge cases in `Packages/StickyCore/Tests/DomainTests/NoteCardProgressTests.swift` per FR-072b / spec §FR-072b / Constitution X
- [ ] T242 [P] [US9] SyncCore test: large todo payload per FR-072b — a note with 100+ todos syncs via the canonical note envelope with no special chunking; assert encryption/decryption of the large payload runs OFF the main actor in `Packages/StickyCore/Tests/SyncCoreTests/LargeTodoSyncTests.swift` per FR-072b / spec §FR-072b / Constitution VIII/XI

### Implementation for Phase 21

- [ ] T243 [US4] Implement virtualized todo list in `App/Sources/Features/Editor/TodoBlockView.swift` (extends T062) — realize only visible todo rows (bounded row realization for notes with 100+ items); keep the underlying scroll smooth for arbitrarily long todo lists; editing/toggling/reordering on unrealized rows works via stable todo UUIDs per FR-072b / spec §FR-072b / Constitution V/XI — **T062 realizes all rows**
- [ ] T244 [US2] Implement "99+ completed" card progress in `App/Sources/Features/Library/NoteCardView.swift` (extends T162) — render todo completion progress as "completed/total" (e.g. "12/45"); when the total exceeds 99 render "99+ completed" to avoid width overflow while preserving the progress signal per FR-072b / spec §FR-072b / Constitution X/XI — **T162 covers FR-020 indicators but not the 99+ rule**

**Checkpoint**: FR-072b has test + implementation tasks. Tests T240–T242 must
FAIL before T243–T244 are implemented (Constitution XII). Phase 21 depends on:
T062 (TodoBlockView — extended by T243), T162 (NoteCardView — extended by
T244), T117 (SyncEngine — verified by T242). Additive; blocks nothing in
Phases 3–13.

---

## Phase 22: Convergence — 2026-08-07 Post-Phase-16-19 Audit

**Purpose**: Close the three traceability gaps found in the post-Phase-16-19
convergence audit: **FR-009a** (one-time deletion toast + immediate window
close when a note with an open window is deleted — referenced in tasks.md
only in localization contexts T230/T239, never wired as behavior),
**FR-031** note-level contextual actions (duplicate note + copy note as
Markdown are untracked MUST actions of the FR-031 contextual menu; only
export/import T233 and move-to-Trash T167 are tracked), and the committed
`StickyNotes.xcodeproj` contradicting the "generated at build time, not
committed" declaration (T001/T173 vs actual repo/CI state). Tests are
written FIRST and must FAIL before implementation (Constitution XII).

- [ ] T245 [P] [US6] App integration test: FR-009a deletion toast + immediate window close — create a note, open its window, delete the note from the menu-bar library (and separately from Trash): assert the open note window closes immediately; assert a one-time, non-blocking, auto-dismissing transient toast announces the localized outcome ("Moved to Trash" / "Permanently Deleted") without blocking interaction or requiring dismissal; assert the deletion is NOT blocked by the open window and closing the window does NOT cancel the deletion; assert restoring from Trash does NOT auto-reopen the window (FR-007); assert the toast is VoiceOver-announceable and respects the active locale (FR-180a) in `AppTests/DeletionToastIntegrationTests.swift` per FR-009a / spec §Edge Cases / Constitution X/XII — **no task wires the FR-009a toast mechanism or its test**
- [ ] T246 [US6] Implement FR-009a deletion-toast + immediate window close in the library/Trash delete flows — when a note with an open window is deleted (to Trash or permanently) from `MenuBarLibraryScene` (T159) or `TrashView` (T167): immediately close the note's window(s) via `NoteWindowCoordinator` (T160) and present a one-time transient toast announcing the localized deletion outcome; the toast auto-dismisses within a short bounded period, never blocks interaction, and is announced by VoiceOver (localized per FR-180a); restoring from Trash never reopens the window in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (or a shared `DeletionToastPresenter` used by library + Trash) and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` per FR-009a / spec §Edge Cases / Constitution X/III — **the toast + immediate-close wiring is absent; delete paths are being built by T159/T167**
- [ ] T247 [P] [US1] [US3] Domain/EditorCore test: note duplicate + copy-as-Markdown per FR-031 — duplicating a note yields a new note UUID with byte-identical blocks, appearance (color, transparency, text size, Always-on-Top), and asset references; copy-as-Markdown serializes blocks (rich text with supported marks, todos with nesting/state, code blocks with preserved text, file-reference display names, screenshot/image captions) into Markdown text with no loss of round-trippable text content in `Packages/StickyCore/Tests/DomainTests/NoteDuplicateAndMarkdownCopyTests.swift` per FR-031 / spec §FR-031 / Constitution V/XII — **the note-level contextual actions "duplicate note" and "copy note as Markdown" (FR-031 MUST) have no task coverage**
- [ ] T248 [US1] [US3] Implement note-level contextual actions "duplicate note" + "copy note as Markdown" — extend the note contextual menu opened from the upper control area (`NoteControlsView`, T165) with: duplicate note (new note UUID, identical blocks + appearance + asset references, lifecycle active, fresh manual sort key per FR-022a) and copy note as Markdown (Markdown text of the note's blocks on the clipboard, serialization helper in `App/Sources/Features/NoteWindow/NoteExportImport.swift` or a small App-layer/EditorCore helper); export-note-as-JSON and move-to-Trash actions are already tracked by T233/T167 in `App/Sources/Features/NoteWindow/NoteExportImport.swift` per FR-031 / spec §FR-031 / Constitution V/X — **only export/import (T233) and move-to-Trash (T167) are tracked; duplicate + copy-as-Markdown are untracked MUST actions of FR-031**
- [ ] T249 Reconcile the committed `StickyNotes.xcodeproj` with the "generated at build time, not committed" declaration — `StickyNotes.xcodeproj/project.pbxproj` is committed in git and `.github/workflows/ci.yml` uses it directly with NO `xcodegen` step, while T001/T173 and `project.yml` declare the binary project is generated at build time and not committed; either (a) remove the committed `.xcodeproj`, add a `xcodegen generate` step to `ci.yml` + quickstart.md, and gitignore it, or (b) if committing is the chosen practice, update T001/T173, the `project.yml` header, and quickstart.md to document commit-and-regenerate with a CI drift check (regenerate + `git diff --exit-code`) in `.github/workflows/ci.yml`, `project.yml`, and `specs/001-sticky-notes-app/quickstart.md` per plan §Project Structure / Constitution IV (contradicts) — **the repo currently commits the generated project while declaring it uncommitted; CI cannot regenerate it today**

**Checkpoint**: FR-009a, the FR-031 contextual-menu actions, and the
xcodeproj contradiction have test + implementation (or reconciliation)
tasks. Tests T245/T247 must FAIL before T246/T248 are implemented
(Constitution XII). Phase 22 depends on: T159 (MenuBarLibraryScene —
extended by T246), T167 (TrashView — extended by T246), T160
(NoteWindowCoordinator — extended by T246), T165 (NoteControlsView —
extended by T248), T233 (NoteExportImport — extended by T248), T001/T173
(project generation model — reconciled by T249). Additive; blocks nothing
in Phases 3–21.
