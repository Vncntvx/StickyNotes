# AGENTS.md

Specs-first repository for "macOS Sticky Notes" — a native, menu-bar-primary sticky-notes app for macOS 26+. **No application code exists yet**; everything lives in the single feature dir `specs/001-sticky-notes-app/` (spec, plan, tasks, research, data-model, quickstart, contracts/). Only one commit exists; work is driven through the Spec Kit (speckit) workflow, not ad-hoc editing.

## Workflow (critical)

- Use the speckit commands/skills (`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.implement`, …) wired in `.opencode/commands/` and `.claude/skills/`. Run them in order: specify → plan → tasks → implement, with review gates.
- `spec.md`, `plan.md`, and `tasks.md` are authoritative design artifacts. Implement per `tasks.md` — it defines exact repository paths (`App/Sources/…`, `Packages/StickyCore/Sources/{Domain,Persistence,EditorCore,AssetStore,SecurityCore,SyncCore,SystemBridge}`) and module boundaries. (The `WidgetExtension/` target was removed 2026-08-13 with the widget surface.) Do not invent structure that contradicts the plan.
- Keep artifacts in sync: never change behavior in `spec.md`/`plan.md` outside the speckit flow (`speckit-analyze` checks cross-artifact consistency).
- "macOS Sticky Notes" is a **working title only** — never invent a final product or brand name (spec.md line 9).

## Commit messages (conventional)

格式：`type(scope): :emoji: 主述`，空行后接中文无序列表 body。

```
feat(app): :hammer_and_wrench: 落地 003 设计系统基础与菜单命令体系（FR-021/030-033/072）
- DesignSystem: 新增 NotePalette（七色浅/深独立设计值），旧六色语义映射至新调色板（紫→薰衣草，FR-032），custom 颜色按原值保留
- ReadableTheme: 内置颜色改经 NotePalette 取 per-appearance 设计值渲染（FR-033），custom 颜色保留 001 Domain projection 路径
- App/MenuCommands: 新增 MenuCommandCatalog 作为菜单命令单一来源，动作复用既有 LibraryModel/NoteWindowCoordinator 方法（SC-017/FR-072）
- Tests: 新增 PaletteContrast/Migration/MenuChecklist 覆盖对比度阈值、旧色映射与菜单清单
```

**主述**：中文祈使，不加句号，≤ 50 字符。引用 **FR 编号**而非 Phase/US/任务编号；超限时用 `()` 补 FR 范围。
**body**：每条以**模块/组件名**开头，描述代码**实际做了什么**（具体 API、数据流、关键值、技术决策），而非过程记录。引用 FR/SC/CHK 编号。单行琐碎变更可省略。
**emoji**：按内容语义选取（非 type 绑定）——`✨`新功能 · `🐛`修复 · `📝`文档 · `♻️`重构 · `✅`测试 · `⚡`性能 · `🔧`工具/配置 · `📦`依赖/打包 · `👷`CI · `🏗️`脚手架 · `🗃️`归档/压缩 · `🔨`实现落地 · `🔒`安全 · `🎨`格式 · `🎉`初始化 · `⏪`回滚。
**禁入**：secrets、真实笔记内容、内部链接（遵循 Constitution 净化要求）。

**type**：`feat` 新功能 · `fix` 修复 · `docs` 规格/文档/契约 · `refactor` 重构 · `test` 测试 · `perf` 性能 · `build` 构建/依赖 · `ci` CI/CD · `chore` 工具链/杂项 · `style` 格式 · `revert` 回滚。

**scope（固定集合）**：`core` StickyCore 任一模块 · `app` App/Sources · `specs` specs/ 工件及 .specify/templates · `tools` .specify/.claude/.opencode 工具链 · `scaffold` 跨目标脚手架 · `ci` .github/workflows · `init` 仓库初始化。跨多个取最主要；无合适可省略。

## Documentation lookups (context7 MCP)

Before writing any code that touches a library, framework, or Apple API (GRDB, SwiftUI, OSLog, CryptoKit, …), query context7 for current docs — training data may be stale, and this project targets macOS 26 / Swift 6 APIs.

- Flow: (1) `context7_resolve-library-id` with the library name + what to look up; (2) pick the best match (exact name, benchmark score, source reputation; prefer version-specific IDs when a version matters); (3) `context7_query-docs` scoped to a **single concept** per call — split multi-topic questions into separate `query-docs` calls, max ~3 calls per question.
- Do not use for: refactoring, debugging business logic, code review, or general Swift language knowledge.
- Do not invent or guess API signatures for GRDB/macOS frameworks — verify via context7 first (e.g. GRDB migration + `DatabasePool`/WAL usage, FTS5 search).

## Constitution constraints (non-negotiable)

- **Tests are written FIRST** and must fail before implementation (Constitution Principle XII, tasks.md header).
- Local-first, offline-complete; no developer-operated backend, no analytics/telemetry (FR-140, FR-190).
- Never commit credentials, keys, or real note content in fixtures. Credentials live in Keychain only. Sanitized logs/diagnostics must never contain note content, paths, or secrets (FR-165, FR-191).
- macOS 26 is the minimum deployment target; preserve it regardless of the dev machine's OS.

## Build & test (from quickstart.md — the validation guide)

> **CRITICAL — Xcode-beta discovery (2026-08-07):** the dev machine DOES have
> a full Xcode install at `/Applications/Xcode-beta.app` (Xcode 27.0,
> build 27A5228h; Swift 6.4; macOS 27 beta; `Testing.framework` present).
> But `xcode-select -p` points at `/Library/Developer/CommandLineTools`, so a
> bare `swift`/`swift test`/`xcodebuild` resolves to the CLT toolchain — which
> is **missing `Testing.framework`**, causing every Swift Testing bundle to
> fail with `dlopen … Testing.framework … no such file`. The previous claim
> "this machine has only CLT" was stale. Fix by prefixing every build/test
> command with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
> (no `sudo xcode-select` needed — keeps the system default on CLT for other
> tools). Verified: with that prefix, `swift test` runs all suites green.

```bash
# StickyCore package (Swift Testing works only under Xcode-beta):
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore

# App target (now buildable on this machine via Xcode-beta):
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -project StickyNotes.xcodeproj -scheme StickyNotes -configuration Debug CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS'
```

- `CODE_SIGNING_ALLOWED=NO` for local debug builds.
- **Manual testing on this Mac**: run `scripts/sign-local.sh` instead of the
  raw unsigned build + ad-hoc sign recipe. It builds Debug and signs the app
  with the STABLE Apple Development identity
  (`Apple Development: wenjie.xu.sino@foxmail.com (SJFRS6Q8GH)`, override via
  `IDENTITY=...`), and relaunches the app. Ad-hoc signing (`codesign -s -`)
  changes the CDHash on every rebuild, so macOS re-prompts for the Keychain
  password on every launch (sync credentials / remembered-unlock items are
  ACL-bound to the previous signature). A stable identity prompts only the
  first time. CI keeps ad-hoc signing (no keychain on runners).
- Test suites: `Packages/StickyCore/Tests/{DomainTests,PersistenceTests,EditorCoreTests,AssetStoreTests,SecurityCoreTests,SyncCoreTests,SystemBridgeTests}` (+ migration fixtures `Fixtures/schema_vN.sqlite`). All run via the `DEVELOPER_DIR=…` prefix above.
- Credentialed WebDAV/S3 sync tests are opt-in via CI secrets (`STICKY_WEBDAV_TEST_*`, `STICKY_S3_TEST_*`) and must be skipped when absent — never commit real credentials.
- Naming inconsistency between docs: `tasks.md` T001 says workspace + app target `App`; `quickstart.md` uses `StickyNotes.xcodeproj` / scheme `StickyNotes`. Reconcile before Phase 1 work.
- App Group container + WidgetExtension removed 2026-08-13: the SQLite database and assets live in the app sandbox container (`Library/Application Support`); device-local prefs use standard UserDefaults.

## Environment gotchas

- **Local toolchain (verified 2026-08-07):** `/Applications/Xcode-beta.app` — Xcode 27.0 (27A5228h), Swift 6.4, macOS 27 beta. `Testing.framework` is available under `…/Platforms/MacOSX.platform/Developer/Library/Frameworks/`. Always invoke build/test with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (system default still points at CLT, which lacks `Testing.framework`).
- **Intended CI toolchain:** Xcode 26.x, Swift 6.3, Swift 6 language mode, strict concurrency, macOS 26 deployment target. The local Xcode 27 beta is NEWER than CI — code that compiles locally may need to stay within the macOS 26 API surface. Record the actual toolchain in `Documentation/toolchain.md` (task T008); do not silently change the deployment target or language mode.
- Intended architecture: modular monolith — app target + one local Swift package `StickyCore` (7 modules). GRDB SQLite (WAL, FTS5) in the app sandbox container is the source of truth; Keychain for credentials/secrets; sync is an additive E2E-encrypted layer (WebDAV or S3-compatible, one at a time).
- Intended architecture: modular monolith — app target + one local Swift package `StickyCore` (7 modules). GRDB SQLite (WAL, FTS5) in the app sandbox container is the source of truth; Keychain for credentials/secrets; sync is an additive E2E-encrypted layer (WebDAV or S3-compatible, one at a time).

<!-- BEGIN token-budget compact-backups -->

## Token Budget — backup guard

Files ending in `.full.md` inside `specs/` and `.specify/memory/`
(e.g. `spec.full.md`, `plan.full.md`) are pre-compaction backups created
by `/speckit.token-budget.compact`. **Do not read them.** They contain the
full uncompacted content; loading them cancels the token savings compaction
achieved. To revert an artifact to its original state, run
`/speckit.token-budget.restore` instead.

<!-- END token-budget compact-backups -->

<!-- BEGIN token-budget concise-mode -->

## Token Budget — concise mode (active)

When executing any `/speckit.*` command (constitution, specify,
clarify, plan, tasks, analyze, implement, checklist,
token-budget.*), follow these output rules:

- Do not narrate plans, intentions, or steps. Run them.
- Do not recap the user's prompt back to them.
- Do not announce file writes ("I'll create...", "Now writing..."). Just write.
- Use terse technical fragments, not full sentences. Write "Updated auth.ts" not "I went ahead and updated auth.ts in order to...".
- No acknowledgment openers ("Sure!", "Of course!", "Great idea!") and no closing remarks ("I hope this helps", "Let me know if you need anything else").
- No transitional summaries between steps ("Now I'll...", "Next, I will..."). Just execute.
- After completing the command, output only:
  1. The list of files created or changed, one per line.
  2. Any blocking question or unmet assumption, in one sentence.
  3. The single line "Done." if there is nothing else to report.
- Tables, fenced code, and structured data inside artifacts are
  unaffected — this rule governs only the chat-channel prose around
  them.
- Override on request: if the user explicitly asks "explain", "walk
  me through", "why", or "what did you do", drop concise mode for
  that single reply and answer normally.

These rules apply only inside `/speckit.*` workflows. Conversational
replies outside SDD steps are not affected.

<!-- END token-budget concise-mode -->

