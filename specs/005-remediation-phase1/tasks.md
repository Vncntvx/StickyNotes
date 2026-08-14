# Tasks: Remediation Phase 1 — 紧急止血与数据安全

**Input**: `specs/005-remediation-phase1/spec.md` + `plan.md` + `Documentation/remediation-roadmap-2026-08-15.md` §2

**Prerequisites**: spec.md ✅, plan.md ✅, roadmap ✅（审计报告依据已归档）

**Tests**: TDD 强制（Constitution XII）——每个 story 的 Red Test 任务必须先于实现任务提交并演示失败。

**Organization**: 按修复项（R1.1–R1.7）分组，每个修复项是独立可验证的增量；Setup 阶段挂接 CI 门控（Roadmap §5 G1/G3/G4）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: R1.1–R1.7（映射 spec.md 的 7 个修复项）
- 所有任务含精确文件路径

## 验证命令（AGENTS.md 前缀）

- Core: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore`
- App: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

---

## Phase 1: Setup — CI 工程化门控（Roadmap §5，首日挂接）

**Purpose**: 拦截"测试自证"与"临时调试物"两类技术债复发；建立竞态复跑稳定性基线

- [X] T001 [P] 新增 `scripts/check-empty-assertions.sh`：扫描 `AppTests/**/*.swift`，任何无配套 `Issue.record`/显式说明注释的裸 `#expect(true)` 与字面量 `#expect(!x.isEmpty)` 即非零退出（合法 fail-closed catch 配对需注释豁免）
- [X] T002 [P] 新增 `scripts/check-debug-artifacts.sh`：扫描 `App/Sources` 内 `NSTemporaryDirectory()` 直写日志与未 `#if DEBUG` 包裹的调试文件写入，命中即非零退出
- [X] T003 在 `.github/workflows/` 现有 CI workflow 挂接 T001/T002（与既有 xcodegen 漂移检查并列，失败即红）
- [X] T004 在 `.github/workflows/` AppTests 测试矩阵加固（Roadmap G4 两部分）：① 并行强制复跑 2 轮（任一轮红即失败）；② 新增 `-AppleLocale zh_CN` locale job（拦截 locale 硬编码断言，为 R3.10 预留）

**Phase 1 验收**：T001/T002 在本地对当前代码库运行即红（存在 21 处裸断言 + DiagnoseLog），证明门控有效。

---

## Phase 2: Foundational — R1.1 保存链路竞态（P0，阻断性数据一致性雷）

**Purpose**: 修复 `pendingEditTask` 覆盖不串联 + `persistBlocks` 非原子 diff 导致已删块被旧快照复活（动态验证实证）

- [X] T005 [R1.1] 写确定性 Red Test：改造 `AppTests/EditorPersistenceTests.swift` 的 `emptyBlockRemovalPersists`——注入可控延迟 repository 包装（第一个结构性保存的 fetch 完成后、写入前 barrier），断言 `flush()` 后 `fetchBlocks` 不含已删块 id；修复前 100% 失败（现有测试在并行全量下已间歇失败，本测试使其确定性）
- [X] T006 [R1.1] 写契约测试 + 签名变更：扩展 `Packages/StickyCore/Tests/EditorCoreTests/AutoSaveTests.swift`——断言 `AutoSaveRevisionToken` 经保存 sink 完整传递（当前 App sink 丢弃 token，测试在 Core 层固化 token 语义契约）。**含包内契约变更**：`AutoSaveSink` 签名需携带 `AutoSaveRevisionToken`（EditorCore/AutoSave.swift），App sink 调用点（`NoteWindowHostModel.swift:65`）同步更新——改动前先跑既有 `AutoSaveTests` 确认契约测试红
- [X] T007 [R1.1] 修复：`App/Sources/Features/NoteWindow/NoteWindowHostModel.swift` —— `updateBlocks` 的保存任务链式串联（`await previous?.value` 模式，参照同文件 `enqueueUndoRestore`）；保存 sink 携带 token 做陈旧写丢弃；`AutoSaveDraftManager`（`Packages/StickyCore/Sources/EditorCore/AutoSave.swift`）按 T006 契约暴露 token
- [X] T008 [R1.1] 验证：T005/T006 绿；全量并行 3 轮 + 串行 1 轮零失败；窗口关闭 flush 不丢最后编辑（既有 `NoteWindowLifecycleTests` 关闭路径保持绿）

**Phase 2 验收**：已删块永不复活；`AutoSaveRevisionToken` 在 DB 层生效。

---

## Phase 3: R1.2 — DiagnoseLog 发布版调试日志清除（P0）

**Purpose**: 移除发布版 `NSTemporaryDirectory()` 明文日志（8 调用点，FR-165/191 违规 + 主线程磁盘 I/O）

- [X] T009 [P] [R1.2] 写 Red Test：扩展 `AppTests` 诊断消毒测试（仿 `DiagnosticsPrivacyTests` 模式）——模拟编辑器焦点/拖动事件序列，断言所有经 `StickyLogger` 出口的日志不含几何数值与响应者状态明细；DiagnoseLog 直写文件绕过 Logger 时断言暴露
- [X] T010 [R1.2] 修复：删除 `App/Sources/Features/Editor/RichTextView.swift` 的 `DiagnoseLog` 及全部调用点（`RichTextView.swift:683/688/1419/1424/1429`、`RichTextBlockView.swift:232`、`EditorSelectionBridge.swift:98/114/117`、`NoteWindowHostModel.swift:519`）；确需保留的调试信息改经 `StickyLogger.debug` 消毒参数
- [X] T011 [R1.2] 验证：T009 绿；`App/Sources` 内 `NSTemporaryDirectory()` 零匹配（T002 门控绿）；Release 构建无该符号；全量测试绿

**Phase 3 验收**：日志出口唯一（StickyLogger）；门控脚本零告警。

---

## Phase 4: R1.3 — 捕获失败吞错修复（P0）

**Purpose**: 捕获失败被吞成空 `Data` 并被当成功截图入库插块（击穿 T303 fail-closed）

- [X] T012 [P] [R1.3] 写 Red Test：`AppTests` 新增捕获失败测试——注入恒抛错 provider，断言 `NoteWindowHostModel.captureScreenshot` 返回 `false`、块列表不变、AssetStore 记录数不变（当前返回 true 并插块 → 失败）
- [X] T013 [P] [R1.3] 写 Red Test：注入空 `Data` provider 断言拒绝导入（不产生资产、不插块）；注入"原图成功/缩略图失败"provider 断言 `thumbnailAssetId` 不得回退为 `originalAssetId`（SC-008，当前回退 → 失败）
- [X] T014 [R1.3] 修复：`App/Sources/Features/Capture/CaptureFlow.swift` 删除 `catch { sink(Data()) }` 吞错，错误向上传播；`NoteWindowHostModel.captureScreenshot`（`App/Sources/Features/NoteWindow/NoteWindowHostModel.swift:1035-1071`）空数据拒收、缩略图缺失时 payload 置 nil；失败经 FR-011a 非阻塞状态面（statusMessage/toast）呈现
- [X] T015 [R1.3] 验证：T012/T013 绿；捕获失败不产生任何资产/块；全量测试绿

**Phase 4 验收**：捕获失败零副作用；空数据零入库。

---

## Phase 5: R1.4 — 截图/图片块真实缩略图渲染（P1）

**Purpose**: 内联块只渲染 SF Symbol 占位，从不加载 `thumbnailAssetId`（FR-094a 声明与实现不符）

- [X] T016 [P] [R1.4] 写 Red Test：提炼"块 payload → 渲染源"状态机为 App 层纯类型（含真实加载/占位/失败三态）——构造含合法 `thumbnailAssetId` 的 screenshot 块 + 注入返回真实 PNG 的 provider，断言状态为"真实缩略图"而非"占位"；provider 返回 nil 断言进入降级占位态（不崩溃）
- [X] T017 [R1.4] 修复：`App/Sources/Features/Editor/ScreenshotBlockView.swift` 与 `RichTextBlockView.swift:113-128` 消费该状态机，经 `AssetStore.readData(thumbnailAssetId)` 加载；占位图标仅作降级态
- [X] T018 [R1.4] 验证：T016 绿；既有 SC-008"卡片网格绝不解码原图"测试保持绿；全量测试绿

**Phase 5 验收**：内联块渲染真实缩略图；降级路径不崩溃。

---

## Phase 6: R1.5 — HTTPS-only 传输强制（P0）

**Purpose**: 宪法 VIII 声明 HTTPS-only 但 WebDAV/S3 适配器无 scheme 校验

- [X] T019 [P] [R1.5] 写 Red Test（`Packages/StickyCore/Tests/SyncCoreTests/`）：构造 `http://` 端点配置，断言 provider 构造或首次 `verify()` 抛出 `StickyError.credentials(.invalidEndpoint)`；`https://` 配置正常通过（当前 http 畅通 → 失败）
- [X] T020 [P] [R1.5] 写 Red Test：声明了 `pinnedFingerprint` 的配置在未实现 pinning 时构造失败（当前字段被静默忽略 → 失败）
- [X] T021 [R1.5] 修复：`Packages/StickyCore/Sources/SyncCore/WebDAVProvider.swift` 与 `S3Provider.swift` 增加 scheme 校验（构造或 verify 边界）；`pinnedFingerprint` 死字段删除或实现 TrustConfiguration（二选一，决策记录进 commit message）
- [X] T022 [R1.5] 联动：`App/Sources/Features/Settings/SyncSettingsView.swift` 端点输入处展示 https 校验提示（本地化文案，`App/Resources/Localizable.xcstrings` 补 key）
- [X] T023 [R1.5] 验证：T019/T020 绿；既有 provider 契约测试（`ProviderHTTPContractTests`）保持绿；全量测试绿

**Phase 6 验收**：非 https 端点全路径拒绝；死字段清零。

---

## Phase 7: R1.6 — Banner/同步状态真实接线（P1）

**Purpose**: `vaultLocked` 硬编码 `false`（needsUnlock 不可达）+ banner 4/5 按钮空操作

- [X] T024 [P] [R1.6] 写 Red Test：构造 `syncCoordinator.isVaultUnlocked == false` 桩状态，断言 `LibraryModel.refreshBanner`（`App/Sources/Features/Library/LibraryModel.swift:96-109`）产出 `.needsUnlock` 类别（当前恒 nil → 失败）
- [X] T025 [P] [R1.6] 写 Red Test：逐类别断言 `authFailed`/`conflictCopiesCreated`/`historyAgedOut`/`pendingChanges` 经 `SyncStatusResolver` 可达；对 `.unlock`/`.reauthenticate`/`.viewConflicts`/`.advancedRecovery` 类别调用 `performBannerAction`（`LibraryModel.swift:118-126`），断言对应 coordinator 方法被调用（当前 default: break → 失败）
- [X] T026 [R1.6] 修复：`LibraryModel.refreshBanner` 与 `SyncSettingsView.resolvedPresentation`（`App/Sources/Features/Settings/SyncSettingsView.swift:241-249`）改接真实状态（`isVaultUnlocked`/`isInProgress`/真实 summary）；`performBannerAction` 补齐 4 个分支动作
- [X] T027 [R1.6] 验证：T024/T025 绿；全量测试绿；既有 `SyncStatusPresentationTests`/`SyncBannerSemanticsTests` 保持绿

**Phase 7 验收**：所有同步状态类别在生产可达；banner 按钮真实触发动作。

---

## Phase 8: R1.7 — 便签 JSON 导入 + 资产 sidecar 真实化（P1）

**Purpose**: 导入无 UI/流程（悬空注释），导出丢弃 `assetBytes` 不写 sidecar（导出即丢图）

- [X] T028 [P] [R1.7] 写 Red Test：构造合法 note-document JSON（含 image 块）+ assets sidecar，走导入流程，断言 note+blocks 落库、资产字节入 AssetStore（当前 `App/Sources/Features/NoteWindow/NoteExportImport.swift` 无导入入口，编译即失败）
- [X] T029 [P] [R1.7] 写 Red Test：带 `assetBytes` 调用导出，断言 sidecar 文件（`NoteDocumentSerializer.assetSidecarFilename`）与文档并列写出（当前不写 → 失败）；损坏 JSON/缺 required key 断言 fail-closed 不产生半成品 note
- [X] T030 [R1.7] 修复：`NoteExportImport.swift` 新增导入流程（NSOpenPanel → `decodeDocument` → `validateForImport` → 仓库写入 → 资产导入）；导出侧写入 sidecar；删除悬空"Imports a note JSON via NSOpenPanel"注释（`NoteExportImport.swift:36-40`）
- [X] T031 [R1.7] 验证：T028/T029 绿；`encodeAssetSidecar`/`decodeAssetSidecar`/`assetSidecarFilename` 不再仅测试引用（grep 门控）；全量测试绿

**Phase 8 验收**：FR-031a 导入/导出闭环；sidecar 读写路径生产消费。

---

## Phase 9: Polish & Phase 1 验收门

**Purpose**: 收尾清理与全量验收

- [X] T032 [P] 清理：`specs/005-remediation-phase1/` 文档核销（spec.md/plan.md 与 tasks.md 一致，无模板占位残留）；确认本 Phase 零新增依赖（`Package.resolved` 不变）
- [X] T033 Phase 1 验收：全量测试绿（含本 Phase 新增 Red Test 转化；当前基线 Core 605 + App 553 仅作参考计数）；`emptyBlockRemovalPersists` 并行 3 轮 + 串行 1 轮零失败；T001/T002 门控脚本在 CI 绿；审计对照核销——S-1（DiagnoseLog）、S-2（占位图标）、S-3（捕获吞错）、S-4/S-5（banner/状态）、S-8（导入/sidecar）、A-2（HTTPS）、动态验证竞态，全部关闭或转 Phase 2 工单

**Phase 9 验收**：验收门全绿；未关闭项显式转入 `Documentation/remediation-roadmap-2026-08-15.md` Phase 2 任务表。

---

## 依赖与并行执行示例

**依赖链**：T005→T007→T008；T012→T014→T015；T016→T017→T018；T024→T026→T027；T028→T030→T031；T001/T002→T003；T003/T004 独立

**并行批次（示例）**：
- 批次 A（Setup 首日）：T001 ∥ T002 ∥ T004
- 批次 B（Red Test 先行，互不依赖文件）：T005 ∥ T009 ∥ T012 ∥ T013 ∥ T016 ∥ T019 ∥ T020 ∥ T024 ∥ T025 ∥ T028 ∥ T029
- 批次 C（实现，依赖各自 Red Test）：T006→T007 ∥ T010 ∥ T014 ∥ T017 ∥ T021→T022 ∥ T026 ∥ T030
- 批次 D（验证与验收）：T008 ∥ T011 ∥ T015 ∥ T018 ∥ T023 ∥ T027 ∥ T031 → T032 → T033

## 实施策略（MVP 优先）

- 里程碑 M1 = Phase 2 + Phase 3 + Phase 6（T005–T011、T019–T023）：数据一致性 + 日志 + 传输安全，Sprint 1 前半交付
- 里程碑 M2 = Phase 4 + Phase 5 + Phase 7 + Phase 8（T012–T018、T024–T031）：捕获/渲染/状态/导入，Sprint 1 后半交付
- 每个 story 独立可验证：Red Test 单独提交演示失败（commit 信息标注 `test(core|app): :white_check_mark: …`），实现单独提交（`fix(...)`），遵循仓库 conventional commits 规范
