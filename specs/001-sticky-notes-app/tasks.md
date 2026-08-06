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

- [ ] T001 Create Xcode workspace with macOS app target `App` and Widget Extension target `WidgetExtension` per plan.md §Project Structure
- [ ] T002 [P] Create local Swift package `Packages/StickyCore/Package.swift` declaring 7 library targets (Domain, Persistence, EditorCore, AssetStore, SecurityCore, SyncCore, SystemBridge) + 7 test targets with dependency direction from plan.md §Module boundaries
- [ ] T003 [P] Configure macOS 26 deployment target + Swift 6 language mode + strict concurrency + treat-warnings-as-errors for project-owned code in both Xcode project and Package.swift
- [ ] T004 Add GRDB.swift as a SwiftPM dependency pinned via Package.resolved; wire into Persistence target only
- [ ] T005 [P] Create App Group entitlement (`group.local.stickynotes.placeholder`) + sandbox + user-selected read/write in `App/Resources/StickyNotes.entitlements` and matching entry in `WidgetExtension/WidgetExtension.entitlements`
- [ ] T006 [P] Create `App/Resources/PrivacyInfo.xcprivacy` documenting screen-recording usage (capture) only, per constitution Principle VI
- [ ] T007 [P] Create String Catalogs `App/Resources/Localizable.xcstrings` with English + Simplified Chinese (zh-Hans) per plan.md §Localization
- [ ] T008 [P] Set up `Documentation/toolchain.md` recording the detected Xcode/Swift toolchain and macOS 26 minimum target per research.md R0
- [ ] T009 Create `.github/workflows/ci.yml` macOS runner with Xcode 26.x stages: dependency resolve, debug build, unit tests, migration tests, editor tests, security vectors, provider contract tests, sync tests, UI smoke, static warnings per plan.md §Testing and §Project Structure (.github/workflows/)
- [ ] T010 [P] Configure `.gitignore` to exclude App Group container, derived data, local credential/env files per quickstart.md §Avoiding committing secrets

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T011 [P] Define Domain value types: `Note`, `Block`, `TodoItem`, `Asset`, `FileReference`, `ScreenshotAssociation`, `Tombstone`, `DeviceIdentity`, `VaultConfiguration`, `WindowState` (device-local frame), `SyncState` (device-local vault run state), `SearchDocument` projection in `Packages/StickyCore/Sources/Domain/Models/` per data-model.md §Entities (Foundation-only, Sendable)
- [ ] T012 [P] Define Domain enums: `BlockKind`, `NoteColorKey`, `TextSize`, `NoteLifecycleState`, `FileAvailability`, `SyncVersionState` (per-entity sync lineage: unsynchronizedLocalModification/synchronizedVersion/divergentVersion/partialAssetSyncFailure per data-model.md §SyncVersionState) in `Packages/StickyCore/Sources/Domain/Models/Enums.swift`
- [ ] T013 [P] Define Domain version-lineage struct (`versionId`, `parentVersionId`, `lastModifiedDeviceId`, `modifiedAt`) + sort-key normalization rules (1024-gap) in `Packages/StickyCore/Sources/Domain/Models/VersionLineage.swift`
- [ ] T014 [P] Define canonical rich-text model (paragraph/run/scalar-offset, NFC, supported marks) in `Packages/StickyCore/Sources/Domain/Models/RichTextDocument.swift` conforming to contracts/rich-text.schema.json
- [ ] T015 [P] Define canonical note document + block payload types in `Packages/StickyCore/Sources/Domain/Models/CanonicalNote.swift` conforming to contracts/note-document.schema.json and contracts/block-payloads.schema.json
- [ ] T016 [P] Implement deterministic JSON encoding/decoding for canonical types (stable keys, ISO 8601 UTC, UUID strings, explicit schemaVersion) in `Packages/StickyCore/Sources/Domain/CanonicalCoding.swift`
- [ ] T017 Implement GRDB `DatabasePool` with WAL mode + bounded busy timeout in App Group container in `Packages/StickyCore/Sources/Persistence/DatabaseStore.swift`
- [ ] T018 Implement ordered migration framework + `schema_migrations` table in `Packages/StickyCore/Sources/Persistence/Migrations/Migrator.swift`; main app owns migrations
- [ ] T019 Create initial schema migration `v1` (all entities from data-model.md) in `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` with indexes from data-model.md §Indexes
- [ ] T020 [P] Implement FTS5 `notes_fts` table + indexing on note change in `Packages/StickyCore/Sources/Persistence/FullTextSearch.swift`
- [ ] T021 [P] Define repository protocols (NoteRepository, BlockRepository, TodoRepository, AssetRepository) in `Packages/StickyCore/Sources/Persistence/Repositories/` returning Sendable snapshots; concrete rows NOT exported as contracts
- [ ] T022 Implement integrity check + pre-migration backup + interrupted-migration recovery in `Packages/StickyCore/Sources/Persistence/Recovery.swift`
- [ ] T023 [P] Define typed error categories (Persistence, EditorConversion, AssetStorage, FileRefAccess, Capture, Permission, Encryption, Credentials, WebDAV, S3, SyncConflict, RemoteCorruption, SchemaCompatibility) in `Packages/StickyCore/Sources/Domain/Errors.swift`
- [ ] T024 [P] Define small `AppEnvironment` with explicit-initializer DI (composed services, no DI framework) in `App/Sources/App/AppEnvironment.swift`
- [ ] T025 [P] Define OSLog `Logger` wrappers with privacy annotations + sanitized error codes in `Packages/StickyCore/Sources/Domain/Logging.swift` per plan.md §Diagnostics

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 2.5: Milestone 0 Prototypes (Risk Gate)

**Purpose**: Validate highest-risk assumptions BEFORE broad feature work depends on them (plan.md §Milestone 0). This is a hard gate — user stories MUST NOT proceed until prototypes confirm feasibility.

- [ ] T025a Milestone 0 prototypes: SwiftUI rich-text + Chinese IME; Markdown single-Undo; one-window-per-note; per-window floating; App Group GRDB widget access; ScreenCaptureKit single-frame; native global shortcut; confirm Xcode 26.x/Swift 6.3 + integrate Argon2id per research.md R0–R18 in `Prototypes/` scratch directory outside the StickyCore package (no library/test target changes)

**Checkpoint**: Milestone 0 prototypes pass → high-risk assumptions de-risked; user stories may proceed.

---

## Phase 3: User Story 1 - Local Note Capture and Editing (Priority: P1) 🎯 MVP

**Goal**: User opens menu-bar library, creates a note, types, closes, reopens — content preserved without Save.

**Independent Test**: Click menu-bar icon → create note → type → close → reopen from library → verify text present and not duplicated.

### Tests for User Story 1 (write FIRST, must FAIL) ⚠️

- [ ] T026 [P] [US1] Migration test: fresh DB creation + v1 schema integrity in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift`
- [ ] T027 [P] [US1] Domain test: Note create/lifecycle + auto-discard empty note + preserve previously-content note when text empty in `Packages/StickyCore/Tests/DomainTests/NoteLifecycleTests.swift`
- [ ] T028 [P] [US1] Domain test: canonical Note round-trip JSON lossless in `Packages/StickyCore/Tests/DomainTests/CanonicalNoteTests.swift`
- [ ] T029 [US1] Integration test: create note → close without save → reopen → content preserved; one window per note, focus not duplicate in `AppTests/NoteCaptureIntegrationTests.swift`

### Implementation for User Story 1

- [ ] T030 [US1] Implement SQLite repository for Note + Block (CRUD, ordering) in `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift`
- [ ] T031 [P] [US1] Implement auto-save draft manager (debounce ~300ms, structural ops immediate, flush on focus-loss/close/terminate, revision tokens) in `Packages/StickyCore/Sources/EditorCore/AutoSave.swift`
- [ ] T032 [US1] Implement SwiftUI `MenuBarExtra` window-style library scene with search/sort/new/Trash/sync-status/Settings/Help/Quit affordances in `App/Sources/Features/Library/MenuBarLibraryScene.swift`
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

- [ ] T038 [P] [US2] Persistence test: FTS5 indexes title/summary/body/todos/code/fileNames/captions and updates transactionally in `Packages/StickyCore/Tests/PersistenceTests/FullTextSearchTests.swift`
- [ ] T039 [P] [US2] Performance test: search across 10,000 textual notes within 200ms in `Packages/StickyCore/Tests/PersistenceTests/SearchPerformanceTests.swift`
- [ ] T040 [P] [US2] Domain test: generated summary does not silently become permanent title in `Packages/StickyCore/Tests/DomainTests/GeneratedSummaryTests.swift`
- [ ] T041 [US2] Integration test: sort switch (modified/created/title/manual) + manual reorder persists in `AppTests/RetrievalIntegrationTests.swift`

### Implementation for User Story 2

- [ ] T042 [P] [US2] Implement search query + result update (active notes by default; privacy-excluded never revealed) in `Packages/StickyCore/Sources/Persistence/SearchService.swift`
- [ ] T043 [P] [US2] Implement manual-order sort key + reorder (1024-gap, normalize on collision) in `Packages/StickyCore/Sources/Domain/Models/ManualSort.swift`
- [ ] T044 [US2] Implement library search field + sort switcher UI with prompt result updates in `App/Sources/Features/Library/LibrarySearchView.swift`
- [ ] T045 [US2] Implement generated-summary derivation (first meaningful content as temporary display title) in `Packages/StickyCore/Sources/Domain/NoteSummary.swift`

**Checkpoint**: User Stories 1 AND 2 work independently

---

## Phase 5: User Story 3 - Note Appearance and Independent Windows (Priority: P1)

**Goal**: User keeps a note visible as a colored sheet, sets Always-on-Top, adjusts transparency/text-size; note remembers size/position; disconnected-display window recovery.

**Independent Test**: Open note → choose color → enable Always-on-Top → resize/move → close/reopen → verify appearance/on-top/size/position persist; disconnect display → window returns to main display, remembers disconnected-display frame.

### Tests for User Story 3 (write FIRST, must FAIL) ⚠️

- [ ] T046 [P] [US3] Domain test: color/transparency/textSize/alwaysOnTop persist per note in `Packages/StickyCore/Tests/DomainTests/NoteAppearanceTests.swift`
- [ ] T047 [P] [US3] Persistence test: WindowState (frame, preferredDisplayUUID, fallbackFrame) stored device-local, never synced in `Packages/StickyCore/Tests/PersistenceTests/WindowStateTests.swift`
- [ ] T048 [US3] SystemBridge test: window-frame correction moves off-screen window to visible display + preserves disconnected-display preferred frame in `Packages/StickyCore/Tests/SystemBridgeTests/WindowFrameCorrectionTests.swift`
- [ ] T049 [US3] Integration test: Always-on-Top per note; contrast readable across light/dark/custom-color/transparency/increased-contrast in `AppTests/AppearanceIntegrationTests.swift`

### Implementation for User Story 3

- [ ] T050 [P] [US3] Implement note appearance model (built-in colors Yellow/Pink/Purple/Blue/Green/Gray + custom) in `Packages/StickyCore/Sources/Domain/Models/NoteAppearance.swift`
- [ ] T051 [P] [US3] Implement WindowState repository (device-local) in `Packages/StickyCore/Sources/Persistence/Repositories/WindowStateRepository.swift`
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

- [ ] T056 [P] [US4] Domain test: TodoItem stable UUID across identical text/text-change/reorder (FR-071) + hierarchy validation (no cycles, depth bound, no orphaned children) in `Packages/StickyCore/Tests/DomainTests/TodoIdentityTests.swift`
- [ ] T057 [P] [US4] Domain test: code block preserves whitespace/tabs/line breaks; copy copies only code in `Packages/StickyCore/Tests/DomainTests/CodeBlockTests.swift`
- [ ] T058 [P] [US4] Domain test: FileReference syncs only generic metadata; FileLocator bookmark/paths never in canonical JSON in `Packages/StickyCore/Tests/DomainTests/FileReferenceTests.swift`
- [ ] T059 [US4] SystemBridge test: drag-out copies without deleting; explicit move requires command+destination+confirmation+verify-before-replace; missing file preserves card + relink; no filesystem scan in `Packages/StickyCore/Tests/SystemBridgeTests/FileReferenceAccessTests.swift`
- [ ] T060 [US4] Integration test: todo complete state communicated by more than color alone (strikethrough) in `AppTests/TodoCodeFileRefIntegrationTests.swift`

### Implementation for User Story 4

- [ ] T061 [P] [US4] Implement TodoItem repository (identity, hierarchy, sort-key, completion) in `Packages/StickyCore/Sources/Persistence/Repositories/TodoRepository.swift`
- [ ] T062 [P] [US4] Implement todo block view (complete/incomplete, drag reorder, indent/outdent, edit, delete, strikethrough) in `App/Sources/Features/Editor/TodoBlockView.swift`
- [ ] T063 [P] [US4] Implement code block view (monospaced, preserved whitespace, copy button, optional language label, wrap-or-scroll) in `App/Sources/Features/Editor/CodeBlockView.swift`
- [ ] T064 [P] [US4] Implement FileReference + FileLocator models per data-model.md in `Packages/StickyCore/Sources/Domain/Models/FileReference.swift`
- [ ] T065 [US4] Implement security-scoped bookmark access (balanced start/stop) + availability status + relink in `Packages/StickyCore/Sources/SystemBridge/SecurityScopedBookmarks.swift`
- [ ] T066 [US4] Implement file-reference card view (name/icon/size/date/availability/origin device) + open/reveal/copy-path/drag-out/move/relink/remove in `App/Sources/Features/Editor/FileReferenceCardView.swift`
- [ ] T067 [US4] Implement drag-out (copy, never move/delete) + explicit move (destination picker + confirmation + verify) in `Packages/StickyCore/Sources/SystemBridge/FileDragOutBridge.swift`

**Checkpoint**: User Stories 1–4 work independently

---

## Phase 7: User Story 5 - Markdown Input and Undo (Priority: P1)

**Goal**: Markdown shortcuts convert to formatting; single Undo restores exact syntax; no corruption of Chinese/IME composition.

**Independent Test**: Type each Markdown pattern → converts → Undo once → exact syntax returns; repeat with active Chinese IME composition.

### Tests for User Story 5 (write FIRST, must FAIL) ⚠️

- [ ] T068 [P] [US5] EditorCore test: line-level transforms (heading/bullet/todo/code-fence) trigger on space/confirm in `Packages/StickyCore/Tests/EditorCoreTests/MarkdownLineTransformTests.swift`
- [ ] T069 [P] [US5] EditorCore test: inline transforms (bold/italic/strike/inline-code) trigger after valid closing delimiter in `Packages/StickyCore/Tests/EditorCoreTests/MarkdownInlineTransformTests.swift`
- [ ] T070 [P] [US5] EditorCore test: single Undo restores exact Markdown syntax + formatting; unmatched delimiters ignored; no conversion inside code blocks except closing fence in `Packages/StickyCore/Tests/EditorCoreTests/MarkdownUndoTests.swift`
- [ ] T071 [P] [US5] EditorCore test: no corruption of Chinese IME marked text / mixed Chinese-English / emoji / partial syntax in `Packages/StickyCore/Tests/EditorCoreTests/IMECompositionTests.swift`
- [ ] T072 [P] [US5] EditorCore test: canonical rich-text round-trip lossless for supported marks; unsupported attributes stripped in `Packages/StickyCore/Tests/EditorCoreTests/RichTextRoundTripTests.swift`

### Implementation for User Story 5

- [ ] T073 [US5] Implement Markdown transformation state machine (line-level + inline, ignores unmatched, skips when IME marked text active, one undo group) in `Packages/StickyCore/Sources/EditorCore/MarkdownTransformer.swift`
- [ ] T074 [US5] Implement editor command layer over `UndoManager` (cursor placement after conversion) in `Packages/StickyCore/Sources/EditorCore/EditorCommands.swift`
- [ ] T075 [US5] Wire Markdown transforms into rich-text block view with IME-safe transformation decisions in `App/Sources/Features/Editor/RichTextBlockView.swift`

**Checkpoint**: User Stories 1–5 work independently

---

## Phase 8: User Story 6 - Trash and Deletion Lifecycle (Priority: P1)

**Goal**: Delete → Trash → restore or permanently delete; 30-day recovery; empty-note auto-discard but previously-content note never auto-deleted when emptied.

**Independent Test**: Delete a note → Trash → restore; permanently delete another; empty a note's text after it had content → not auto-deleted.

### Tests for User Story 6 (write FIRST, must FAIL) ⚠️

- [ ] T076 [P] [US6] Domain test: lifecycle transitions active→trashed→permanentlyDeleted; 30-day expiry; distinguish Trash/permanent/conflictCopy/active in `Packages/StickyCore/Tests/DomainTests/TrashLifecycleTests.swift`
- [ ] T077 [P] [US6] Domain test: never-contained-content note auto-discardable on close; previously-content note NOT auto-deleted when text empty in `Packages/StickyCore/Tests/DomainTests/EmptyNoteDiscardTests.swift`
- [ ] T078 [US6] Persistence test: Trash expiry scan + retention 30 days in `Packages/StickyCore/Tests/PersistenceTests/TrashExpiryTests.swift`

### Implementation for User Story 6

- [ ] T079 [P] [US6] Implement lifecycle state machine + trash/restore/permanent-delete in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift`
- [ ] T080 [US6] Implement Trash UI (list, restore, permanently delete, distinguish states) in `App/Sources/Features/Trash/TrashView.swift`
- [ ] T081 [US6] Implement empty-note auto-discard logic on window close in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift`

**Checkpoint**: All P1 user stories (1–6) work independently → MVP complete

---

## Phase 9: User Story 7 - Screenshot Capture and Clipboard Images (Priority: P2)

**Goal**: Capture region/window into new/existing note; paste clipboard image; view screenshots full-size; select cover. Static only; no live monitoring; no controlling original app.

**Independent Test**: Capture region into new note; add window screenshot to existing note; paste clipboard image; open viewer to zoom/copy/navigate; select cover.

### Tests for User Story 7 (write FIRST, must FAIL) ⚠️

- [ ] T082 [P] [US7] AssetStore test: atomic temp-write+rename, SHA-256 hash, verify-before-delete, orphan cleanup, dedup by contentHash in `Packages/StickyCore/Tests/AssetStoreTests/AssetStorageTests.swift`
- [ ] T083 [P] [US7] AssetStore test: thumbnail generated async, no original decode in card grid; lossless preferred for text window captures in `Packages/StickyCore/Tests/AssetStoreTests/ThumbnailTests.swift`
- [ ] T084 [P] [US7] Domain test: at most one cover screenshot per note (transactional); multiple screenshots allowed in `Packages/StickyCore/Tests/DomainTests/ScreenshotAssociationTests.swift`
- [ ] T085 [US7] SystemBridge test: ScreenCaptureKit single-frame capture; cancel cleanly without creating note/asset; no Accessibility prompt for ordinary capture in `Packages/StickyCore/Tests/SystemBridgeTests/CaptureTests.swift`
- [ ] T086 [US7] Integration test: screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate); opening screenshot does not activate original app in `AppTests/ScreenshotIntegrationTests.swift`

### Implementation for User Story 7

- [ ] T087 [P] [US7] Implement AssetStore: atomic writes, SHA-256, metadata transactions, cleanup queue, lazy loading, export/drag-out in `Packages/StickyCore/Sources/AssetStore/AssetStore.swift`
- [ ] T088 [P] [US7] Implement thumbnail generation + original/thumbnail/appIcon separation in `Packages/StickyCore/Sources/AssetStore/ThumbnailGenerator.swift`
- [ ] T089 [US7] Implement ScreenCaptureKit window capture via system content-sharing picker (single static frame, app name/icon/title/time, no retained stream) in `Packages/StickyCore/Sources/SystemBridge/WindowCapture.swift`
- [ ] T090 [US7] Implement region capture (single-frame + transparent multi-display selection overlay; Retina/multi-display/rotation/coordinate conversion; clean cancel) in `Packages/StickyCore/Sources/SystemBridge/RegionCapture.swift`
- [ ] T091 [US7] Implement screenshot block view + association metadata + cover selection in `App/Sources/Features/Editor/ScreenshotBlockView.swift`
- [ ] T092 [US7] Implement screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate) in `App/Sources/Features/Capture/ScreenshotViewer.swift`
- [ ] T093 [US7] Implement pasted-image block (embedded original, view/larger/copy/drag-out/save/remove) in `App/Sources/Features/Editor/EmbeddedImageBlockView.swift`

**Checkpoint**: User Stories 1–7 work independently

---

## Phase 10: User Story 8 - Widgets, Global Shortcuts, Dock, and Permissions (Priority: P2)

**Goal**: Add widgets; toggle todos from widget; configure global shortcuts; hide Dock while keeping functions reachable; permissions on-demand only.

**Independent Test**: Add each widget form; mark todo from widget; configure shortcut; disable Dock icon; verify Settings/Help/About/sync/Quit reachable; permission-denied fallbacks.

### Tests for User Story 8 (write FIRST, must FAIL) ⚠️

- [ ] T094 [P] [US8] Persistence test: widget reads App Group SQLite in short transactions; todo update atomic; schema-mismatch fallback without crash in `Packages/StickyCore/Tests/PersistenceTests/WidgetAccessTests.swift`
- [ ] T095 [P] [US8] Domain test: widget-ineligible note exposes nothing in timelines/previews/placeholders/snapshots/logs in `Packages/StickyCore/Tests/DomainTests/WidgetPrivacyTests.swift`
- [ ] T096 [US8] SystemBridge test: global shortcut registers/unregisters, fires while another app focused, detects registration failure, no Accessibility prompt in `Packages/StickyCore/Tests/SystemBridgeTests/GlobalShortcutTests.swift`
- [ ] T097 [US8] SystemBridge test: Dock activation-policy switch runtime; Settings/Help/About/sync/Quit remain reachable; widget deep-link does NOT flip Dock policy in `Packages/StickyCore/Tests/SystemBridgeTests/DockActivationTests.swift`
- [ ] T098 [US8] Integration test: permission-denied fallbacks (screen-recording denied → notes usable + explanation + open settings; accessibility denied → only advanced window-id unavailable) in `AppTests/PermissionFallbackIntegrationTests.swift`

### Implementation for User Story 8

- [ ] T099 [P] [US8] Implement WidgetExtension target: WidgetKit + SwiftUI; families per spec (small-selected, small-recent, medium-multi, medium-todo, large-overview, quick-create) in `WidgetExtension/StickyWidgetBundle.swift`
- [ ] T100 [P] [US8] Implement AppIntents (toggle todo by UUID, create note, open note, quick-create action per FR-110) + deep-link routing per contracts/deep-links.md in `WidgetExtension/WidgetIntents.swift` and `App/Sources/App/DeepLinkRouter.swift`
- [ ] T101 [P] [US8] Implement privacy-safe widget placeholders/snapshots + graceful handling of deleted/trashed/conflicted/unavailable configured notes in `WidgetExtension/WidgetSnapshots.swift`
- [ ] T102 [US8] Implement global shortcut adapter (native registration, no Accessibility, conflict detection, re-register) in `Packages/StickyCore/Sources/SystemBridge/GlobalShortcuts.swift`
- [ ] T103 [US8] Implement Dock activation-policy switching (regular↔accessory runtime, menu-bar access preserved) in `Packages/StickyCore/Sources/SystemBridge/DockActivationBridge.swift`
- [ ] T104 [US8] Implement permission service (screen-recording/accessibility status, feature explanation, request action, open-settings, denied recovery) in `Packages/StickyCore/Sources/SystemBridge/PermissionService.swift`
- [ ] T105 [US8] Implement Settings UI (global shortcuts config, Dock toggle, sync status entry, permissions) in `App/Sources/Features/Settings/SettingsView.swift`

**Checkpoint**: User Stories 1–8 work independently

---

## Phase 11: User Story 9 - Optional Encrypted Synchronization (Priority: P3)

**Goal**: Configure one WebDAV/S3 repo + sync password; notes replicate E2E-encrypted; provider cannot read content/metadata; local editing never waits.

**Independent Test**: Configure one repo → trigger manual sync → edit offline → reconnect → changes appear on another Mac; provider cannot read content.

### Tests for User Story 9 (write FIRST, must FAIL) ⚠️

- [ ] T106 [P] [US9] SecurityCore test: encryption test vectors (correct/wrong password, modified ciphertext/nonce/AAD, wrong object ID/type/vault, unsupported version, password re-wrap, Keychain unavailable, corrupt bootstrap) in `Packages/StickyCore/Tests/SecurityCoreTests/EncryptionVectorTests.swift`
- [ ] T107 [P] [US9] Provider contract test: shared suite both WebDAV + S3 pass (Put/Get/Head/conditional create/replace/failure/delete/missing/auth/server/timeout/cancellation/retry classification) in `Packages/StickyCore/Tests/SyncCoreTests/ProviderContractTests.swift`
- [ ] T108 [P] [US9] SyncCore test: initial upload/download, incremental update, partial asset upload, interrupted manifest commit, repeated retry, wrong password, remote corruption, network loss/restoration in `Packages/StickyCore/Tests/SyncCoreTests/SyncEngineTests.swift`
- [ ] T109 [US9] SyncCore test: no credentials/secrets, note content, file names/paths, window titles, screenshot captions, or todo text appear in logs or exported diagnostics (covers full FR-191 + SC-010 redaction scope) in `Packages/StickyCore/Tests/SyncCoreTests/DiagnosticsPrivacyTests.swift`
- [ ] T110 [US9] Domain test: remote object names opaque/random; no semantic type in filenames; manifest carries only opaque names+sizes/times in `Packages/StickyCore/Tests/DomainTests/RemoteLayoutTests.swift`

### Implementation for User Story 9

- [ ] T111 [P] [US9] Implement SecurityCore: Argon2id KEK, random master key, HKDF object keys, AES-GCM envelopes, Keychain access, secure random, fail-closed per contracts/vault-bootstrap.schema.json + encrypted-envelope.schema.json in `Packages/StickyCore/Sources/SecurityCore/`
- [ ] T112 [P] [US9] Implement vault bootstrap + onboarding (enable sync, join vault, wrong password, another-vault repo, create empty vault, upload existing notes, password change re-wrap) in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift`
- [ ] T113 [P] [US9] Implement provider-neutral repository protocol per contracts/provider-protocol.md in `Packages/StickyCore/Sources/SyncCore/ProviderProtocol.swift`
- [ ] T114 [P] [US9] Implement WebDAV adapter over URLSession (PROPFIND/MKCOL/GET/PUT/HEAD/DELETE, ETag/If-Match/If-None-Match, XML multistatus, HTTPS-only, self-signed pinning) in `Packages/StickyCore/Sources/SyncCore/WebDAVProvider.swift`
- [ ] T115 [P] [US9] Implement S3 SigV4 adapter over URLSession (configurable endpoint, path-style/virtual-host, compatibility: AWS/R2/MinIO/B2) in `Packages/StickyCore/Sources/SyncCore/S3Provider.swift`
- [ ] T116 [P] [US9] Implement normalized provider errors per contracts/provider-errors.md (fail-closed categories) in `Packages/StickyCore/Sources/SyncCore/ProviderErrors.swift`
- [ ] T117 [US9] Implement single-vault SyncActor (one transaction per vault; triggers ~3s/15min/startup/network-restore/manual/termination; idempotent steps; exponential backoff+jitter; conditional manifest commit) in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift`
- [ ] T118 [US9] Implement remote manifest handling + conditional replace + retry-on-precondition-failure per contracts/encrypted-manifest.schema.json in `Packages/StickyCore/Sources/SyncCore/ManifestStore.swift`
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
- [ ] T135 Performance tests: warm menu-bar presentation (SC-001), initial card load (SC-002), note-window creation (SC-003), typing latency incl. Chinese IME composition (SC-004), search 10k (SC-005), idle CPU (SC-006), offline no-degradation vs online (SC-007), no full-resolution decode in card grid (SC-008), save latency, thumbnail decode, sync pass, large-asset encryption, card-browsing memory, end-to-end capture loop <30s (SC-011) in `Packages/StickyCore/Tests/PersistenceTests/PerformanceBaselineTests.swift`
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
