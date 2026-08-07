# Tasks: macOS Sticky Notes

**Input**: `/specs/001-sticky-notes-app/` design docs.
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/.
**Tests**: MANDATORY (Constitution XII). Every user story includes test tasks written FIRST (fail before implementation).
**Organization**: Tasks grouped by user story for independent implementation/testing. Phases align with plan milestones (M0 prototypes → M1 local core → M2 system integration → M3 sync → M4 release). Seven `StickyCore` modules (Domain, Persistence, EditorCore, AssetStore, SecurityCore, SyncCore, SystemBridge) + App + WidgetExtension.

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: Parallelizable (different files, no dependencies on incomplete tasks)
- **[Story]**: User story (US1–US10)
- Include exact file paths in descriptions
- Tests written FIRST, must FAIL before implementation

## Path Conventions

Native macOS app. Repository layout (plan.md §Project Structure):

```text
App/Sources/{App,Features,Resources}
WidgetExtension/
Packages/StickyCore/Sources/{Domain,Persistence,EditorCore,AssetStore,SecurityCore,SyncCore,SystemBridge}
Packages/StickyCore/Tests/{DomainTests,PersistenceTests,EditorCoreTests,AssetStoreTests,SecurityCoreTests,SyncCoreTests,SystemBridgeTests}
AppTests/  AppUITests/  Documentation/  .github/workflows/
```

All paths repository-relative.

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

- [X] T025a Milestone 0 prototypes: SwiftUI rich-text + Chinese IME; Markdown single-Undo; one-window-per-note; per-window floating; App Group GRDB widget access; ScreenCaptureKit single-frame; native global shortcut; confirm Xcode 26.x/Swift 6.3 + integrate Argon2id per research.md R0–R18 in `Prototypes/` scratch directory outside the StickyCore package (no library/test target changes) — **partial (reconciled per T174)**: headless prototypes (MarkdownUndo, AppGroupGRDB, GlobalShortcut criteria 1–3, Argon2id) PASS and are verified; GUI prototypes (RichTextIME, WindowCoordinator, ScreenCapture) compile under Xcode-beta but their interactive verification is DEFERRED to a machine with a display, tracked as T158. The gate's GUI portion is not claimed complete (Constitution XII — no unverified completion claims).

**Checkpoint**: Milestone 0 prototypes pass → high-risk assumptions de-risked; user stories may proceed.

---

## Phase 3: User Story 1 - Local Note Capture and Editing (Priority: P1) 🎯 MVP

**Goal**: User opens menu-bar library, creates a note, types, closes, reopens — content preserved without Save.

**Independent Test**: Click menu-bar icon → create note → type → close → reopen from library → verify text present and not duplicated.

### Tests for User Story 1 (write FIRST, must FAIL) ⚠️

- [X] T026 [P] [US1] Migration test: fresh DB creation + v1 schema integrity (covers schema creation only; migration-recovery scenarios are in T153) in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift`
- [X] T027 [P] [US1] Domain test: Note create/lifecycle + auto-discard empty note + preserve previously-content note when text empty in `Packages/StickyCore/Tests/DomainTests/NoteLifecycleTests.swift`
- [X] T028 [P] [US1] Domain test: canonical Note round-trip JSON lossless in `Packages/StickyCore/Tests/DomainTests/CanonicalNoteTests.swift`
- [X] T029 [US1] Integration test: create note → close without save → reopen → content preserved; one window per note, focus not duplicate in `AppTests/NoteCaptureIntegrationTests.swift`

### Implementation for User Story 1

- [X] T030 [US1] Implement SQLite repository for Note + Block (CRUD, ordering) in `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift`
- [X] T031 [P] [US1] Implement auto-save draft manager (debounce ~300ms, structural ops immediate, flush on focus-loss/close/terminate, revision tokens) in `Packages/StickyCore/Sources/EditorCore/AutoSave.swift`
- [X] T032 [US1] Implement SwiftUI `MenuBarExtra` window-style library scene with search/sort/new/Trash/sync-status/Settings/Help/Quit affordances in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (create-blank-note entry per FR-010)
- [X] T033 [US1] Implement re-click behavior (focus if not focused, dismiss if focused, never second window) per FR-009 in `App/Sources/Features/Library/MenuBarLibraryScene.swift`
- [X] T034 [US1] Implement SwiftUI multi-window note scenes + `NoteWindowCoordinator` (open by UUID, one window per note, focus existing, flush pending edits before close, no reopen after relaunch) in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift`
- [X] T035 [US1] Implement AppKit bridge for `NSWindow` registration/focus/level in `Packages/StickyCore/Sources/SystemBridge/NoteWindowBridge.swift` (AppKit isolated here)
- [X] T036 [US1] Implement basic rich-text `TextEditor` block view + `RichTextAdapter` (SwiftUI attributed ↔ canonical ↔ plain text) in `App/Sources/Features/Editor/RichTextBlockView.swift` and `Packages/StickyCore/Sources/EditorCore/RichTextAdapter.swift`
- [X] T037 [US1] Implement card-grid note-card view in `App/Sources/Features/Library/NoteCardView.swift`

**Checkpoint**: User Story 1 fully functional and independently testable

---

## Phase 4: User Story 2 - Retrieval, Browsing, and Search (Priority: P1)

**Goal**: User searches across all active notes by any word, switches sort, finds notes with minimal effort.

**Independent Test**: Create several notes with varied titles/content → search a word appearing only in body/todo/code/filename → matching note appears; switch sort orders.

### Tests for User Story 2 (write FIRST, must FAIL) ⚠️

- [X] T038 [P] [US2] Persistence test: FTS5 indexes title/summary/body/todos/code/fileNames/captions and updates transactionally in `Packages/StickyCore/Tests/PersistenceTests/FullTextSearchTests.swift`
- [X] T039 [P] [US2] Performance test: search across 10,000 textual notes within 200ms in `Packages/StickyCore/Tests/PersistenceTests/SearchPerformanceTests.swift`
- [X] T040 [P] [US2] Domain test: generated summary does not silently become permanent title in `Packages/StickyCore/Tests/DomainTests/NoteSummaryTests.swift`
- [X] T041 [US2] Integration test: sort switch (modified/created/title/manual) + manual reorder persists in `AppTests/RetrievalIntegrationTests.swift`

### Implementation for User Story 2

- [X] T042 [P] [US2] Implement search query + result update (active notes by default; privacy-excluded never revealed) in `Packages/StickyCore/Sources/Persistence/SearchService.swift`
- [X] T043 [P] [US2] Implement manual-order sort key + reorder (1024-gap, normalize on collision) in `Packages/StickyCore/Sources/Domain/Models/VersionLineage.swift`
- [X] T044 [US2] Implement library search field + sort switcher UI with prompt result updates in `App/Sources/Features/Library/LibrarySearchView.swift`
- [X] T045 [US2] Implement generated-summary derivation (first meaningful content as temporary display title) in `Packages/StickyCore/Sources/Domain/NoteSummary.swift`

**Checkpoint**: User Stories 1 AND 2 work independently

---

## Phase 5: User Story 3 - Note Appearance and Independent Windows (Priority: P1)

**Goal**: User keeps a note visible as a colored sheet, sets Always-on-Top, adjusts transparency/text-size; note remembers size/position; disconnected-display window recovery.

**Independent Test**: Open note → choose color → enable Always-on-Top → resize/move → close/reopen → verify appearance/on-top/size/position persist; disconnect display → window returns to main display, remembers disconnected-display frame.

### Tests for User Story 3 (write FIRST, must FAIL) ⚠️

- [X] T046 [P] [US3] Domain test: color/transparency/textSize/alwaysOnTop persist per note in `Packages/StickyCore/Tests/DomainTests/NoteAppearanceTests.swift` — textSize portion superseded by FR-043a (enum→integer model, re-verified by T252/T257)
- [X] T047 [P] [US3] Persistence test: WindowState (frame, preferredDisplayUUID, fallbackFrame) stored device-local, never synced in `Packages/StickyCore/Tests/PersistenceTests/WindowStateTests.swift`
- [X] T048 [US3] SystemBridge test: window-frame correction moves off-screen window to visible display + preserves disconnected-display preferred frame in `Packages/StickyCore/Tests/SystemBridgeTests/WindowFrameCorrectionTests.swift`
- [X] T049 [US3] Integration test: Always-on-Top per note; contrast readable across light/dark/custom-color/transparency/increased-contrast in `AppTests/AppearanceIntegrationTests.swift`

### Implementation for User Story 3

- [X] T050 [P] [US3] Implement note appearance model (built-in colors Yellow/Pink/Purple/Blue/Green/Gray + custom) in `Packages/StickyCore/Sources/Domain/Models/NoteAppearance.swift`
- [X] T051 [P] [US3] Implement WindowState repository (device-local) in `Packages/StickyCore/Sources/Persistence/Repositories/WindowStateRepository.swift`
- [X] T052 [US3] Implement upper control area (title/color/transparency/textSize/Always-on-Top/screenshot/file-ref/actions/close) hidden until pointer enter in `App/Sources/Features/NoteWindow/NoteControlsView.swift`
- [X] T053 [US3] Implement per-window floating level via AppKit bridge in `Packages/StickyCore/Sources/SystemBridge/WindowLevelBridge.swift`
- [X] T054 [US3] Implement display connect/disconnect handling + frame restoration + fallback frame in `Packages/StickyCore/Sources/SystemBridge/DisplayChangeBridge.swift`
- [X] T055 [US3] Implement dynamic readable foreground colors + contrast adaptation (reject/adjust custom colors failing contrast) in `App/Sources/Features/NoteWindow/ReadableTheme.swift`

**Checkpoint**: User Stories 1–3 work independently

---

## Phase 6: User Story 4 - Todos, Code Blocks, and File References (Priority: P1)

**Goal**: User adds todos, inserts code blocks with copy, drops a Finder file as a reference openable/revealable without copying.

**Independent Test**: Add todos and toggle; insert code block and copy; drag a file into note then open/reveal from the note.

### Tests for User Story 4 (write FIRST, must FAIL) ⚠️

- [X] T056 [P] [US4] Domain test: TodoItem stable UUID across identical text/text-change/reorder (FR-071) + hierarchy validation (no cycles, depth bound ≤6 per FR-072a, no orphaned children). See also T189 for binding-value verification. in `Packages/StickyCore/Tests/PersistenceTests/TodoRepositoryTests.swift`
- [X] T057 [P] [US4] Domain test: code block preserves whitespace/tabs/line breaks; copy copies only code in `Packages/StickyCore/Tests/DomainTests/CodeBlockTests.swift`
- [X] T058 [P] [US4] Domain test: FileReference syncs only generic metadata; FileLocator bookmark/paths never in canonical JSON in `Packages/StickyCore/Tests/DomainTests/FileReferenceTests.swift`
- [X] T059 [US4] SystemBridge test: drag-out copies without deleting; explicit move requires command+destination+confirmation+verify-before-replace; missing file preserves card + relink; no filesystem scan in `Packages/StickyCore/Tests/SystemBridgeTests/FileReferenceAccessTests.swift`
- [X] T060 [US4] Integration test: todo complete state communicated by more than color alone (strikethrough) in `AppTests/TodoCodeFileRefIntegrationTests.swift`

### Implementation for User Story 4

- [X] T061 [P] [US4] Implement TodoItem repository (identity, hierarchy, sort-key, completion) in `Packages/StickyCore/Sources/Persistence/Repositories/TodoRepository.swift`
- [X] T062 [P] [US4] Implement todo block view (complete/incomplete, drag reorder, indent/outdent, edit, delete, strikethrough) in `App/Sources/Features/Editor/TodoBlockView.swift`
- [X] T063 [P] [US4] Implement code block view (monospaced, preserved whitespace, copy button, optional language label, wrap-or-scroll) in `App/Sources/Features/Editor/CodeBlockView.swift`
- [X] T064 [P] [US4] Implement FileReference + FileLocator models per data-model.md in `Packages/StickyCore/Sources/Domain/Models/FileReference.swift`
- [X] T065 [US4] Implement security-scoped bookmark access (balanced start/stop) + availability status + relink in `Packages/StickyCore/Sources/SystemBridge/SecurityScopedBookmarks.swift` → superseded by T166 (current)
- [X] T066 [US4] Implement file-reference card view (name/icon/size/date/availability/origin device) + open/reveal/copy-path/drag-out/move/relink/remove in `App/Sources/Features/Editor/FileReferenceCardView.swift` → superseded by T166 (current)
- [X] T067 [US4] Implement drag-out (copy, never move/delete) + explicit move (destination picker + confirmation + verify) in `Packages/StickyCore/Sources/SystemBridge/FileDragOutBridge.swift` → superseded by T166 (current)

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
- [X] T075 [US5] Wire Markdown transforms into rich-text block view with IME-safe transformation decisions in `App/Sources/Features/Editor/RichTextBlockView.swift` → superseded by T161 (current)

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
- [X] T080 [US6] Implement Trash UI (list, restore, permanently delete, distinguish states) in `App/Sources/Features/Trash/TrashView.swift` → superseded by T167 (current)
- [X] T081 [US6] Implement empty-note auto-discard logic on window close in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` → superseded by T167 (current)

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
- [X] T086 [US7] Integration test: screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate); opening screenshot does not activate original app in `AppTests/ScreenshotIntegrationTests.swift` → superseded by T163g (current)

### Implementation for User Story 7

- [X] T087 [P] [US7] Implement AssetStore: atomic writes, SHA-256, metadata transactions, cleanup queue, lazy loading, export/drag-out in `Packages/StickyCore/Sources/AssetStore/AssetStore.swift`
- [X] T088 [P] [US7] Implement thumbnail generation + original/thumbnail/appIcon separation in `Packages/StickyCore/Sources/AssetStore/ThumbnailGenerator.swift`
- [X] T089 [US7] Implement ScreenCaptureKit window capture via system content-sharing picker (single static frame, app name/icon/title/time, no retained stream) in `Packages/StickyCore/Sources/SystemBridge/WindowCapture.swift`
- [X] T090 [US7] Implement region capture (single-frame + transparent multi-display selection overlay; Retina/multi-display/rotation/coordinate conversion; clean cancel) in `Packages/StickyCore/Sources/SystemBridge/RegionCapture.swift`
- [X] T091 [US7] Implement screenshot block view + association metadata + cover selection in `App/Sources/Features/Editor/ScreenshotBlockView.swift` → superseded by T168 (current)
- [X] T092 [US7] Implement screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate) in `App/Sources/Features/Capture/ScreenshotViewer.swift` → superseded by T168 (current)
- [X] T093 [US7] Implement pasted-image block (embedded original, view/larger/copy/drag-out/save/remove) in `App/Sources/Features/Editor/EmbeddedImageBlockView.swift` → superseded by T168 (current)

**Checkpoint**: User Stories 1–7 work independently

---

## Phase 10: User Story 8 - Widgets, Global Shortcuts, Dock, and Permissions (Priority: P2)

**Goal**: Add widgets; toggle todos from widget; configure global shortcuts; hide Dock while keeping functions reachable; permissions on-demand only.

**Independent Test**: Add each widget form; mark todo from widget; configure shortcut; disable Dock icon; verify Settings/Help/About/sync/Quit reachable; permission-denied fallbacks.

### Tests for User Story 8 (write FIRST, must FAIL) ⚠️

- [X] T094 [P] [US8] Persistence test: widget reads App Group SQLite in short transactions; todo update atomic; schema-mismatch fallback without crash in `Packages/StickyCore/Tests/PersistenceTests/WidgetAccessTests.swift`
- [X] T095 [P] [US8] Domain test: widget-ineligible note exposes nothing in timelines/previews/placeholders/snapshots/logs in `Packages/StickyCore/Tests/DomainTests/WidgetPrivacyTests.swift`
- [X] T096 [US8] SystemBridge test: global shortcut registers/unregisters, fires while another app focused, detects registration failure, no Accessibility prompt in `Packages/StickyCore/Tests/SystemBridgeTests/ShortcutDockTests.swift` (consolidated with T097 — reconciled per T175)
- [X] T097 [US8] SystemBridge test: Dock activation-policy switch runtime; Settings/Help/About/sync/Quit remain reachable; widget deep-link does NOT flip Dock policy in `Packages/StickyCore/Tests/SystemBridgeTests/ShortcutDockTests.swift` (consolidated with T096 — reconciled per T175)
- [X] T098 [US8] Integration test: permission-denied fallbacks (screen-recording denied → notes usable + explanation + open settings; accessibility denied → only advanced window-id unavailable) in `AppTests/PermissionFallbackIntegrationTests.swift` → superseded by T163h (current)

### Implementation for User Story 8

- [X] T099 [P] [US8] Implement WidgetExtension target: WidgetKit + SwiftUI; families per spec (small-selected, small-recent, medium-multi, medium-todo, large-overview, quick-create) in `WidgetExtension/StickyWidgetBundle.swift` → superseded by T169 (current)
- [X] T100 [P] [US8] Implement AppIntents (toggle todo by UUID, create note, open note, quick-create action per FR-110) + deep-link routing per contracts/deep-links.md in `WidgetExtension/WidgetIntents.swift` and `App/Sources/App/DeepLinkRouter.swift` → superseded by T169 (current)
- [X] T101 [P] [US8] Implement privacy-safe widget placeholders/snapshots + graceful handling of deleted/trashed/conflicted/unavailable configured notes in `WidgetExtension/WidgetSnapshots.swift` → superseded by T169 (current)
- [X] T102 [US8] Implement global shortcut adapter (native registration, no Accessibility, conflict detection, re-register) in `Packages/StickyCore/Sources/SystemBridge/GlobalShortcuts.swift`
- [X] T103 [US8] Implement Dock activation-policy switching (regular↔accessory runtime, menu-bar access preserved) in `Packages/StickyCore/Sources/SystemBridge/DockActivationBridge.swift`
- [X] T104 [US8] Implement permission service (screen-recording/accessibility status, feature explanation, request action, open-settings, denied recovery) in `Packages/StickyCore/Sources/SystemBridge/PermissionService.swift`
- [X] T105 [US8] Implement Settings UI (global shortcuts config, Dock toggle, sync status entry, permissions) in `App/Sources/Features/Settings/SettingsView.swift` → superseded by T169 (current)

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
- [X] T119 [US9] Implement sync settings UI (configure/test/enable-disable/manual/last-success/errors/remove-without-deleting-local) + unrecoverable-password warning (FR-163) in `App/Sources/Features/Settings/SyncSettingsView.swift` → superseded by T170 (current)
- [X] T120 [US9] Implement sync status + non-blocking diagnostics in menu-bar library in `App/Sources/Features/Library/SyncStatusView.swift` → superseded by T170 (current)

**Checkpoint**: User Stories 1–9 work independently

---

## Phase 12: User Story 10 - Synchronization Conflicts and Remote Deletion (Priority: P3)

**Goal**: Two Macs diverge → original + labeled conflict copy; delete-vs-edit → recovered conflict copy; deletions propagate safely with 30-day tombstone.

**Independent Test**: Edit same note on two offline Macs → sync → both versions survive as original + conflict copy; delete on one while edit offline on other → edited content survives as recovered conflict copy.

### Tests for User Story 10 (write FIRST, must FAIL) ⚠️

- [X] T121 [P] [US10] SyncCore test: simultaneous edit → conflict copy; conflict deduplication (retry does not create unbounded duplicates) in `Packages/StickyCore/Tests/SyncCoreTests/ConflictCopyTests.swift` → superseded by T163k (current)
- [X] T122 [P] [US10] SyncCore test: delete-vs-edit → recovered conflict copy; not lost, not resurrected in `Packages/StickyCore/Tests/SyncCoreTests/DeleteEditConflictTests.swift` → superseded by T163l (current)
- [X] T123 [P] [US10] SyncCore test: tombstone lifecycle (offline <30d, >30d, device returning after remote cleanup, unknown devices, manual Trash empty) in `Packages/StickyCore/Tests/SyncCoreTests/TombstoneTests.swift` → superseded by T163m (current)
- [X] T124 [P] [US10] SyncCore test: long-offline device reconciles deletion history before uploading locally-deleted notes; not wall-clock last-modified-wins in `Packages/StickyCore/Tests/SyncCoreTests/LongOfflineTests.swift` → superseded by T163n (current)
- [X] T125 [US10] Domain test: distinguish Trash/permanent-deleted/recovered-conflict-copy/active in `Packages/StickyCore/Tests/DomainTests/NoteDistinguishabilityTests.swift` → superseded by T163o (current)

### Implementation for User Story 10

- [X] T126 [P] [US10] Implement note-level conflict model + deterministic dedup key `(originalNoteId, localVersionId, remoteVersionId)` per plan.md §Conflict model in `Packages/StickyCore/Sources/SyncCore/ConflictResolver.swift` → superseded by T171 (current)
- [X] T127 [P] [US10] Implement conflict-copy creation (new note UUID, label, preserve all blocks/assets/file-ref metadata, asset ref-count/dup, sync normally) in `Packages/StickyCore/Sources/SyncCore/ConflictCopyBuilder.swift` → superseded by T171 (current)
- [X] T128 [P] [US10] Implement tombstone store + 30-day sync-safety-gated retention per contracts/tombstone.schema.json + data-model.md §Tombstone lifecycle in `Packages/StickyCore/Sources/Persistence/Repositories/TombstoneRepository.swift` → superseded by T171 (current)
- [X] T129 [US10] Implement long-offline reconciliation (reconcile remote deletion history before upload; conservative unknown-remote handling) in `Packages/StickyCore/Sources/SyncCore/OfflineReconciler.swift` → superseded by T171/T184 (current)
- [X] T130 [US10] Implement conflict-copy labeling + distinguishability UI in library/Trash in `App/Sources/Features/Library/ConflictCopyView.swift` → superseded by T171 (current)

**Checkpoint**: All user stories (1–10) work independently

---

## Phase 13: Polish & Cross-Cutting Concerns

**Purpose**: Accessibility, localization, performance validation, documentation, release readiness (Milestone 4).

- [X] T131 [P] Accessibility: VoiceOver labels/actions + keyboard navigation + focus order + keyboard alternatives for hover controls + block/todo keyboard reorder/indent in `App/Sources/Features/Editor/Accessibility.swift`
- [X] T132 [P] Accessibility: announcements for todo-state changes + failed file access + failed capture; Increased Contrast + Reduce Motion + dynamic readable foreground in `App/Sources/Features/NoteWindow/AccessibilityAdaptations.swift`
- [X] T133 [P] Localization: locale-aware date/file-size formatters; language-neutral persisted enums/sync schemas; no localized strings as protocol identifiers in `App/Sources/Features/Shared/Formatters.swift`
- [X] T134 [P] Performance: lazy card-grid projections + bounded result loading + lazy thumbnail decode + signposts on measurable paths in `Packages/StickyCore/Sources/Persistence/CardProjection.swift` and `App/Sources/Features/Library/NoteCardView.swift`
- [X] T135 Performance tests: warm menu-bar presentation (SC-001), initial card load (SC-002), note-window creation (SC-003), typing latency incl. Chinese IME composition (SC-004/SC-004a), search 10k (SC-005/FR-024a), idle CPU (SC-006), offline no-degradation vs online (SC-007), no full-resolution decode in card grid (SC-008), save latency, thumbnail decode, sync pass, large-asset encryption, card-browsing memory, end-to-end capture loop <30s (SC-011) in `Packages/StickyCore/Tests/PersistenceTests/PerformanceBaselineTests.swift`
- [X] T135a [P] Independence gate test: verify SC-009 — run all P1 acceptance scenarios (US1-US6) with sync disabled, no widgets configured, no screenshots captured, no screen-recording permission granted; assert each P1 story is independently demonstrable without any P2/P3 feature configured in `AppTests/P1IndependenceGateTests.swift` per SC-009 / Constitution XIV
- [X] T136 [P] Documentation: architecture docs, privacy document (constitution VI), security policy, protocol docs, license compliance in `Documentation/`
- [X] T137 [P] Release: Developer ID signing + notarization workflow + GitHub release workflow; secrets in GitHub encrypted secrets only, never in repo files or fork PR workflows in `.github/workflows/release.yml`
- [X] T138 [P] Regression tests for fixed defects accumulated across stories in `AppTests/RegressionTests.swift`
- [X] T139 [P] Real-service compatibility tests (opt-in, credentialed): standards-compliant WebDAV, MinIO, one hosted S3-compatible, AWS S3 — never commit credentials per quickstart.md in `Packages/StickyCore/Tests/SyncCoreTests/RealServiceCompatibilityTests.swift`
- [X] T141 [US1] [US6] XCUITest critical UI journeys: menu-bar open/dismiss/re-click (FR-009); note create/open/focus-existing-not-duplicate/close (FR-005/FR-006); Trash restore + permanent delete (FR-014); screenshot viewer open does not activate original app (FR-095) in `AppUITests/CriticalFlowsUITests.swift` per constitution XII
- [X] T142 [P] [US3] Implement global font preference (Chinese + English with fallback) in Settings + Domain `FontPreference` model per FR-043 in `Packages/StickyCore/Sources/Domain/Models/FontPreference.swift` and `App/Sources/Features/Settings/FontPreferenceView.swift`
- [X] T143 [P] [US1] [US5] Implement auto-link detection (web URLs, email addresses, telephone numbers) feeding canonical rich-text `link` mark per FR-050 in `Packages/StickyCore/Sources/EditorCore/AutoLinkDetector.swift`
- [X] T144 [P] [US8] Implement About panel reachable from menu-bar interface (covers FR-008 About reachability when Dock disabled) in `App/Sources/Features/About/AboutView.swift`
- [X] T145 [US8] Implement "new note from clipboard" global-shortcut handler (FR-120) reusing pasted-image logic in `Packages/StickyCore/Sources/SystemBridge/GlobalShortcuts.swift` and `App/Sources/App/DeepLinkRouter.swift`
- [X] T146 [P] [US3] Configure `NSWindow.collectionBehavior` so note windows do not appear across every Space and do not force over full-screen applications (FR-035) in `Packages/StickyCore/Sources/SystemBridge/NoteWindowBridge.swift`
- [X] T147 [P] [US3] Domain test: FontPreference persistence + Chinese/English fallback selection for unsupported glyphs per FR-043 in `Packages/StickyCore/Tests/DomainTests/FontPreferenceTests.swift`
- [X] T148 [P] [US1] [US5] EditorCore test: auto-link detection recognizes web URLs, email addresses, telephone numbers; emits canonical rich-text `link` mark; no false positives inside code blocks per FR-050 in `Packages/StickyCore/Tests/EditorCoreTests/AutoLinkDetectorTests.swift`
- [X] T149 [US8] Integration test: About panel reachable from menu-bar interface with Dock disabled (FR-008) in `AppTests/AboutReachabilityIntegrationTests.swift`
- [X] T150 [US8] SystemBridge test: "new note from clipboard" global shortcut fires while another app is focused and creates a note with clipboard contents (FR-120) in `Packages/StickyCore/Tests/SystemBridgeTests/ClipboardNoteShortcutTests.swift`
- [X] T151 [US3] SystemBridge test: note window `collectionBehavior` prevents appearance across every Space and prevents forcing over full-screen applications (FR-035) in `Packages/StickyCore/Tests/SystemBridgeTests/WindowSpaceBehaviorTests.swift`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately.
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories.
- **Milestone 0 Prototypes (Phase 2.5)**: HARD GATE after Foundational, before ANY user story (plan.md §Milestone 0).
- **User Stories (Phase 3–12)**: All depend on Foundational.
  - P1 (US1–US6): priority order or parallel.
  - P2 (US7–US8): Foundational + relevant P1 surface (US7 reuses AssetStore + note windows; US8 reuses Domain/Persistence + note windows).
  - P3 (US9–US10): Foundational + Domain canonical types; US10 depends on US9 sync engine.
- **Polish (Phase 13)**: Depends on all desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: After Foundational — no story deps. **MVP**.
- **US2 (P1)**: After Foundational — may reuse US1 Note/Card views, independently testable.
- **US3 (P1)**: After Foundational — independent (note windows).
- **US4 (P1)**: After Foundational — independent (todos/code/file-refs).
- **US5 (P1)**: After Foundational — depends on US1 rich-text block view (RichTextAdapter).
- **US6 (P1)**: After Foundational — may reuse US1 lifecycle fields, independently testable.
- **US7 (P2)**: After Foundational + US1 (note windows/blocks) — reuses AssetStore.
- **US8 (P2)**: After Foundational + US1 (note open/deep-link) — reuses Domain/Persistence.
- **US9 (P3)**: After Foundational + Domain canonical types — independent of UI stories.
- **US10 (P3)**: After US9 (sync engine) — conflict/tombstone built on sync.

### Within Each User Story

- Tests FIRST, must FAIL before implementation (Constitution XII).
- Models/domain → services → UI; core → integration.
- Story complete (checkpoint reached) before next priority.

### Parallel Opportunities

- All Phase 1/2 `[P]` tasks (different files) run in parallel.
- Within a story, `[P]` test tasks and `[P]` models run in parallel.
- Different stories parallelizable by different contributors once Foundational completes (mind US5→US1, US7→US1, US8→US1, US10→US9 couplings).
- Across stories, `[P]` tasks touching distinct modules (e.g., US9 SecurityCore/SyncCore vs US7 AssetStore) run in parallel.

---

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1: Setup → 2. Phase 2: Foundational (CRITICAL — blocks all stories) → 3. Phase 2.5: Milestone 0 prototypes (hard risk gate) → 4. Phase 3: US1 (capture/edit/reopen/no-save/one-window) → 5. **STOP and VALIDATE**: Test US1 independently — MVP delivered.

### Incremental Delivery

1. Setup + Foundational → Foundation ready.
2. Milestone 0 prototypes (Phase 2.5) → de-risk high-assumption areas.
3. Add US1 → Test → MVP.
4. Add US2–US6 (P1) → each tested independently → full local core (Milestone 1).
5. Add US7–US8 (P2) → system integration (Milestone 2).
6. Add US9–US10 (P3) → encrypted sync (Milestone 3).
7. Polish + release (Milestone 4).

### Parallel Team Strategy

1. Team completes Setup + Foundational together.
2. Once Foundational done, assign by priority and coupling:
   - A: US1 → US5 (rich-text coupling)
   - B: US2 + US6 (lifecycle/search)
   - C: US3 + US4 (windows/todos/code/file-refs)
   - D: US7 (assets/capture) once US1 lands
   - E: US8 (widgets/shortcuts/permissions) once US1 lands
   - F: US9 → US10 (sync) — independent of UI stories, can start after Foundational

---

## Notes

- `[P]` = different files, no dependencies on incomplete tasks.
- `[Story]` = user story traceability to spec.md.
- Tests FIRST per story (Constitution XII; mandatory, not optional).
- File paths reference plan.md §Project Structure (App/, WidgetExtension/, Packages/StickyCore/Sources|Tests/).
- Verify each checkpoint before moving on; stop at any checkpoint to validate a story independently.
- Milestone 0 prototypes (T025a) validate high-risk assumptions per research.md R0–R18 before broad feature work depends on them.

---

## Phase 14: Convergence

- [X] T152 Enforce `Note.coverScreenshotBlockId → Block.id` FK in v1 schema in `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` (详情见 history/tasks-log.md)
- [X] T153 Add migration-recovery tests covering `StickyMigrator` pre-migration backup in `Packages/StickyCore/Tests/PersistenceTests/MigrationTests.swift` (详情见 history/tasks-log.md)
- [X] T154 Wire `StickyMigrator` + `MigrationRecovery.recoverFromInterruptedMigration` (详情见 history/tasks-log.md)
- [X] T155 Complete the Milestone 0 prototype hard gate (T025a): build SwiftUI rich-text prototypes (详情见 history/tasks-log.md)
- [X] T156 Review `Packages/StickyCore/Sources/Persistence/TempDatabasePaths.swift` (详情见 history/tasks-log.md)
- [X] T157 Fix stale FTS5 comment in `Packages/StickyCore/Sources/Persistence/Migrations/m0001_initial.swift` (详情见 history/tasks-log.md)
- [ ] T158 Interactive verification of Milestone 0 GUI prototypes (T025a gate remainder) — run `RichTextIMEPrototype`, `WindowCoordinatorPrototype`, `ScreenCapturePrototype` on a Mac with a display under `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run …` per `Prototypes/README.md`. Each prototype prints its own PASS/FAIL. Record results and flip T025a's partial note to fully verified. Explicit gate for the GUI portion of T025a unverifiable by headless compilation alone.

---

## Phase 15: Convergence

> **Note**: Tasks T159-T172 supersede and consolidate the corresponding Phase 3-12 tasks (T032-T119) that remain `[ ]`. The Phase 3-12 originals are retained for historical traceability; the convergence tasks are authoritative and should be executed in their place.

- [X] T159 Implement SwiftUI `MenuBarLibraryScene.swift` (search/sort/new/Trash/sync-status/Settings/Help/Quit affordances) + FR-009 re-click behavior (focus if not focused, dismiss if focused, never second window) per FR-001/FR-003/FR-004/FR-009/US1/AC1,AC6 in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (missing — dir empty; `StickyNotesApp.swift:40-58` ships only a stub `MenuBarExtra`)
- [X] T160 Implement `NoteWindowCoordinator.swift` (open by UUID, one window per note, focus existing not duplicate, flush pending edits before close, no reopen after relaunch) + `NoteWindowBridge.swift` (AppKit NSWindow registration/focus/level isolated in SystemBridge) per FR-005/FR-006/FR-007/FR-007a/US1/AC2-5 in `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` and `Packages/StickyCore/Sources/SystemBridge/NoteWindowBridge.swift` (missing — dir empty; deferred from T034; FR-007a: new note window receives keyboard focus immediately, library stays open without focus, global-shortcut creation activates the app)
- [X] T161 Implement `RichTextBlockView.swift` (SwiftUI `TextEditor` + `AttributedString` rich-text block) + `RichTextAdapter.swift` (SwiftUI attributed ↔ canonical ↔ plain text, IME-safe Markdown transform wiring) per FR-050/FR-051/FR-052/FR-053/FR-060/FR-061/FR-062/FR-063/US1/AC3/US5 in `App/Sources/Features/Editor/RichTextBlockView.swift` and `Packages/StickyCore/Sources/EditorCore/RichTextAdapter.swift` (missing — dir empty; EditorCore has Markdown/AutoSave/EditorCommands but no adapter connecting SwiftUI attributed state to the canonical rich-text model)
- [X] T162 Implement `NoteCardView.swift` (compact card-grid card: manual title / generated summary, short body preview, note color, last-modified, todo progress, screenshot/image/file-ref indicators, conflict/sync warning) per FR-002/FR-002a/FR-020/FR-021/US1/US2 in `App/Sources/Features/Library/NoteCardView.swift` (missing — dir empty; card-grid library surface absent)
- [X] T163a [P] [US1] Create `AppTests/NoteCaptureIntegrationTests.swift` per T029 — create note → close without save → reopen → content preserved; one window per note, focus not duplicate; FR-007a new-note-window focus; Constitution XII
- [X] T163b [P] [US2] Create `AppTests/RetrievalIntegrationTests.swift` per T041 — sort switch (modified/created/title/manual) + manual reorder persists; Constitution XII
- [X] T163c [P] [US3] Create `Packages/StickyCore/Tests/SystemBridgeTests/WindowFrameCorrectionTests.swift` per T048 — window-frame correction moves off-screen window to visible display + preserves disconnected-display preferred frame; Constitution XII
- [X] T163d [P] [US3] Create `AppTests/AppearanceIntegrationTests.swift` per T049 — Always-on-Top per note; contrast readable across light/dark/custom-color/transparency/increased-contrast; Constitution XII
- [X] T163e [P] [US4] Create `Packages/StickyCore/Tests/SystemBridgeTests/FileReferenceAccessTests.swift` per T059 — drag-out copies without deleting; explicit move requires command+destination+confirmation+verify; missing file preserves card + relink; no filesystem scan; Constitution XII
- [X] T163f [P] [US4] Create `AppTests/TodoCodeFileRefIntegrationTests.swift` per T060 — todo complete state communicated by more than color alone (strikethrough); Constitution XII
- [X] T163g [P] [US7] Create `AppTests/ScreenshotIntegrationTests.swift` per T086 — screenshot viewer (zoom/actual/fit/copy/drag-out/SaveAs/delete/edit-caption/navigate); opening screenshot does not activate original app; Constitution XII
- [X] T163h [P] [US8] Create `AppTests/PermissionFallbackIntegrationTests.swift` per T098 — permission-denied fallbacks (screen-recording denied → notes usable + explanation + open settings; accessibility denied → only advanced window-id unavailable); Constitution XII
- [X] T163i [P] Create `AppTests/RegressionTests.swift` per T138 — regression tests for fixed defects accumulated across stories; Constitution XII
- [X] T163j [P] Create `AppUITests/CriticalFlowsUITests.swift` per T141 — XCUITest: menu-bar open/dismiss/re-click (FR-009); note create/open/focus-existing-not-duplicate/close (FR-005/FR-006); Trash restore + permanent delete (FR-014); screenshot viewer open does not activate original app (FR-095); Constitution XII
- [X] T163k [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/ConflictCopyTests.swift` per T121 — simultaneous edit → conflict copy; conflict deduplication (retry does not create unbounded duplicates); Constitution XII
- [X] T163l [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/DeleteEditConflictTests.swift` per T122 — delete-vs-edit → recovered conflict copy; not lost, not resurrected; Constitution XII
- [X] T163m [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/TombstoneTests.swift` per T123 — tombstone lifecycle (offline <30d, >30d, device returning after remote cleanup, unknown devices, manual Trash empty); Constitution XII
- [X] T163n [P] [US10] Create `Packages/StickyCore/Tests/SyncCoreTests/LongOfflineTests.swift` per T124 — long-offline device reconciles deletion history before uploading locally-deleted notes; not wall-clock last-modified-wins; Constitution XII
- [X] T163o [P] [US10] Create `Packages/StickyCore/Tests/DomainTests/NoteDistinguishabilityTests.swift` per T125 — distinguish Trash/permanent-deleted/recovered-conflict-copy/active; Constitution XII
- [X] T163p [P] Create `Packages/StickyCore/Tests/PersistenceTests/PerformanceBaselineTests.swift` per T135 — performance tests: SC-001-SC-008, SC-011; Constitution XII
- [X] T163q [P] Create `Packages/StickyCore/Tests/DomainTests/FontPreferenceTests.swift` per T147 — FontPreference persistence + Chinese/English fallback selection per FR-043; Constitution XII
- [X] T163r [P] Create `Packages/StickyCore/Tests/EditorCoreTests/AutoLinkDetectorTests.swift` per T148 — auto-link detection (web URLs, email, telephone) → canonical rich-text `link` mark; no false positives inside code blocks per FR-050; Constitution XII
- [X] T164 Implement `LibrarySearchView.swift` (search field + sort switcher among Recently Modified/Created/Title/Manual with prompt result updates) per FR-022/FR-022a/FR-023/FR-023a/FR-024/FR-024a/US2/AC1,AC2 in `App/Sources/Features/Library/LibrarySearchView.swift` (missing — dir empty; SearchService exists in Persistence but no UI consumes it)
- [X] T165 Implement `NoteControlsView.swift` (upper control area: title/color/transparency/textSize/Always-on-Top/screenshot/file-ref/actions/close, hidden until pointer enter) + `WindowLevelBridge.swift` (per-window floating level via AppKit) + `DisplayChangeBridge.swift` (display connect/disconnect handling + frame restoration + fallback frame preserving disconnected-display preferred frame) + `ReadableTheme.swift` (dynamic readable foreground colors + contrast adaptation, reject/adjust custom colors failing contrast) per FR-030/FR-030a/FR-031/FR-032/FR-033/FR-034/FR-035/FR-042/FR-044/US3 in `App/Sources/Features/NoteWindow/{NoteControlsView,ReadableTheme}.swift` and `Packages/StickyCore/Sources/SystemBridge/{WindowLevelBridge,DisplayChangeBridge}.swift` (missing — dirs empty; SystemBridge has no window-level/display-change bridges)
- [X] T166 Implement `TodoBlockView.swift` (complete/incomplete with strikethrough beyond color alone, drag reorder, indent/outdent, edit, delete) + `CodeBlockView.swift` (monospaced, preserved whitespace, copy button copying only code, optional language label, wrap-or-scroll) + `FileReferenceCardView.swift` (name/icon/size/date/availability/origin device + open/reveal/copy-path/drag-out/move/relink/remove) + `SecurityScopedBookmarks.swift` (balanced start/stop security-scoped access + availability status + relink) + `FileDragOutBridge.swift` (drag-out copies never move/delete + explicit move with destination picker + confirmation + verify-before-replace-bookmark) per FR-070/FR-072a/FR-080/FR-081/FR-082/FR-100/FR-101/FR-102/FR-103/FR-104/FR-105/US4 in `App/Sources/Features/Editor/{TodoBlockView,CodeBlockView,FileReferenceCardView}.swift` and `Packages/StickyCore/Sources/SystemBridge/{SecurityScopedBookmarks,FileDragOutBridge}.swift` (missing — dirs empty; SystemBridge has no security-scoped bookmark or drag-out bridge)
- [X] T167 Implement `TrashView.swift` (list Trash, restore, permanently delete, distinguish Trash/permanent-deleted/recovered-conflict-copy/active states) + wire empty-note auto-discard logic on window close in `NoteWindowCoordinator` (never-content note MAY be auto-removed; previously-content note MUST NOT be auto-deleted when text empty) per FR-014/FR-014a/FR-175/US6/AC3,AC4,AC5 in `App/Sources/Features/Trash/TrashView.swift` and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` (missing — dir empty; NoteWindowCoordinator (T160) does not yet exist to host the auto-discard hook; lifecycle operations per FR-011)
- [X] T168 Implement `ScreenshotBlockView.swift` (screenshot association metadata + cover selection, at most one cover per note transactional) + `ScreenshotViewer.swift` (zoom/actual-size/fit-to-window/copy/drag-out/Save-As/delete-association/edit-caption/navigate between screenshots of same note; viewer MUST NOT auto-start/switch/control original app) + `EmbeddedImageBlockView.swift` (embedded clipboard image original: view/larger/copy/drag-out/save-elsewhere/remove) per FR-090/FR-090a/FR-091/FR-092/FR-093/FR-094/FR-094a/FR-095/FR-096/US7 in `App/Sources/Features/Editor/{ScreenshotBlockView,EmbeddedImageBlockView}.swift` and `App/Sources/Features/Capture/ScreenshotViewer.swift` (missing — dirs empty)
- [X] T169 Implement WidgetExtension target sources: `StickyWidgetBundle.swift` (WidgetKit + SwiftUI; families per spec: small-selected, small-recent, medium-multi, medium-todo, large-overview, quick-create action) + `WidgetIntents.swift` (AppIntents: toggle todo by UUID, create note, open note, quick-create per FR-110) + `WidgetSnapshots.swift` (privacy-safe placeholders/snapshots + graceful handling of deleted/trashed/conflicted/unavailable configured notes) + `DeepLinkRouter.swift` in App (URL routing `stickynotes://note/<uuid>`, `stickynotes://new`, `stickynotes://search` per contracts/deep-links.md) + `SettingsView.swift` (global shortcuts config, Dock toggle, sync status entry, permissions) per FR-110/FR-111/FR-112/FR-120/FR-121/FR-130/FR-131/FR-132/FR-133/FR-134/US8 in `WidgetExtension/{StickyWidgetBundle,WidgetIntents,WidgetSnapshots}.swift` and `App/Sources/App/DeepLinkRouter.swift` and `App/Sources/Features/Settings/SettingsView.swift` (missing — WidgetExtension has only Info.plist + entitlements; Settings dir empty)
- [X] T170 Implement `SyncSettingsView.swift` (configure/test/enable-disable automatic/manual sync/view last-successful-time/view actionable errors/remove local config without deleting local notes + clear unrecoverable-password warning per FR-163) + `SyncStatusView.swift` (non-blocking sync status + sanitized diagnostics in menu-bar library; credentials/unlocked secrets never in logs or exported diagnostics per FR-165) per FR-150/FR-151/FR-152/FR-152a/FR-153/FR-154/FR-160/FR-162/FR-163/FR-164/FR-165/US9/AC1,AC4 in `App/Sources/Features/Settings/SyncSettingsView.swift` and `App/Sources/Features/Library/SyncStatusView.swift` (missing — dirs empty; SyncEngine exists in SyncCore but no UI consumes it)
- [X] T171 Implement `ConflictResolver.swift` (note-level conflict model + deterministic dedup key `(originalNoteId, localVersionId, remoteVersionId)` so retry does not create unbounded duplicates; NO automatic character/block merging) + `ConflictCopyBuilder.swift` (create new note UUID for divergent version, label with origin/time, preserve text/todos/code/images/screenshots/file-reference metadata, asset ref-count/dup, sync normally) + `TombstoneRepository.swift` (tombstone store + 30-day sync-safety-gated retention per contracts/tombstone.schema.json) + `OfflineReconciler.swift` (long-offline device reconciles remote deletion history before uploading locally-deleted notes; conservative unknown-remote handling; not wall-clock last-modified-wins) + `ConflictCopyView.swift` (conflict-copy labeling + distinguishability in library/Trash) per FR-170/FR-171/FR-172/FR-173/FR-174/FR-175/US10 in `Packages/StickyCore/Sources/SyncCore/{ConflictResolver,ConflictCopyBuilder,OfflineReconciler}.swift`, `Packages/StickyCore/Sources/Persistence/Repositories/TombstoneRepository.swift`, and `App/Sources/Features/Library/ConflictCopyView.swift` (missing — none exist; US10 implementation entirely absent)
- [X] T172 Implement Phase 13 polish & cross-cutting: `Accessibility.swift` (VoiceOver labels/actions, keyboard navigation, focus order, keyboard alternatives for hover controls, block/todo keyboard reorder/indent) + `AccessibilityAdaptations.swift` (announcements for todo-state changes/failed file access/failed capture; Increased Contrast + Reduce Motion + dynamic readable foreground) + `Formatters.swift` (locale-aware date/file-size formatters; language-neutral persisted enums/sync schemas) + `CardProjection.swift` (lazy card-grid projections + bounded result loading in Persistence) + lazy thumbnail decode + signposts on measurable paths in `NoteCardView.swift` + `AboutView.swift` (About panel reachable from menu-bar interface, covers FR-008 when Dock disabled) + `FontPreference.swift` Domain model + `FontPreferenceView.swift` (global font preference Chinese+English with fallback per FR-043) + `AutoLinkDetector.swift` (auto-link detection for web URLs/email/telephone feeding canonical rich-text `link` mark per FR-050) + `.github/workflows/release.yml` (Developer ID signing + notarization + GitHub release workflow; secrets in GitHub encrypted secrets only) per FR-008/FR-043/FR-050/FR-051/FR-052/FR-052a/FR-053/FR-061/FR-062/FR-180/FR-181/FR-182/SC-001-SC-011/Constitution VI/XII in `App/Sources/Features/{Editor/Accessibility,NoteWindow/AccessibilityAdaptations,Shared/Formatters,About/AboutView,Settings/FontPreferenceView}.swift`, `Packages/StickyCore/Sources/{Persistence/CardProjection,Domain/Models/FontPreference,EditorCore/AutoLinkDetector}.swift`, and `.github/workflows/release.yml` (missing — App/Features/{About,Shared,Editor,NoteWindow} empty; CardProjection/FontPreference/AutoLinkDetector absent; release workflow absent)
- [X] T173 Reconciled: T001 updated to reflect `project.yml` as source of truth; `StickyNotes.xcodeproj` committed with documented regenerate-and-drift-check practice per FR-008 (详情见 history/tasks-log.md)
- [X] T174 Reconcile T025a/T158 status — **resolved 2026-08-07 (option b)**: T025a is marked `[X]` with an explicit partial note stating the GUI interactive verification is deferred to T158; the Milestone 0 gate's GUI portion is NOT claimed complete. T158 remains open as the interactive GUI verification task, to be run on a Mac with a display (`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift run …` per `Prototypes/README.md`). Constitution XII prohibits claiming unverified completion; the deferral is now documented in the artifact itself rather than implied. (详情见 history/tasks-log.md)
- [X] T175 Reconcile SystemBridge test task→file traceability — **resolved 2026-08-07 (option b)**: T096/T097 file paths updated to `ShortcutDockTests.swift` (the consolidated file, which carries the GlobalShortcut + DockActivation coverage); no split performed (详情见 history/tasks-log.md)

---

## Phase 16: Convergence — 2026-08-07 Clarification Propagation

**Purpose**: Propagate the five requirements clarified in the 2026-08-07 `/speckit-clarify` session (FR-154 repository replacement, FR-162a remember-unlock lifetime, FR-174 long-offline tombstone purge, FR-191 diagnostic-bundle content boundary, wrong-vault-selected edge case) into test + implementation tasks. Encoded in spec.md, plan.md, research.md (R15-refined, R19–R22), data-model.md (VaultConfiguration, DiagnosticSnapshot, Tombstone lifecycle, Constraints), contracts/ (`diagnostic-bundle.schema.json`, `provider-errors.md` `wrongVault` category, `vault-bootstrap.schema.json` description), and checklists/security.md. Tests written FIRST and must FAIL before implementation (Constitution XII).

### Tests for Phase 16 (write FIRST, must FAIL) ⚠️

- [X] T176 [P] [US9] SecurityCore test: wrong-vault-selected fail-closed in `Packages/StickyCore/Tests/SecurityCoreTests/WrongVaultDetectionTests.swift` (详情见 history/tasks-log.md)
- [X] T177 [P] [US9] SecurityCore test: remember-unlock lifetime per FR-162a in `Packages/StickyCore/Tests/SecurityCoreTests/RememberUnlockLifetimeTests.swift` (详情见 history/tasks-log.md)
- [X] T178 [P] [US9] SyncCore test: repository replacement per FR-154 in `Packages/StickyCore/Tests/SyncCoreTests/RepositoryReplacementTests.swift` (详情见 history/tasks-log.md)
- [X] T179 [P] [US10] SyncCore test: long-offline tombstone purge reconciliation — returning device (offline >30 d, remote tombstone already purged by another device's cleanup) syncs: (a) MUST NOT auto-delete any local content; (b) reconciles remote deletion history before upload; (c) if no remote tombstone found for a note, treats as "no remote deletion record found" and preserves it locally; (d) notes the user deleted on the returning device MUST NOT be re-uploaded unless explicitly restored; (e) user is informed that some sync history has aged out; (f) if local version diverged from last known common ancestor, a conflict copy is created on next sync in `Packages/StickyCore/Tests/SyncCoreTests/LongOfflineTombstonePurgeTests.swift` per FR-174 (clarified 2026-08-07) / research R15-refined / data-model §Tombstone lifecycle / Constitution VIII
- [X] T180 [P] [US9] SyncCore/Diagnostics test: diagnostic-bundle field-boundary verification per FR-191 in `Packages/StickyCore/Tests/SyncCoreTests/DiagnosticBundleBoundaryTests.swift` (详情见 history/tasks-log.md)

### Implementation for Phase 16

- [X] T181 [US9] Implement wrong-vault detection in VaultBootstrap in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` (详情见 history/tasks-log.md)
- [X] T182 [US9] Implement remember-unlock lifetime in SecurityCore per FR-162a in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` (详情见 history/tasks-log.md)
- [X] T183 [US9] Implement repository replacement flow in VaultBootstrap + SyncSettingsView per FR-154 in `Packages/StickyCore/Sources/SecurityCore/VaultBootstrap.swift` (详情见 history/tasks-log.md)
- [X] T184 [US10] Refine OfflineReconciler for long-offline tombstone purge — when a returning device (offline >30 d) syncs and the remote tombstone was already purged by another device's cleanup: (a) reconcile remote deletion history BEFORE uploading local notes; (b) if no remote tombstone is found for a note, treat as "no remote deletion record found" and preserve it locally; (c) notes the user deleted on the returning device MUST NOT be re-uploaded unless the user explicitly restores them; (d) inform the user that some synchronization history has aged out; (e) if the local version diverged from the last known common ancestor, create a conflict copy on next sync; MUST NOT auto-delete any local content (refines T129 OfflineReconciler which currently has the generic long-offline handling but not the specific tombstone-purge-reconciliation behavior) in `Packages/StickyCore/Sources/SyncCore/OfflineReconciler.swift` per FR-174 (clarified 2026-08-07) / research R15-refined / data-model §Tombstone lifecycle / Constitution VIII
- [X] T185 [US9] Implement diagnostic-bundle export per FR-191 in `Packages/StickyCore/Sources/SyncCore/DiagnosticBundle.swift` (详情见 history/tasks-log.md)
- [X] T186 [US9] Wire diagnostic-bundle export into Settings UI — add an "Export Diagnostic Bundle" action in `SyncSettingsView` (or `SettingsView`) that generates the bundle via T185 and presents a save-panel (NSSavePanel via SystemBridge) so the user can save/share the JSON file for support; the filename is opaque (e.g. `stickynotes-diagnostics-<date>.json`); the exported file MUST validate against `contracts/diagnostic-bundle.schema.json` and MUST NOT contain any FR-191-excluded data; user-facing message explains what is included and that no note content/credentials are present in `App/Sources/Features/Settings/SyncSettingsView.swift` (or `App/Sources/Features/Settings/SettingsView.swift`) per FR-191 (clarified 2026-08-07) / SC-010 / Constitution VI

**Checkpoint**: All five 2026-08-07 clarifications have test + implementation tasks. Tests T176–T180 must FAIL before T181–T186 are implemented (Constitution XII). Phase 16 depends on: T112 (VaultBootstrap), T117 (SyncEngine), T119 (SyncSettingsView — extended by T183), T129 (OfflineReconciler — refined by T184), T109 (DiagnosticsPrivacyTests — extended by T180). Additive convergence tasks; block nothing in Phases 3–13.

---

## Phase 17: Convergence — 2026-08-07 Clarification Propagation (Sessions 2 & 3)

**Purpose**: Propagate the eleven binding FRs added in the second and third `/speckit-clarify` sessions (FR-022a, FR-023a, FR-072a, FR-090a, FR-094a, FR-140a, FR-152a, FR-160a, FR-160b, FR-160c, FR-160d) into test + implementation tasks. These promote previously-illustrative values into binding spec requirements. Tests written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: Several values already implemented (verify-only); three require implementation changes (FR-094a thumbnail 512→256, FR-152a sync debounce, FR-160d exhaustive fail-closed test vectors).

### Tests for Phase 17 (write FIRST, must FAIL) ⚠️

- [X] T187 [P] [US2] Domain/Persistence test: verify sort-key gap = 1024 and renormalization thres... per FR-022a in `Packages/StickyCore/Tests/DomainTests/SortKeyBindingTests.swift` (详情见 history/tasks-log.md)
- [X] T188 [P] [US2] Persistence test: verify FTS5 `notes_fts` is an external-content table backed... per FR-023a in `Packages/StickyCore/Tests/PersistenceTests/FTS5ExternalContentTests.swift` (详情见 history/tasks-log.md)
- [X] T189 [P] [US4] Domain/EditorCore test: verify todo nesting max depth = 6 per FR-072/FR-072a per FR-072 in `Packages/StickyCore/Tests/EditorCoreTests/TodoDepthBindingTests.swift` (详情见 history/tasks-log.md)
- [X] T190 [P] [US9] SyncCore test: verify assets are synchronized as independent encrypted object... per FR-090a in `Packages/StickyCore/Tests/SyncCoreTests/IndependentAssetSyncTests.swift` (详情见 history/tasks-log.md)
- [X] T191 [P] [US7] AssetStore test: verify thumbnail longest edge = 256px per FR-094a per FR-094a in `Packages/StickyCore/Tests/AssetStoreTests/Thumbnail256BindingTests.swift` (详情见 history/tasks-log.md)
- [X] T192 [P] Persistence test: verify bounded busy timeout = 5 seconds per FR-140/FR-140a per FR-140 in `Packages/StickyCore/Tests/PersistenceTests/BusyTimeoutBindingTests.swift` (详情见 history/tasks-log.md)
- [X] T193 [P] [US9] SyncCore test: verify sync debounce window = 2-4 seconds after last local cha... per FR-152a in `Packages/StickyCore/Tests/SyncCoreTests/SyncDebounceBindingTests.swift` (详情见 history/tasks-log.md)
- [X] T194 [P] [US9] SecurityCore test: verify meaningful-metadata positive enumeration per FR-160a per FR-160a in `Packages/StickyCore/Tests/SecurityCoreTests/MeaningfulMetadataEnumerationTests.swift` (详情见 history/tasks-log.md)
- [X] T195 [P] [US9] SecurityCore test: verify Argon2id production minimums per FR-160c per FR-160c in `Packages/StickyCore/Tests/SecurityCoreTests/Argon2idProductionMinimumTests.swift` (详情见 history/tasks-log.md)
- [X] T196 [P] [US9] SecurityCore test: exhaustive fail-closed input vectors per FR-160d per FR-160d in `Packages/StickyCore/Tests/SecurityCoreTests/FailClosedVectorTests.swift` (详情见 history/tasks-log.md)

### Implementation for Phase 17

- [X] T197 [US7] Change `ThumbnailGenerator.defaultLongestEdge` from 512 to 256 per FR-094a in `Packages/StickyCore/Sources/AssetStore/ThumbnailGenerator.swift` (详情见 history/tasks-log.md)
- [X] T198 [US9] Implement sync debounce window (2-4 seconds) in SyncEngine per FR-152a per FR-152a in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` (详情见 history/tasks-log.md)
- [X] T199 [US9] Enforce Argon2id production-minimum rejection in KeyDerivation per FR-160c per FR-160c in `Packages/StickyCore/Sources/SecurityCore/KeyDerivation.swift` (详情见 history/tasks-log.md)
- [X] T200 [US9] Extend fail-closed test vectors to exhaustive FR-160d list in SecurityCore per FR-160d in `Packages/StickyCore/Sources/SecurityCore/EncryptedEnvelope.swift` (详情见 history/tasks-log.md)
- [X] T201 [P] [US9] Verify FTS5 external-content mode in Persistence per FR-023a in `Packages/StickyCore/Sources/Persistence/FullTextSearch.swift` (详情见 history/tasks-log.md)
- [X] T202 [P] [US9] Verify independent-asset sync granularity in SyncEngine per FR-090a in `Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` (详情见 history/tasks-log.md)

**Checkpoint**: All eleven binding FRs from clarify sessions 2 & 3 have test + implementation tasks. Tests T187–T196 must FAIL before T197–T202 are implemented (Constitution XII). Phase 17 depends on: T013 (VersionLineage — verified by T187), T020 (FTS5 — verified/refactored by T201), T061 (TodoRepository — verified by T189), T087/T088 (AssetStore/ThumbnailGenerator — changed by T197, verified by T190/T191), T017 (DatabaseStore — verified by T192), T117 (SyncEngine — extended by T198, verified by T193), T111 (SecurityCore — extended by T199/T200, verified by T194/T195/T196). Additive; blocks nothing in Phases 3–13.

**Implementation audit summary** (verify-only vs requires changes):
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

**Purpose**: Propagate the two binding spec requirements added after a `checklists/ux.md` coverage review (CHK058): **FR-014a** (first-launch experience: empty library with a clear create-first-note call to action; no permission prompts on first launch unless the user invokes a feature requiring them; sync-status area shows "not configured" rather than an error when sync is unconfigured; a brief, dismissible onboarding hint explaining auto-save and the menu-bar-primary model, never shown again after the first note is created) and **SC-004a** (keystroke-to-glyph latency <16 ms during normal editing including with Chinese IME composition active, measured via OSLog signposts/Instruments). Both are UI/UX-facing; no impact on contracts or the sync protocol. Tests written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: `StickyLogger` already provides `signpostBegin`/`signpostEnd` (OSSignposter) in `Domain/Logging.swift` — SC-004a needs the editor keystroke path wired through them and a latency assertion. FR-014a has no existing implementation: `App/Sources/Features/Library/` and `App/Sources/Features/Editor/` are empty, `StickyNotesApp.swift` ships only a stub `MenuBarExtra`, and `PermissionService` (T104) exists but has no startup-path guard.

### Tests for Phase 18 (write FIRST, must FAIL) ⚠️

- [X] T203 [P] [US1] Domain test: first-launch hint state machine per FR-014a per FR-014a in `Packages/StickyCore/Tests/DomainTests/FirstLaunchStateTests.swift` (详情见 history/tasks-log.md)
- [X] T204 [P] [US1] App integration test: first-launch experience end-to-end per FR-014a — on a fresh App Group container with no Keychain credentials: launch → the menu-bar library shows an empty card grid with a clear call-to-action to create the first note (button + keyboard shortcut); the sync-status area shows "not configured" (never an error); NO permission prompt fires during launch (assert `PermissionService` records no request on the startup path); a dismissible onboarding hint explaining auto-save and the menu-bar-primary model is visible; after creating the first note the hint is never shown again across relaunches; dismissing the hint also hides it permanently in `AppTests/FirstLaunchExperienceIntegrationTests.swift` per FR-014a / research R28 / data-model §LocalPreferences / Constitution VI/X/III
- [X] T205 [P] [US1] EditorCore performance test: keystroke-to-glyph latency <16 ms per SC-004a — signpost-bracket the editor input path (keystroke event → attributed-state mutation → glyph commit) via `StickyLogger.signpostBegin`/`signpostEnd`; assert the interval stays below 16 ms (one frame at 60 Hz) for plain English, Chinese IME marked-text, mixed CJK/Latin, and emoji input sequences; assert signposts carry timing and sanitized op names only (no note content, per FR-191/Constitution VI) in `Packages/StickyCore/Tests/EditorCoreTests/KeystrokeLatencyTests.swift` per SC-004a / research R29 / plan §Keystroke latency instrumentation / Constitution XI/XII/VI

### Implementation for Phase 18

- [X] T206 [US1] Implement `FirstLaunchState` value type per FR-014a in `Packages/StickyCore/Sources/Domain/Models/FirstLaunchState.swift` (详情见 history/tasks-log.md)
- [X] T207 [US1] Implement device-local persistence of first-launch state per FR-191 in `App/Sources/Features/Library/LocalPreferences.swift` (详情见 history/tasks-log.md)
- [X] T208 [US1] Implement empty-library CTA + onboarding hint UI in `App/Sources/Features/Library/EmptyLibraryView.swift` — empty card-grid state with a clear call-to-action to create the first note (button + keyboard shortcut); a brief, dismissible onboarding hint explaining auto-save and the menu-bar-primary model; the hint is never shown again once `hasCreatedFirstNote` or `dismissed` is set (T207); wire into `MenuBarLibraryScene.swift` (extends T032/T159) per FR-014a / research R28 / Constitution X/III
- [X] T209 [US1] Implement "not configured" sync status in `App/Sources/Features/Library/SyncStatusView.swift` — when no `VaultConfiguration` exists, the sync-status area shows "not configured" (never an error); only show error/status states when sync is actually configured (extends T120/T170) per FR-014a / plan §First-launch experience / Constitution III
- [X] T210 [US1] Enforce no-permission-prompts-on-first-launch guard per FR-014a in `App/Sources/App/AppEnvironment.swift` (详情见 history/tasks-log.md)
- [X] T211 [US1] Instrument keystroke-to-glyph path with OSLog signposts per SC-004a — wire `StickyLogger.signpostBegin`/`signpostEnd` (already provided in `Packages/StickyCore/Sources/Domain/Logging.swift`) around keystroke event → attributed-state commit → glyph commit in the editor input path; signposts carry timing and sanitized op names only (no note content per FR-191); verify the interval appears in the Instruments Signpost Logging track and stays below 16 ms per T205 in `App/Sources/Features/Editor/RichTextBlockView.swift` (extends T036) per SC-004a / research R29 / plan §Keystroke latency instrumentation / Constitution XI/VI

**Checkpoint**: FR-014a and SC-004a have test + implementation tasks. Tests T203–T205 must FAIL before T206–T211 are implemented (Constitution XII). Phase 18 depends on: T032/T159 (MenuBarLibraryScene — extended by T208, T209), T104 (PermissionService — guarded by T210), T036 (editor input path — instrumented by T211), Domain/Logging.swift signpost helpers (already implemented). Additive; blocks nothing in Phases 3–13.

**Implementation audit summary** (verify-only vs requires changes):
- FR-014a (first-launch experience): ✗ not implemented — T203/T204 verify, T206–T210 implement
- SC-004a (keystroke-to-glyph <16 ms): ⚠ signpost helpers exist; editor path not instrumented — T205 verify, T211 implement

## Phase 19: Convergence — 2026-08-07 Third Clarify Session (FR-012a, FR-160e, FR-022a Trash-restore, FR-162a Launch + Toggle)

**Purpose**: Propagate the five binding clarifications added in the third `/speckit-clarify` session: **FR-012a** (precise "meaningful text" definition for empty-note auto-removal: ≥1 non-whitespace Unicode character in the title or any rich-text block, OR the presence of any todo/image/screenshot/code-block/file-reference block; a single character qualifies, whitespace-only does not), **FR-160e** (wrong-password unlock attempts MUST NOT be rate-limited, throttled, or lockout-bounded; Argon2id KDF cost is the rate limiter; no cached password/derived key), **FR-022a Trash-restore** (restoring a note from Trash resets its `manualSortKey` to max(active)+1024, placing it at the end of Manual order; pre-deletion key not retained), and **FR-162a launch + toggle** (app-launch unlock via boot-timestamp comparison — remember enabled + no restart → silent restore + startup sync, otherwise prompt; toggle-off while unlocked clears Keychain immediately but preserves the current unlocked session until explicit lock/exit). Tests written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: T077/T081 cover the basic auto-discard concept but do not pin the FR-012a one-non-whitespace-character threshold. T112 covers vault bootstrap but has no FR-160e no-lockout guard or FR-162a boot-timestamp/toggle logic. T079 covers the lifecycle state machine but not the FR-022a Trash-restore sort-key reset.

### Tests for Phase 19 (write FIRST, must FAIL) ⚠️

- [X] T212 [P] [US6] Domain test: FR-012a meaningful-text boundary per FR-012a in `Packages/StickyCore/Tests/DomainTests/MeaningfulTextBoundaryTests.swift` (详情见 history/tasks-log.md)
- [X] T213 [P] [US9] SecurityCore test: FR-160e no-rate-limit on wrong-password unlock per FR-160d in `Packages/StickyCore/Tests/SecurityCoreTests/NoLockoutPolicyTests.swift` (详情见 history/tasks-log.md)
- [X] T214 [P] [US6] Persistence test: FR-022a Trash-restore sort-key reset per FR-022a in `Packages/StickyCore/Tests/PersistenceTests/TrashRestoreSortKeyTests.swift` (详情见 history/tasks-log.md)
- [X] T215 [P] [US9] SecurityCore test: FR-162a app-launch unlock via boot timestamp per FR-152a in `Packages/StickyCore/Tests/SecurityCoreTests/AppLaunchUnlockTests.swift` (详情见 history/tasks-log.md)
- [X] T216 [P] [US9] SecurityCore test: FR-162a toggle-off while unlocked per FR-162a in `Packages/StickyCore/Tests/SecurityCoreTests/RememberUnlockToggleTests.swift` (详情见 history/tasks-log.md)

### Implementation for Phase 19

- [X] T217 [US6] Pin FR-012a meaningful-text threshold in auto-discard logic per FR-012a in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` (详情见 history/tasks-log.md)
- [X] T218 [US9] Enforce FR-160e no-lockout policy in SecurityCore per FR-160e in `Packages/StickyCore/Sources/SecurityCore/` (详情见 history/tasks-log.md)
- [X] T219 [US6] Implement FR-022a Trash-restore sort-key reset in NoteLifecycle/NoteRepository per FR-022a in `Packages/StickyCore/Sources/Domain/NoteLifecycle.swift` (详情见 history/tasks-log.md)
- [X] T220 [US9] Implement FR-162a app-launch unlock + boot-timestamp detection in SecurityCor... per FR-152a in `Packages/StickyCore/Sources/SecurityCore/VaultConfiguration.swift` (详情见 history/tasks-log.md)
- [X] T221 [US9] Implement FR-162a toggle-off behavior in SecurityCore/Settings per FR-162a in `Packages/StickyCore/Sources/SecurityCore/VaultConfiguration.swift` (详情见 history/tasks-log.md)

**Checkpoint**: All five binding clarifications from the third clarify session have test + implementation tasks. Tests T212–T216 must FAIL before T217–T221 are implemented (Constitution XII). Phase 19 depends on: T079 (NoteLifecycle — extended by T217, T219), T081/T167 (NoteWindowCoordinator auto-discard hook — wired by T217), T030 (NoteRepository — extended by T219), T112 (VaultBootstrap — extended by T218, T220), T011 (VaultConfiguration Domain model — extended by T220), T119 (SyncSettingsView — extended by T221). Additive; blocks nothing in Phases 3–13.

**Implementation audit summary** (verify-only vs requires changes):
- FR-012a (meaningful-text threshold): ⚠ concept covered by T077/T081, threshold not pinned — T212 verify, T217 pin exact rule
- FR-160e (no-lockout policy): ⚠ audit + guard — T213 verify, T218 audit/remove latent logic
- FR-022a Trash-restore (sort-key reset): ✗ restore path exists but no reset — T214 verify, T219 implement reset
- FR-162a launch (boot-timestamp): ✗ not implemented — T215 verify, T220 implement
- FR-162a toggle-off (Keychain clearance + session preserve): ✗ not implemented — T216 verify, T221 implement

## Phase 20: Convergence — 2026-08-07 Clarify Sessions 4 & 5 (FR-031a, FR-180a, FR-090b, FR-141a, FR-022b, FR-014b, FR-040a, FR-041a, FR-050a, FR-110a)

**Purpose**: Propagate the ten binding clarifications added in the fourth and fifth `/speckit-clarify` sessions: **FR-031a** (single-note JSON export/import reusing the canonical note-envelope schema; round-trip faithful; file references export generic metadata only; import fails closed), **FR-180a** (zh-Hans + en UI localization, system-language switch), **FR-090b** (scale limits: asset ≤ 50 MB / ≤ 16,384 px longest edge; note structured content ≤ 5 MB; oversize insertions rejected), **FR-141a** (auto-save debounce 500 ms; flush before close/delete/quit; crash-loss window ≤ one debounce window), **FR-022b** (manual-order sort-key divergence reconciled per-note by last-writer-wins, no conflict copies), **FR-014b** (Empty Trash batch permanent delete with explicit confirmation), **FR-040a** (canonical sRGB hex per built-in color), **FR-041a** (opacity 40%–100%, 5-pt steps, default 100%), **FR-050a** (emptied blocks removed on cursor exit, final block preserved, single-Undo, IME-safe), **FR-110a** (change-driven widget refresh, no fixed polling). Whole-library bulk export/import is a declared non-goal. Tests written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: FR-040a/FR-041a/FR-090b/FR-014b/FR-031a have no existing implementation (colors/opacity are unbound values, no size caps, no Empty Trash, no export/import path). FR-141a has a debounce concept (T037) but no pinned 500 ms value or crash-loss contract. FR-050a block deletion exists but has no cursor-exit/merge rule. FR-110a widget reload exists (Phase 10) but is not change-driven. FR-180a string catalogs are planned (T008) but not bound to zh-Hans+en completeness. FR-022b has no sync-side sort-key coordination.

### Tests for Phase 20 (write FIRST, must FAIL) ⚠️

- [X] T222 [P] [US6] Persistence test: Empty Trash batch permanent delete per FR-014b — with N notes in Trash, invoking Empty Trash without confirmation deletes nothing; after confirmation, ALL trashed notes transition trashed → permanentlyDeleted in a single transaction (no intermediate observable state); readable local content removed when safe; a Tombstone is retained per note for sync (FR-174 sync-safety applies); the confirmation states immediate permanent deletion and loss of the 30-day recoverability guarantee in `Packages/StickyCore/Tests/PersistenceTests/EmptyTrashTests.swift` per FR-014b / research R38 / data-model §Note lifecycle / Constitution X/VIII
- [X] T223 [P] [US10] SyncCore test: sort-key-only divergence → per-note LWW, no conflict copy per FR-022b — (a) two devices reorder the same notes differently with NO content change → sync applies the most recently written sort key per note (deterministic via version timestamp/sequence), NO conflict copy is created; (b) crossed reorder (A moves X above Y while B moves Y above X) resolves deterministically per-note by version recency; (c) sort-key divergence combined with real content divergence → a content conflict copy IS still created; (d) assert content fields are the ONLY divergence trigger in `Packages/StickyCore/Tests/SyncCoreTests/SortKeyLastWriterWinsTests.swift` per FR-022b / research R35 / plan §Conflict model / Constitution VIII/IV/XII
- [X] T224 [P] [US1] Domain/Persistence test: note JSON export/import round-trip per FR-031a — export a note containing every block kind (rich text with all supported attributes, todos incl. nesting/state/order, code block, file reference, embedded image, screenshot) → import the JSON → assert byte-level semantic equality of text, rich-text attributes, todo identity/text/state/nesting/order, code text, image/screenshot asset payloads, and appearance (color, transparency, text size, Always-on-Top); assert file-reference blocks import with generic metadata only (display name, content type, size, origin device, added date — NEVER bookmark bytes or absolute paths per FR-105); assert importing an unsupported schema version or corrupted envelope fails closed with NO partial note created; assert the exported document validates against `contracts/note-document.schema.json` in `Packages/StickyCore/Tests/DomainTests/NoteExportImportRoundTripTests.swift` per FR-031a / research R34 / contracts/note-document.schema.json / Constitution IV/XII
- [X] T225 [P] [US3] Domain test: canonical color hexes + opacity range per FR-040/FR-040a, FR-041/FR-041a — assert the six built-in colors resolve to EXACTLY the canonical sRGB hexes (yellow #FFE08A, pink #F9A8C4, purple #C9A8E8, blue #A8CFF9, green #A8E8B8, gray #D8D8DC) shared across light/dark; assert opacity is constrained to 0.40–1.00 in 0.05 steps with default 1.00; assert FR-042 WCAG 2.2 contrast (≥4.5:1 normal, ≥3:1 large/controls) holds for the full matrix: 6 colors × 13 opacity steps × light/dark, computed against the effective composited background (note color at chosen opacity over a desktop sample), with automatic foreground adjustment as the fallback in `Packages/StickyCore/Tests/DomainTests/NoteAppearanceBindingTests.swift` per FR-040a/FR-041a / research R37 / data-model §Note / Constitution X/XI/XII
- [X] T226 [P] [US1] EditorCore test: empty-block removal per FR-050a — (a) an emptied block (paragraph/list item/todo/heading) stays in place while the cursor remains within it; (b) on cursor exit the block is removed by merging with the adjacent block (or deleted when no merge is possible); (c) the final block of a note is NEVER removed this way (remains an empty paragraph); (d) a single Undo restores the removed block and its content; (e) removal does NOT fire while an input-method marked-text composition is active (FR-063) in `Packages/StickyCore/Tests/EditorCoreTests/EmptyBlockRemovalTests.swift` per FR-050a / research R38 / plan §Editor architecture / Constitution V/X/XII
- [X] T227 [P] [US7] AssetStore/Persistence test: scale limits per FR-090b — assert constants: max asset bytes = 50 MB, max asset longest edge = 16,384 px, max note structured content = 5 MB; pasting/inserting an image over any asset limit is rejected with a localized explanation and NO partial asset write (no orphan temp file, no metadata record); a content change that would push note structured content over 5 MB is refused while the last valid saved state is preserved intact; assets within limits still sync as independent objects (FR-090a) in `Packages/StickyCore/Tests/AssetStoreTests/ScaleLimitTests.swift` per FR-090b / research R39 / contracts/asset-metadata.schema.json / Constitution XI/IV/XII
- [X] T228 [P] [US8] App/Widget test: change-driven widget refresh per FR-110a — after a local change affecting a widget (note created/edited/deleted/trashed/restored, todo toggled, widget-eligibility changed, conflict copy created), assert the main app triggers a WidgetKit timeline reload for the affected widget kind(s) (via WidgetCenter test double) and does NOT reload unaffected kinds; a widget action (todo toggle, quick-create) also triggers refresh of affected widgets; assert the widget process contains NO fixed-interval polling timer (no `Timer`/repeating refresh scheduling) in `AppTests/WidgetChangeDrivenRefreshTests.swift` per FR-110a / research R36 / plan §Widgets / Constitution XI/VI/SC-006
- [X] T229 [P] [US1] Persistence test: auto-save debounce + crash-loss contract per FR-141/FR-141a — assert ordinary text changes persist in a single transaction once 500 ms elapse without further changes (deterministic per build); structural ops/todo completion persist immediately; flush happens before window close, note deletion, auto-removal decision (FR-012), and application quit; crash-recovery: terminate the process mid-edit (within the debounce window), relaunch, assert at most the input from the last debounce window is lost and content persisted by a completed autosave is always recovered in `Packages/StickyCore/Tests/PersistenceTests/AutosaveCrashConsistencyTests.swift` per FR-141a / research R17-refined / plan §Auto-save / Constitution III/XII
- [X] T230 [P] [US1] App test: zh-Hans + en localization completeness per FR-180a — assert every user-visible string (menus, buttons, tooltips, toasts, settings, Help, accessibility labels, error/sync status) is resolved from the localization catalogs with NO hard-coded UI strings (source scan for string literals in `App/Sources/`); assert both zh-Hans and en variants exist for every catalog key; assert the deletion toast announced by VoiceOver (FR-009a) respects the active locale; assert the SC-011 core capture loop is operable in either language in `AppTests/LocalizationCompletenessTests.swift` per FR-180a / plan §Localization / Constitution X/II/XII

### Implementation for Phase 20

- [X] T231 [US6] Implement Empty Trash in Trash view + NoteRepository per FR-014b — add an "Empty Trash" action to the Trash UI (`App/Sources/Features/Trash/TrashView.swift`, extends T167): the action opens a confirmation dialog stating that all notes in Trash will be permanently deleted immediately and that the 30-day recoverability guarantee (FR-014) no longer applies (localized per FR-180a, keyboard-accessible per FR-181); on confirmation, transition every trashed note to permanentlyDeleted in a single transaction with tombstone retention per FR-174 (`Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift`, extends T030) per FR-014b / research R38 / data-model §Note lifecycle / Constitution X/VIII
- [X] T232 [US10] Implement per-note sort-key last-writer-wins in SyncCore per FR-022b — in the divergence detection path (`Packages/StickyCore/Sources/SyncCore/SyncEngine.swift` or the divergence detector), when comparing local vs remote note versions: if the ONLY differing field is `manualSortKey`, accept the newer version's sort key (deterministic per-note by version timestamp/sequence) WITHOUT recording divergence and WITHOUT creating a conflict copy; if any content field also differs, the normal conflict-copy path applies; crossed reorders resolve per-note by version recency (no global order arbitration) per FR-022b / research R35 / plan §Conflict model / Constitution VIII/IV — **no per-field divergence classification exists; this task adds it**
- [X] T233 [US1] Implement single-note JSON export/import per FR-031a — export: serialize the note (blocks + embedded asset payloads + appearance) into the canonical note-document form (`Packages/StickyCore/Sources/Domain/NoteDocumentSerializer.swift`), write via NSSavePanel (SystemBridge, sandbox user-selected location); import: read via NSOpenPanel, validate `schemaVersion` and envelope structure, fail closed on unsupported/corrupted documents with NO partial note, insert through the same repository path as new notes (T030); file-reference blocks export/import generic metadata only — never bookmark bytes or absolute paths (FR-105); wire both actions into the note contextual menu (extends T031) and library (import) in `App/Sources/Features/NoteWindow/NoteExportImport.swift` and `Packages/StickyCore/Sources/Domain/NoteDocumentSerializer.swift` per FR-031a / research R34 / contracts/note-document.schema.json / Constitution IV/X — **no export/import path exists**
- [X] T234 [US3] Implement canonical colors + bounded opacity per FR-040a/FR-041a — define the six canonical sRGB hex constants in `Packages/StickyCore/Sources/Domain/Models/NoteAppearance.swift` (yellow #FFE08A, pink #F9A8C4, purple #C9A8E8, blue #A8CFF9, green #A8E8B8, gray #D8D8DC); constrain note background opacity to 0.40–1.00 in 0.05 steps with default 1.00 (replacing any unbounded value in T034); apply FR-042 contrast validation and automatic foreground adjustment against the effective composited background whenever opacity < 1.00; any hex change must update the T225 contrast matrix in the same change (Constitution IV) per FR-040a/FR-041a / research R37 / data-model §Note / Constitution X/XI — **colors/opacity currently unbound; this task pins them**
- [X] T235 [US1] Implement empty-block removal in EditorCore per FR-050a — when the cursor leaves an emptied block (paragraph/list item/todo/heading): remove it by merging with the adjacent block (or deleting when no merge is possible); never remove the final block of a note (it remains an empty paragraph); group the removal as ONE undo operation (single Undo restores block + content); suppress removal while an input-method marked-text composition is active (FR-063) in `Packages/StickyCore/Sources/EditorCore/BlockMergeOperation.swift` (new) wired into the editor focus/movement path (`App/Sources/Features/Editor/RichTextBlockView.swift`, extends T036) per FR-050a / research R38 / plan §Editor architecture / Constitution V/X — **block deletion exists (T036) but has no cursor-exit/merge rule; this task adds it**
- [X] T236 [US7] Implement scale limits in AssetStore/Persistence per FR-090b — add explicit constants (maxAssetBytes = 50 MB, maxAssetLongestEdge = 16,384 px, maxNoteContentBytes = 5 MB) enforced at the asset-store and persistence boundaries: oversize paste/capture insertions are rejected with a localized explanation and NO partial asset write (no orphan temp files, no metadata record); content changes that would exceed the 5 MB note-content cap are refused while the last valid saved state is preserved; constants documented and covered by T227 in `Packages/StickyCore/Sources/AssetStore/AssetStore.swift` and `Packages/StickyCore/Sources/Persistence/Repositories/NoteRepository.swift` per FR-090b / research R39 / contracts/asset-metadata.schema.json / Constitution XI/IV — **no size caps exist**
- [X] T237 [US8] Implement change-driven widget refresh per FR-110a — add a `WidgetRefreshCoordinator` (`App/Sources/App/WidgetRefreshCoordinator.swift`): after any persistence write affecting widget surface (note created/edited/deleted/trashed/restored, todo toggled, widget-eligibility changed, conflict copy created), call `WidgetCenter.shared.reloadTimelines(ofKind:)` for the affected kinds only; widget actions (todo toggle, quick-create) trigger refresh of affected widgets; ensure NO fixed-interval polling timer exists in the widget process (SC-006); when the app is not running, widgets may show last-known content until the app next runs or the system refreshes (FR-140a "temporarily unavailable" on read failure) per FR-110a / research R36 / plan §Widgets / Constitution XI/VI — **widget reload exists (Phase 10) but is not change-driven**
- [X] T238 [US1] Implement 500 ms auto-save debounce + crash-loss contract per FR-141a — replace the current debounce value (~300 ms placeholder in `Packages/StickyCore/Sources/Persistence/NoteAutosaveDebouncer.swift` or the editor autosave path) with a deterministic 500 ms debounce persisting in a single transaction, decoupled from the 2-4 s sync debounce (T198); flush synchronously before window close, note deletion, auto-removal decisions (FR-012), and application quit; keep the revision-token/serialized-edit-session protection so a stale debounced write cannot clobber a newer structural edit; crash-loss contract per FR-141a verified by T229 per FR-141a / research R17-refined / plan §Auto-save / Constitution III/XII — **debounce exists (~300 ms); must be pinned to 500 ms with flush guarantees**
- [X] T239 [US1] Implement zh-Hans + en localization per FR-180a — populate the String Catalogs (`App/Sources/Resources/` Localizable.xcstrings for zh-Hans + en) with ALL user-visible strings (menus, buttons, tooltips, toasts, settings, Help, accessibility labels, error/sync status text); switch follows the system language preference; note content is never translated; the deletion toast announced by VoiceOver (FR-009a) resolves from the active locale; audit `App/Sources/` for hard-coded UI strings and move them into the catalogs; localization completeness verified by T230 and SC-011 operability in both languages per FR-180a / plan §Localization / Constitution X/II — **catalogs planned (T008) but not bound to zh-Hans+en completeness**

**Checkpoint**: All ten binding clarifications from clarify sessions 4 & 5 have test + implementation tasks. Tests T222–T230 must FAIL before T231–T239 are implemented (Constitution XII). Phase 20 depends on: T030 (NoteRepository — extended by T231, T236), T167 (TrashView — extended by T231), T117 (SyncEngine — extended by T232), T031 (note contextual menu — extended by T233), T034/T036 (note appearance/editor — extended by T234/T235), T087 (AssetStore — extended by T236), WidgetExtension (Phase 10 — refreshed by T237), T037 (autosave path — pinned by T238), T008 (string catalogs — extended by T239). Additive; blocks nothing in Phases 3–13.

**Implementation audit summary** (verify-only vs requires changes):
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

**Purpose**: Cover the binding spec requirement **FR-072b** (editor + note-card surfaces MUST gracefully handle notes with 100+ todo items: virtualized/lazy rendering of the todo block view; the note card shows todo progress as "completed/total", switching to "99+ completed" when the total exceeds 99; sync handles large todo payloads with encryption/decryption off the main actor). This FR was identified by `/speckit-analyze` as a coverage gap (zero tasks referenced it). Tests written FIRST and must FAIL (Constitution XII).

### Tests for Phase 21 (write FIRST, must FAIL) ⚠️

- [X] T240 [P] [US4] EditorCore test: large todo list rendering per FR-072b — a note with 100+ (and 1,000+) todo items: assert the todo block view realizes only visible rows (bounded row-realization count regardless of total, virtualized/lazy rendering); assert scrolling remains smooth (no full-list re-render per frame) in `Packages/StickyCore/Tests/EditorCoreTests/LargeTodoListTests.swift` per FR-072b / spec §FR-072b / Constitution V/XI — **no existing task covers FR-072b**
- [X] T241 [P] [US2] Domain test: card todo-progress format per FR-072b — assert the card progress string is "completed/total" (e.g. "12/45"); assert totals > 99 render as "99+ completed"; assert 0-completed and all-completed edge cases in `Packages/StickyCore/Tests/DomainTests/NoteCardProgressTests.swift` per FR-072b / spec §FR-072b / Constitution X
- [X] T242 [P] [US9] SyncCore test: large todo payload per FR-072b — a note with 100+ todos syncs via the canonical note envelope with no special chunking; assert encryption/decryption of the large payload runs OFF the main actor in `Packages/StickyCore/Tests/SyncCoreTests/LargeTodoSyncTests.swift` per FR-072b / spec §FR-072b / Constitution VIII/XI

### Implementation for Phase 21

- [X] T243 [US4] Implement virtualized todo list in `App/Sources/Features/Editor/TodoBlockView.swift` (extends T062) — realize only visible todo rows (bounded row realization for notes with 100+ items); keep the underlying scroll smooth for arbitrarily long todo lists; editing/toggling/reordering on unrealized rows works via stable todo UUIDs per FR-072b / spec §FR-072b / Constitution V/XI — **T062 realizes all rows**
- [X] T244 [US2] Implement "99+ completed" card progress in `App/Sources/Features/Library/NoteCardView.swift` (extends T162) — render todo completion progress as "completed/total" (e.g. "12/45"); when the total exceeds 99 render "99+ completed" to avoid width overflow while preserving the progress signal per FR-072b / spec §FR-072b / Constitution X/XI — **T162 covers FR-020 indicators but not the 99+ rule**

**Checkpoint**: FR-072b has test + implementation tasks. Tests T240–T242 must FAIL before T243–T244 are implemented (Constitution XII). Phase 21 depends on: T062 (TodoBlockView — extended by T243), T162 (NoteCardView — extended by T244), T117 (SyncEngine — verified by T242). Additive; blocks nothing in Phases 3–13.

---

## Phase 22: Convergence — 2026-08-07 Post-Phase-16-19 Audit

**Purpose**: Close the three traceability gaps found in the post-Phase-16-19 convergence audit: **FR-009a** (one-time deletion toast + immediate window close when a note with an open window is deleted — referenced in tasks.md only in localization contexts T230/T239, never wired as behavior), **FR-031** note-level contextual actions (duplicate note + copy note as Markdown are untracked MUST actions of the FR-031 contextual menu; only export/import T233 and move-to-Trash T167 are tracked), and the committed `StickyNotes.xcodeproj` contradicting the "generated at build time, not committed" declaration (T001/T173 vs actual repo/CI state). Tests written FIRST and must FAIL before implementation (Constitution XII).

- [X] T245 [P] [US6] App integration test: FR-009a deletion toast + immediate window close — create a note, open its window, delete the note from the menu-bar library (and separately from Trash): assert the open note window closes immediately; assert a one-time, non-blocking, auto-dismissing transient toast announces the localized outcome ("Moved to Trash" / "Permanently Deleted") without blocking interaction or requiring dismissal; assert the deletion is NOT blocked by the open window and closing the window does NOT cancel the deletion; assert restoring from Trash does NOT auto-reopen the window (FR-007); assert the toast is VoiceOver-announceable and respects the active locale (FR-180a) in `AppTests/DeletionToastIntegrationTests.swift` per FR-009a / spec §Edge Cases / Constitution X/XII — **no task wires the FR-009a toast mechanism or its test**
- [X] T246 [US6] Implement FR-009a deletion-toast + immediate window close in the library/Trash delete flows — when a note with an open window is deleted (to Trash or permanently) from `MenuBarLibraryScene` (T159) or `TrashView` (T167): immediately close the note's window(s) via `NoteWindowCoordinator` (T160) and present a one-time transient toast announcing the localized deletion outcome; the toast auto-dismisses within a short bounded period, never blocks interaction, and is announced by VoiceOver (localized per FR-180a); restoring from Trash never reopens the window in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (or a shared `DeletionToastPresenter` used by library + Trash) and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` per FR-009a / spec §Edge Cases / Constitution X/III — **the toast + immediate-close wiring is absent; delete paths are being built by T159/T167**
- [X] T247 [P] [US1] [US3] Domain/EditorCore test: note duplicate + copy-as-Markdown per FR-031 — duplicating a note yields a new note UUID with byte-identical blocks, appearance (color, transparency, text size, Always-on-Top), and asset references; copy-as-Markdown serializes blocks (rich text with supported marks, todos with nesting/state, code blocks with preserved text, file-reference display names, screenshot/image captions) into Markdown text with no loss of round-trippable text content in `Packages/StickyCore/Tests/DomainTests/NoteDuplicateAndMarkdownCopyTests.swift` per FR-031 / spec §FR-031 / Constitution V/XII — **the note-level contextual actions "duplicate note" and "copy note as Markdown" (FR-031 MUST) have no task coverage**
- [X] T248 [US1] [US3] Implement note-level contextual actions "duplicate note" + "copy note as Markdown" — extend the note contextual menu opened from the upper control area (`NoteControlsView`, T165) with: duplicate note (new note UUID, identical blocks + appearance + asset references, lifecycle active, fresh manual sort key per FR-022a) and copy note as Markdown (Markdown text of the note's blocks on the clipboard, serialization helper in `App/Sources/Features/NoteWindow/NoteExportImport.swift` or a small App-layer/EditorCore helper); export-note-as-JSON and move-to-Trash actions are already tracked by T233/T167 in `App/Sources/Features/NoteWindow/NoteExportImport.swift` per FR-031 / spec §FR-031 / Constitution V/X — **only export/import (T233) and move-to-Trash (T167) are tracked; duplicate + copy-as-Markdown are untracked MUST actions of FR-031**
- [X] T249 Reconcile the committed `StickyNotes.xcodeproj` with the "generated at build time, not committed" declaration — `StickyNotes.xcodeproj/project.pbxproj` is committed in git and `.github/workflows/ci.yml` uses it directly with NO `xcodegen` step, while T001/T173 and `project.yml` declare the binary project is generated at build time and not committed; either (a) remove the committed `.xcodeproj`, add a `xcodegen generate` step to `ci.yml` + quickstart.md, and gitignore it, or (b) if committing is the chosen practice, update T001/T173, the `project.yml` header, and quickstart.md to document commit-and-regenerate with a CI drift check (regenerate + `git diff --exit-code`) in `.github/workflows/ci.yml`, `project.yml`, and `specs/001-sticky-notes-app/quickstart.md` per plan §Project Structure / Constitution IV (contradicts) — **the repo currently commits the generated project while declaring it uncommitted; CI cannot regenerate it today**

**Checkpoint**: FR-009a, the FR-031 contextual-menu actions, and the xcodeproj contradiction have test + implementation (or reconciliation) tasks. Tests T245/T247 must FAIL before T246/T248 are implemented (Constitution XII). Phase 22 depends on: T159 (MenuBarLibraryScene — extended by T246), T167 (TrashView — extended by T246), T160 (NoteWindowCoordinator — extended by T246), T165 (NoteControlsView — extended by T248), T233 (NoteExportImport — extended by T248), T001/T173 (project generation model — reconciled by T249). Additive; blocks nothing in Phases 3–21.

---

## Phase 23: Convergence — 2026-08-07 Sixth Clarify Session (FR-001a, FR-020a, FR-043a, FR-095a, FR-054)

**Purpose**: Cover the five binding spec requirements from the sixth `/speckit-clarify` session (targeted at remaining `checklists/ux.md` gaps): **FR-001a** (menu-bar library window: left edge aligned with the icon's left edge, clamped to the visible screen frame, 4 pt below the menu bar, instant open/dismiss with no animation), **FR-020a** (card body preview truncated at 2 rendered lines with a trailing ellipsis, drawn from the first rich-text block — never duplicating the generated summary title; last-modified time relative within 7 days, then absolute with the year when in a previous calendar year), **FR-043a** (per-note text size bounded 9–24 pt in 1-pt steps, default 13 pt; text ≥18 pt is large text for the FR-042 thresholds — `textSize` in the data model and `contracts/note-document.schema.json` changed from the illustrative small/regular/large/extraLarge enum to the integer point size), **FR-095a** (screenshot viewer in an independent borderless note-style window; zoom 25%–400% in 25% steps via scroll/pinch, ⌘+/- equivalents, double-click actual-size/fit-to-window; arrow-key navigation between same-note screenshots; Return/double-click enters caption editing), and **FR-054** (cross-block text selection; copy places plain + rich text with supported formatting only; delete removes only selected characters and merges emptied blocks per FR-050a; trailing padding paragraph never selectable). Tests written FIRST and must FAIL (Constitution XII).

### Tests for Phase 23 (write FIRST, must FAIL) ⚠️

- [X] T250 [P] [US1] SystemBridge test: menu-bar library window frame per FR-001a — given the menu-bar icon frame at various x positions and near screen edges: assert the library window's left edge aligns with the icon's left edge, the window is clamped fully inside the visible screen frame, and the window's top sits 4 pt below the bottom of the menu bar; assert presentation/dismissal perform NO animation (instant, so the SC-001 ≤150 ms warm-presentation target is measurable without animation interference) in `Packages/StickyCore/Tests/SystemBridgeTests/MenuBarWindowFrameTests.swift` per FR-001a / research R40 / plan §Application scenes / Constitution X/XI/II — **no task covers library window positioning (CHK001)**
- [X] T251 [P] [US2] App/Domain test: card preview truncation + last-modified time per FR-020a — assert the body preview truncates at 2 rendered lines with a trailing ellipsis at the card's current width (line-level, not character-level; 1-line vs 2-line vs CJK/long-word cases), the preview draws from the note's first rich-text block and never duplicates the generated summary title (FR-021), and the last-modified time is relative ("5 min ago") within the last 7 days and absolute ("Aug 1", with the year when in a previous calendar year) beyond it; assert the deterministic boundary per FR-020a: age = exactly 7 days renders relative, age = 7 days + 1 second renders absolute in `AppTests/CardRenderingTests.swift` and `Packages/StickyCore/Tests/DomainTests/NoteCardPreviewTests.swift` per FR-020a / research R40 / spec §FR-020a / Constitution X/XI — **no task quantifies preview truncation or the time format (CHK007/CHK019)**
- [X] T252 [P] [US3] Domain test: textSize numeric range per FR-043a — assert `NoteAppearance.textSize` is the integer point size (9–24 inclusive accepted, <9 / >24 / non-integers rejected), defaults to 13, and that ≥18 pt is classified as large text for the FR-042 thresholds (17 vs 18 pt boundary) in `Packages/StickyCore/Tests/DomainTests/NoteAppearanceTests.swift` (extends T046) per FR-043a / research R41 / spec §FR-043a / Constitution X/XI/IV — **T046 covers persistence at the old enum; FR-043a requires the numeric 9–24 model**
- [X] T253 [P] [US7] App integration test: screenshot viewer interaction per FR-095a — assert the viewer opens in an independent borderless note-style window (several viewers MAY coexist; images drag out); zoom is bounded 25%–400% in 25% steps (24% clamps to 25%, 400% is max); scroll/pinch and ⌘+/⌘- equivalents change zoom; double-click toggles actual size (100%) ↔ fit-to-window; arrow keys navigate between the same note's screenshots; Return (or double-click on a screenshot) enters caption-editing mode in `AppTests/ScreenshotViewerInteractionTests.swift` per FR-095a / research R42 / spec §FR-095a / Constitution X/XI/II — **T086/T092 cover viewer capabilities but not the bounded zoom-step contract, keyboard navigation, or window container**
- [X] T254 [P] [US1] EditorCore test: cross-block selection per FR-054 — assert selection spans block boundaries (paragraph/list item/todo item/heading); copying places both plain-text and rich-text (RTF/HTML) representations with ONLY application-supported formatting (FR-053); deleting removes only the selected characters and an emptied block is merged away per FR-050a with a single Undo restoring; the trailing empty padding paragraph is never selectable in `Packages/StickyCore/Tests/EditorCoreTests/CrossBlockSelectionTests.swift` per FR-054 / research R43 / spec §FR-054 / Constitution V/X/XII — **no task covers spanning selection, clipboard output, or range-delete semantics (CHK114)**
- [X] T260 [P] [US7] Persistence test: cover-screenshot nullification per FR-094b — create a note with two screenshot blocks, select one as the card cover, delete that block: assert `Note.coverScreenshotBlockId` is nullified within the same transaction (FK ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED, T152), no dangling reference is ever observable, and the note card falls back to a no-cover state with no extra confirmation in `Packages/StickyCore/Tests/PersistenceTests/CoverScreenshotTests.swift` per FR-094b / spec §Edge Cases / Constitution IV — **no task cites FR-094b**

### Implementation for Phase 23

- [X] T255 [US1] Implement menu-bar library window positioning per FR-001a — add a SystemBridge placement helper (status-item icon frame → left-edge-aligned frame, clamped to the visible screen frame, top 4 pt below the menu bar; no `NSAnimationContext`, so open/dismiss are instant) and wire it into the `MenuBarLibraryScene` presentation (extends T032/T159) in `Packages/StickyCore/Sources/SystemBridge/MenuBarWindowFrame.swift` (new) and `App/Sources/Features/Library/MenuBarLibraryScene.swift` per FR-001a / research R40 / plan §Application scenes / Constitution X/II/XI — **T032/T159 scope the scene contents but not its frame/animation behavior**
- [X] T256 [US2] Implement deterministic card preview truncation + last-modified time formatting per FR-020a — in `App/Sources/Features/Library/NoteCardView.swift` (extends T162) truncate the body preview at 2 rendered lines with a trailing ellipsis (line-aware at the card's current width, drawn from the first rich-text block, never duplicating the generated summary title per FR-021); in `App/Sources/Features/Shared/Formatters.swift` (extends T172) render last-modified time relative within the last 7 days and absolute (with the year when in a previous calendar year) beyond, locale-aware per FR-180a per FR-020a / research R40 / plan §Application scenes / Constitution X/XI — **T162 renders the preview but has no truncation or time rule (CHK007/CHK019)**
- [X] T257 [US3] Implement bounded per-note textSize (9–24 pt, 1-pt steps, default 13) per FR-043a — change `NoteAppearance.textSize` to the integer point size with 9–24 range validation (text ≥18 pt flagged as large text for the FR-042 thresholds) in `Packages/StickyCore/Sources/Domain/Models/NoteAppearance.swift`, and expose the 16-step range in the upper-area control in `App/Sources/Features/NoteWindow/NoteControlsView.swift` (extends T165) per FR-043a / research R41 / spec §FR-043a / Constitution X/XI/IV — **T165 exposes a text-size control without the bound range; data model + schema already updated to the integer model (plan Phase 23 propagation)**
- [X] T258 [US7] Implement the screenshot viewer interaction contract per FR-095a — in `App/Sources/Features/Capture/ScreenshotViewer.swift` (extends T092/T168): present the viewer in an independent borderless note-style window matching FR-030a (multi-window model, several viewers MAY coexist); model zoom as the bounded step set 25%–400% (25% steps; scroll/pinch + ⌘+/- equivalents; double-click toggles actual size ↔ fit-to-window); arrow keys navigate between the same note's screenshots; Return (or double-click on a screenshot) enters caption-editing mode; the viewer never activates the captured application per FR-095a / research R42 / spec §FR-095a / Constitution X/XI/II — **T092 implements the capability list without the bounded zoom steps, keyboard navigation, or window-container rule (CHK008)**
- [X] T259 [US1] Implement cross-block selection semantics per FR-054 — in `Packages/StickyCore/Sources/EditorCore/CrossBlockSelection.swift` (new) + `RichTextAdapter.swift` (extends T036/T161): support a selection spanning block boundaries (per-block character offsets); clipboard copy emits plain + rich (RTF/HTML) representations containing only supported formatting (FR-053); range-delete removes only the selected characters and delegates emptied-block merging to the FR-050a `BlockMergeOperation` (T235) as ONE undo group; the trailing empty padding paragraph is excluded from the selectable range; wire into `App/Sources/Features/Editor/RichTextBlockView.swift` per FR-054 / research R43 / spec §FR-054 / Constitution V/X/XII — **selection currently stops at block boundaries (CHK114)**
- [X] T261 Add constraint-verification tasks citing FR-142/FR-143/FR-190 — (a) extend the existing offline/network-failure test tasks (T118/T119 sync-offline family) to cite FR-142 explicitly (network failures MUST NEVER block local editing, FR-142); (b) add a dependency/architecture audit task asserting FR-143 + FR-190: `Package.resolved` contains only GRDB + the audited Argon2id package, no analytics/telemetry SDKs or developer-service endpoints exist in code, and the quickstart acceptance steps include an offline-completeness + no-telemetry check per FR-143/FR-190 / spec §FR-143/§FR-190 / Constitution I/III/VI — **constraint FRs have zero task citations**

**Checkpoint**: FR-001a, FR-020a, FR-043a, FR-095a, FR-054, FR-094b, FR-142/FR-143/FR-190 have test + implementation tasks. Tests T250–T254 and T260 must FAIL before T255–T259 and T261 are implemented (Constitution XII). Phase 23 depends on: T032/T159 (MenuBarLibraryScene — extended by T255), T162 (NoteCardView — extended by T256), T172 (Formatters — extended by T256), T046/T165 (NoteAppearance + NoteControlsView — extended by T252/T257), T092/T168 (ScreenshotViewer — extended by T253/T258), T036/T161 (RichTextBlockView/RichTextAdapter — extended by T254/T259), T235 (BlockMergeOperation — reused by T259), T152 (FK verified by T260), T118/T119 (offline/network-failure tests — cited by T261). The data model + `contracts/note-document.schema.json` were already updated to the integer textSize in the plan phase; T252/T257 verify and implement the Domain/UI sides. Additive; blocks nothing in Phases 3–22.

---

## Phase 24: Convergence — 2026-08-07 Session-2 Clarifications (FR-009 sheet rule, FR-011a, FR-014c, FR-050b, FR-141b, FR-180b)

**Purpose**: Propagate the six binding requirements clarified in the session-2 `/speckit.clarify` run (closing `checklists/ux.md` gaps CHK006/CHK015/CHK055/CHK061/CHK080/CHK084): **FR-009** (clicking the menu-bar icon while an app-modal sheet is open leaves the sheet open and toggles the library normally — the toggle never dismisses an open sheet), **FR-011a** (library/search exception guarantee: failures never crash/lose data and surface non-blocking; window-open failure leaves the library usable with retry; search no-results renders the FR-014c empty-state and is never an error), **FR-014c** (unified empty-state component — localized message + icon, no CTA — shared by search no-results and empty Trash; distinct from the FR-014a first-launch CTA variant), **FR-050b** (unified block container style consistent with FR-030a; per-category distinguishing affordances only; per-block pixel values are implementation choices), **FR-141b** (async-feedback split policy: silent for background ops — autosave/search/thumbnail; explicit non-blocking status for user-initiated ops — capture/manual sync/export-import), and **FR-180b** (scoped VoiceOver labeling: platform defaults for standard controls; explicit localized labels/actions for custom-built controls; required announcements for deletion toast + user-initiated op completion). Tests written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: None of the six FRs have existing task coverage (grep-cited 0 times). FR-009's sheet rule extends T033/T159 re-click logic; FR-011a extends the library error paths being built by T159/T160; FR-014c is a new shared component (T208 covers the distinct first-launch variant); FR-050b is a shared container style across the block views of T161/T166/T168; FR-141b is a UI policy over T168 (capture), T170 (sync status), T233 (export/import), T036/T161 (editor autosave/search); FR-180b extends T172 (Accessibility) and T246 (deletion toast).

### Tests for Phase 24 (write FIRST, must FAIL) ⚠️

- [X] T262 [P] [US1] App integration test: FR-009 sheet-over-library toggle rule — with an app-modal sheet open (Settings, Save As, export dialog) attached to the library or note window, click the menu-bar icon: assert the sheet stays open; assert the library toggles exactly per FR-009 (focused → dismissed, unfocused → focused, never a second library window); assert the toggle NEVER dismisses an open sheet in `AppTests/LibrarySheetToggleTests.swift` per FR-009 / spec §Edge Cases / Constitution X — **no task covers the sheet-over-library edge case (CHK061)**
- [X] T263 [P] [US1] App integration test: FR-011a library/search exception guarantee — (a) force a note-window-open failure (injected error from `NoteWindowCoordinator`): the library remains fully usable, a non-blocking localized status message reports the failure, and retrying the open action succeeds; (b) a sort-switch failure and a manual-reorder failure never crash and never leave a partial observable order (FR-022a transactionality); (c) search with no matching results renders the unified empty-state (FR-014c) and is NEVER treated as an error in `AppTests/LibraryExceptionGuaranteeTests.swift` per FR-011a / spec §FR-011a / Constitution X/III/XII — **no task cites FR-011a (CHK055)**
- [X] T264 [P] [US2] App test: FR-014c unified empty-state — with a non-empty library: (a) a search query matching nothing renders the unified empty-state component (localized message + icon, NO call-to-action, no other content); (b) opening Trash while it is empty renders the SAME component with the same spacing/visual style; (c) the first-launch empty-library variant (FR-014a CTA + onboarding hint) is a distinct component and is never substituted for the unified empty-state; (d) both messages resolve from the localization catalogs (zh-Hans + en, FR-180a) in `AppTests/UnifiedEmptyStateTests.swift` per FR-014c / spec §FR-014c / Constitution X/XII — **no task cites FR-014c; CHK014 partially resolved**
- [X] T265 [P] [US1] App test: FR-050b unified block presentation — assert all six block categories (rich text, todo, code, file-reference, embedded image, screenshot) render with ONE unified container style: no per-block borders or backgrounds by default, consistent vertical block spacing, corner-radius family per FR-030a; distinguishing affordances only (todo checkbox, monospaced code font, compact file card with FR-100 fields, framed media from the FR-094a thumbnail); assert no pixel-level per-category styling is required beyond the affordances in `AppTests/BlockPresentationConsistencyTests.swift` per FR-050b / spec §FR-050b / Constitution X/II — **no task cites FR-050b (CHK006)**
- [X] T266 [P] [US1] App integration test: FR-141b async-feedback split policy — (a) background operations (autosave per FR-141a, search query update per FR-024a, thumbnail generation per FR-094a) show NO progress indicator, spinner, or completion toast, and the interface stays fully interactive; (b) user-initiated operations (screenshot capture per FR-091, manual synchronization per FR-151, single-note JSON export/import per FR-031a) show explicit non-blocking status feedback (status text/indicator in the relevant surface, localized per FR-180a); (c) no async operation blocks typing or other interaction (FR-153) in `AppTests/AsyncFeedbackPolicyTests.swift` per FR-141b / spec §FR-141b / Constitution X/XI — **no task cites FR-141b (CHK015)**
- [X] T267 [P] [US3] App accessibility test: FR-180b scoped labeling — (a) standard platform controls (buttons, menus, text fields, sliders, toggles, table rows) rely on platform-provided labels/actions with NO custom labels duplicating visible text; (b) custom-built controls expose explicit localized labels and actions: file-reference card (open/reveal/copy path/relink/move/remove per FR-101), screenshot viewer (zoom/actual size/fit-to-window/copy/drag-out/Save As/delete association/edit caption/navigation per FR-095a), upper-area hover controls (FR-031), editor block affordances (todo checkbox with completed/incomplete state, code-block copy button, image/screenshot blocks); (c) VoiceOver announces the deletion toast (FR-009a) and completion of user-initiated operations with explicit status feedback (capture/sync/export-import per FR-141b) in `AppTests/ScopedAccessibilityLabelsTests.swift` per FR-180b / spec §FR-180b / Constitution X/XII — **no task cites FR-180b (CHK080/CHK084)**

### Implementation for Phase 24

- [X] T268 [US1] Implement FR-009 sheet-over-library toggle rule — in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (extends T033/T159): the menu-bar-icon toggle path MUST NOT dismiss any open app-modal sheet (Settings, Save As, export dialog); the library toggles exactly per FR-009 (focused → dismissed, unfocused → focused, never a second window) while the sheet remains open; verify no `dismiss` is routed to sheet content on the icon-click path per FR-009 / spec §FR-009/Edge Cases / Constitution X — **T033/T159 implement re-click without the sheet rule (CHK061)**
- [X] T269 [US1] Implement FR-011a library/search exception guarantee — in `App/Sources/Features/Library/MenuBarLibraryScene.swift` (extends T159) and `App/Sources/Features/NoteWindow/NoteWindowCoordinator.swift` (extends T160): wrap library actions (open note window, toggle/dismiss, sort switch, manual reorder, search) so failures NEVER crash, NEVER lose/corrupt data, and surface as a non-blocking localized status message when user-visible (FR-141b/FR-191 sanitization); window-open failure keeps the library usable and permits retry; search no-results routes to the unified empty-state (T270), never an error; sort/reorder failures rely on the general guarantee + FR-022a transactional persistence (no partial order observable) per FR-011a / spec §FR-011a / Constitution X/III — **no library error-handling policy exists (CHK055)**
- [X] T270 [US2] Implement the unified empty-state component per FR-014c — create `App/Sources/Features/Shared/EmptyStateView.swift` (localized message + icon, NO call-to-action, no other content; one component, spacing, and visual style); wire it into search no-results in `LibrarySearchView.swift` (extends T164) and empty Trash in `TrashView.swift` (extends T167); the first-launch empty-library variant (`EmptyLibraryView`, T208) remains distinct with its CTA + onboarding hint and is never substituted per FR-014c / spec §FR-014c / Constitution X — **no shared empty-state exists (CHK014)**
- [X] T271 [US4] Implement the unified block container style per FR-050b — create a shared block-container modifier/component in `App/Sources/Features/Editor/BlockContainer.swift` (new) applying one container style consistent with FR-030a (no per-block borders/backgrounds by default, consistent vertical spacing, corner-radius family) and apply it to all block views: `RichTextBlockView` (T161), `TodoBlockView`/`CodeBlockView`/`FileReferenceCardView` (T166), `ScreenshotBlockView`/`EmbeddedImageBlockView` (T168); category distinction comes ONLY from inherent affordances (todo checkbox, monospaced code font per FR-080, compact file card with FR-100 fields, framed media from the FR-094a thumbnail); no per-category pixel values beyond the affordances per FR-050b / spec §FR-050b / Constitution X/II — **block views style independently (CHK006)**
- [X] T272 [US1] Implement the FR-141b async-feedback split policy — (a) background ops: ensure autosave (T238), search updates (T164), and thumbnail generation (T236) render NO progress indicator/spinner/toast; (b) user-initiated ops: capture (T168), manual sync (T170 `SyncStatusView`), and JSON export/import (T233) surface explicit non-blocking status text/indicator in the relevant surface, localized per FR-180a; (c) verify no async path blocks typing or interaction (FR-153) in `App/Sources/Features/Library/SyncStatusView.swift`, `App/Sources/Features/Capture/`, `App/Sources/Features/NoteWindow/NoteExportImport.swift` per FR-141b / spec §FR-141b / Constitution X/XI — **no feedback policy exists (CHK015)**
- [X] T273 [US3] Implement FR-180b scoped VoiceOver labeling — extend `App/Sources/Features/Editor/Accessibility.swift` / `App/Sources/Features/NoteWindow/AccessibilityAdaptations.swift` (extends T172): standard controls rely on platform labels (no custom duplicates of visible text); add explicit localized labels/actions to custom-built controls — file-reference card (open/reveal/copy path/relink/move/remove per FR-101), screenshot viewer (zoom/actual size/fit-to-window/copy/drag-out/Save As/delete association/edit caption/navigation per FR-095a), upper-area hover controls (FR-031), editor block affordances (todo checkbox completed/incomplete per FR-070/FR-182, code-block copy button per FR-081, image/screenshot blocks); VoiceOver announcements: deletion toast (T246 per FR-009a) and completion of user-initiated ops with explicit status (capture/sync/export-import per T272/FR-141b) per FR-180b / spec §FR-180b / Constitution X — **labels are generic "meaningful labels" (CHK080/CHK084)**

**Checkpoint**: All six session-2 clarifications have test + implementation tasks. Tests T262–T267 must FAIL before T268–T273 are implemented (Constitution XII). Phase 24 depends on: T033/T159 (MenuBarLibraryScene — extended by T268/T269), T160 (NoteWindowCoordinator — extended by T269), T164 (LibrarySearchView — extended by T270), T167 (TrashView — extended by T270), T208 (EmptyLibraryView — kept distinct by T270), T161/T166/T168 (block views — restyled by T271), T238 (autosave — verified silent by T272), T236 (thumbnail — verified silent by T272), T170 (SyncStatusView — extended by T272), T233 (NoteExportImport — extended by T272), T172 (Accessibility — extended by T273), T246 (deletion toast — announced by T273). Additive; blocks nothing in Phases 3–23.

**Implementation audit summary** (verify-only vs requires changes):
- FR-009 sheet rule (open sheet + toggle): ✗ no sheet handling on icon-click path — T262 verify, T268 implement
- FR-011a (library/search exception guarantee): ✗ no error-handling policy — T263 verify, T269 implement
- FR-014c (unified empty-state): ✗ no shared component — T264 verify, T270 implement
- FR-050b (unified block presentation): ⚠ block views style independently — T265 verify, T271 implement
- FR-141b (async-feedback split policy): ⚠ status surfaces exist for sync only — T266 verify, T272 implement
- FR-180b (scoped VoiceOver labeling): ⚠ generic labels only — T267 verify, T273 implement

---

## Phase 25: Convergence — 2026-08-07 Session-3 Clarifications (FR-021, FR-100, FR-112, SC-006)

**Purpose**: Propagate the five binding requirement extensions from the session-3 `/speckit.clarify` run (closing the last `checklists/ux.md` gaps — CHK009/CHK014/CHK063/CHK076/CHK095): **FR-021** (two notes with byte-identical first meaningful content MAY have identical generated summaries; cards remain distinguishable via the other deterministic card fields — last-modified time, color, 2-line preview per FR-020a; no summary disambiguation rule), **FR-100** (file-reference card icon size and metadata layout are implementation choices per FR-050b; the availability-status indicator MUST distinguish available / missing / stale (bookmark unresolved but file may exist) / on-another-device (FR-104), each by more than color alone per FR-044), **FR-112** (widget-eligibility toggle is a note-level action in the note's contextual menu with the other FR-031 note-level actions, keyboard-accessible per FR-181, NOT on the upper-area control bar; when no eligible note exists — every note excluded, or configured note deleted/trashed/conflicted — the widget presents the sanitized FR-140a "temporarily unavailable" placeholder, localized, no content, no note title, never implying an excluded note exists), and **SC-006** (VoiceOver traversal latency not separately quantified — dominated by the system accessibility engine; SC-004a and SC-006 remain the accessibility performance guarantees). Tests written FIRST and must FAIL before implementation (Constitution XII).

**Implementation audit (2026-08-07)**: FR-021's collision acceptance is a Domain/rendering rule with no existing coverage (T162/T256 render the summary; T251 verifies truncation); FR-100's indicator states are unimplemented (T166/T271 build the card); FR-112's toggle placement affects the contextual menu (T248) and widget snapshots (T169); the no-eligible-note widget fallback affects widget placeholders (T101/T169); SC-006's clarification is a spec-note with no implementation burden but warrants a test-doc alignment check.

### Tests for Phase 25 (write FIRST, must FAIL) ⚠️

- [X] T274 [P] [US2] Domain test: identical-summary collision acceptance per FR-021 — two notes whose first meaningful content is byte-identical: assert both generate identical summary strings (no disambiguation suffix); assert the cards remain distinguishable through the other deterministic fields (last-modified time, note color, 2-line body preview per FR-020a); assert the generated summary never becomes a permanent manual title per FR-021 in `Packages/StickyCore/Tests/DomainTests/IdenticalSummaryCollisionTests.swift` per FR-021 / spec §FR-021 / Constitution IV/X — **no task covers summary collision (CHK063)**
- [X] T275 [P] [US4] App test: file-reference card availability-status indicator per FR-100 — assert the indicator distinguishes four states: available (file resolves), missing (file unavailable, relink offered per FR-103), stale (bookmark unresolved but file may exist), on-another-device (synchronized generic metadata with no local file per FR-104); assert each state is communicated by more than color alone (FR-044); assert icon size and metadata layout are not pinned by any per-category spec (FR-050b) in `AppTests/FileRefIndicatorStatesTests.swift` per FR-100 / spec §FR-100/FR-103/FR-104/FR-050b / Constitution X/IX — **no task enumerates indicator states (CHK009)**
- [X] T276 [P] [US8] App/Widget test: widget-eligibility toggle placement + no-eligible-note fallback per FR-112 — (a) assert the widget-eligibility toggle is a note-level action in the note's contextual menu (with duplicate/export-as-JSON/copy-as-Markdown/move-to-Trash per FR-031), keyboard-accessible per FR-181, and NOT on the upper-area control bar (FR-031); (b) with all notes widget-excluded or the configured note deleted/trashed/conflicted, assert every widget form shows the sanitized "temporarily unavailable" placeholder (FR-140a) — localized, no content, no note title, no implication that an excluded note exists in `AppTests/WidgetEligibilityUxTests.swift` per FR-112 / spec §FR-112/FR-140a / Constitution VI/XI — **no task covers toggle placement or the no-eligible-note fallback (CHK095/CHK014)**
- [X] T277 [P] [US2] Docs-alignment test: SC-006 VoiceOver-note alignment — assert the spec's SC-006 accessibility-performance note (VoiceOver traversal latency not separately quantified; SC-004a/SC-006 remain the guarantees) is reflected in the editor performance test documentation and that no test asserts a VoiceOver traversal latency target (avoiding a non-actionable assertion) in `Packages/StickyCore/Tests/EditorCoreTests/KeystrokeLatencyTests.swift` (T205) per SC-006 / spec §SC-006 / Constitution X/XI — **no task aligns tests with the SC-006 note (CHK076)**

### Implementation for Phase 25

- [X] T278 [US2] Implement identical-summary collision acceptance per FR-021 — in `Packages/StickyCore/Sources/Domain/Models/NoteSummary.swift` (or the card summary generation path used by T162/T256): generate the temporary summary from the first meaningful content WITHOUT any disambiguation suffix (byte-identical content → identical summaries); keep the summary temporary (never silently a permanent manual title per FR-021); card differentiation relies on last-modified time, color, and the FR-020a 2-line preview (T256) per FR-021 / spec §FR-021 / Constitution IV/X — **summary generation has no collision rule; no disambiguation may be added (CHK063)**
- [X] T279 [US4] Implement file-reference card availability-status indicator per FR-100 — in `App/Sources/Features/Editor/FileReferenceCardView.swift` (extends T166) and the underlying `FileAvailability` state (`Packages/StickyCore/Sources/Domain/Models/Enums.swift`, T012): map bookmark resolution outcomes to the four states — available / missing / stale (bookmark unresolved but file may exist) / on-another-device (FR-104 generic metadata, no local file); render each state with more than color alone (FR-044, e.g. icon + text); icon size and metadata layout remain implementation choices per FR-050b (T271) per FR-100 / spec §FR-100/FR-103/FR-104/FR-044/FR-050b / Constitution X/IX — **the card renders a single availability boolean; the four-state model is missing (CHK009)**
- [X] T280 [US8] Implement widget-eligibility toggle placement + no-eligible-note fallback per FR-112 — (a) add the widget-eligibility toggle as a note-level action in the contextual menu built by T248 (`App/Sources/Features/NoteWindow/NoteControlsView.swift` contextual menu), keyboard-accessible per FR-181, NOT on the upper-area control bar; (b) in `WidgetExtension/WidgetSnapshots.swift` (extends T101/T169), when no eligible note exists for a widget (all notes excluded, or configured note deleted/trashed/conflicted), render the sanitized FR-140a "temporarily unavailable" placeholder — localized, no content, no note title, never implying an excluded note exists per FR-112 / spec §FR-112/FR-140a/FR-031 / Constitution VI/XI — **the eligibility setting exists as a data field (T012/T169) but has no placement or no-eligible-note widget fallback (CHK095/CHK014)**

**Checkpoint**: All five session-3 clarifications have test + implementation tasks. Tests T274–T277 must FAIL before T278–T280 are implemented (Constitution XII). Phase 25 depends on: T162/T256 (NoteCardView summary rendering — extended by T278), T166 (FileReferenceCardView — extended by T279), T012 (FileAvailability enum — extended by T279), T248 (contextual menu — extended by T280), T101/T169 (WidgetSnapshots — extended by T280), T205 (KeystrokeLatencyTests — aligned by T277). Additive; blocks nothing in Phases 3–24.

**Implementation audit summary** (verify-only vs requires changes):
- FR-021 (identical summaries accepted): ⚠ summary generation exists, no collision rule — T274 verify, T278 confirm no disambiguation
- FR-100 (indicator four states): ✗ single availability boolean — T275 verify, T279 implement four-state model
- FR-112 toggle placement (contextual menu): ✗ eligibility setting has no placement — T276 verify, T280 implement
- FR-112 no-eligible-note fallback (FR-140a placeholder): ✗ widget shows no defined fallback — T276 verify, T280 implement
- SC-006 VoiceOver note (not quantified): ⚠ spec-only note; test docs must not assert traversal targets — T277 verify alignment

<!-- token-budget: compacted (level=medium) on 2026-08-07T08:56:41Z; original at tasks.full.md -->
