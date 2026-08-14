# Tasks: Remediation Phase 3 — 架构净化与现代化

**Input**: `specs/006-remediation-phase3/spec.md` + `plan.md` + `Documentation/remediation-roadmap-2026-08-15.md` §4/§5

**Prerequisites**: spec.md ✅, plan.md ✅, roadmap ✅（Phase 1/2 全量绿基线 578/100 App + Core 全绿）

**Tests**: TDD 强制（Constitution XII）——结构断言/删除即验证/字节等价 Red 先行；每批实现独立提交（conventional commits）。

**Organization**: 按修复项（R3.1–R3.10）分组；Setup 阶段挂接 G2 死符号门控（Roadmap §5）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: R3.1–R3.10（映射 spec.md 的 10 个修复项）
- 所有任务含精确文件路径

## 验证命令（AGENTS.md 前缀）

- Core: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore`
- App: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

---

## Phase 1: Setup — G2 死符号门控（Roadmap §5，R3.2 后挂接）

**Purpose**: 存量死符号清零后建立"禁增量"门控；为 R3.2 的"删除即验证"提供可执行依据

- [ ] T001 [P] [Setup] 新增 `scripts/check-dead-symbols.sh`：提取 `App/Sources` 与 `Packages/StickyCore/Sources` 顶层 `public`/`internal` 类型与函数签名（AST 轻量正则），全仓（含 AppTests/Packages 测试）引用计数为 0 即非零退出；初始 allowlist 为空（R3.2 完成后运行零告警）
- [ ] T002 [P] [Setup] 在 `.github/workflows/` 现有 CI workflow 挂接 T001（与 xcodegen 漂移检查、G1/G3 门控并列，失败即红）
- [ ] T003 [Setup] 本地预检：对当前代码库运行 T001，产出存量死符号清单（应含 R3.2 删除清单符号），作为 R3.2 对账基线

**Phase 1 验收**：T001 脚本可用；存量清单与 R3.2 删除项逐条对应。

---

## Phase 2: R3.1 — AppEnvironment 瘦身（P1）

**Purpose**: 删除 5 个空服务分组（`DomainServices`/`EditorServices`/`SecurityServices`/`SyncServices`/`SystemBridgeServices`）+ `tombstoneRepository`/`cardProjection` 死属性 + 未用 `localPreferences` 槽位（D-2/D-3）

- [ ] T004 [P] [R3.1] 写 Red 结构断言测试：`AppTests/AppEnvironmentShapeTests.swift`——枚举 `AppEnvironment` 存储属性，断言 `domain`/`editor`/`security`/`sync`/`systemBridge` 五个槽位在 App+AppTests 中至少一次解引用（当前 0 次 → 失败）；`tombstoneRepository`/`cardProjection` 零引用断言（当前成立，作为删除后回归锚点）
- [ ] T005 [R3.1] 修复：`App/Sources/App/AppEnvironment.swift` 删除 `DomainServices`/`EditorServices`/`SecurityServices`/`SyncServices`/`SystemBridgeServices` 五个空壳类型与对应槽位；删除 `tombstoneRepository`/`cardProjection` 死属性；`localPreferences` 槽位删除或改为 `LocalPreferences.defaults` 直取（决策：App 层 `LocalPreferences` 保留为设备本地首选项封装，`AppEnvironment` 不再持有未用槽位）；`placeholder`/`bootstrap`/全部调用点（`App/Sources/App/StickyNotesApp.swift`、`AppTests`）同步收缩
- [ ] T006 [R3.1] 验证：T004 绿；全量编译（Core+App）+ 全量测试绿；空分组类型名全库零匹配（grep 门控）

**Phase 2 验收**：`AppEnvironment` 仅含真实消费槽位（persistence/assets/syncCoordinator/typography）；空分组类型零残留。

---

## Phase 3: R3.2 — 死代码批次清理（P1）

**Purpose**: 按符号归属删除 D-7…D-17 死符号；删除前 grep 门控确认零消费者

- [ ] T007 [P] [R3.2] 写 grep 门控测试：`AppTests/DeadSymbolAuditTests.swift`（或 Core 侧对应）——断言以下符号全库零引用：`AutoLinkDetector` 旧扫描器 5 函数、`SecurityCoreModule`/`SyncCoreModule` 空壳类型、`AccessibilityAdaptations` 枚举、`DisplayFormatters.dateTime`、`AppMetrics` 3 常量、`LocalPreferences` 3 方法（`saveFirstLaunchState`/`dismissOnboardingHint`/`resetFirstLaunchState` 等按实际零引用者）
- [ ] T008 [R3.2] 删除批次 A（EditorCore）：`Packages/StickyCore/Sources/EditorCore/AutoLinkDetector.swift` 旧扫描器 5 函数（保留被 `RichTextBlockView` 消费的符号，先核对调用点）；`CrossBlockSelection:126` 字面死循环（`for _ in 0..<0` 或等价恒空循环）删除
- [ ] T009 [R3.2] 删除批次 B（Domain）：`ManualSortKeys.normalize` 恒真 precondition（`Packages/StickyCore/Sources/Domain/Models/VersionLineage.swift:143`）——删除或改为不成立的 precondition 语义
- [ ] T010 [R3.2] 删除批次 C（SecurityCore/SyncCore）：`SecurityCoreModule`/`SyncCoreModule` 空壳（`Packages/StickyCore/Sources/SecurityCore/SecurityCore.swift`、`SyncCore/SyncCore.swift`）
- [ ] T011 [R3.2] 删除批次 D（App）：`ReadableTheme.background(for:)`（核对 `App/Sources/Features/NoteWindow/ReadableTheme.swift` 消费方）、`NotePalette.color(for:)` 或保留被消费的 overload（核对 `NotePalette.swift:139`）、`AccessibilityAdaptations.swift` 整文件（T132 产物，先核对运行时消费者）、`DisplayFormatters.dateTime`（`Formatters.swift:58`，`lastModified`/`absoluteDate`/`fileSize` 保留）、`LocalPreferences` 3 方法、未用 import ×5（编译 -warnings-as-errors 已暴露）、`#available(macOS 26)` 不可达 else（`BlockInsertionControl.swift:126`/`RichTextBlockView.swift:741`——部署目标 26.0，else 分支不可达）、`AppMetrics` 3 常量、`RegionSelectionOverlay.setupLayer` 未用参数（`App/Sources/Features/Capture/RegionSelectionOverlay.swift:84`）
- [ ] T012 [R3.2] 验证：T007 绿；每批删除后全量编译 + 测试绿；T001 死符号门控在清理后运行零告警；删除清单与审计 D-7…D-17 逐条对账

**Phase 3 验收**：R3.2 清单符号全库零引用；G2 门控绿。

---

## Phase 4: R3.3 — canonicalJSON 收敛（P1）

**Purpose**: 4 处手写 `sortedKeys` 编码器统一走 `Domain.CanonicalJSONEncoder`，日期策略收敛（M-9）

- [ ] T013 [P] [R3.3] 写 Red 等值测试：`Packages/StickyCore/Tests/SecurityCoreTests/CanonicalJSONConvergenceTests.swift` + `SyncCoreTests` 对应——对 `EncryptedEnvelope`/`VaultBootstrap`/`SyncedAssetBlob`/`DiagnosticBundle` 各构造含日期字段实例：手写编码器输出 → `CanonicalJSONDecoder` 解码 → 与原值等值断言（当前含日期字段的 `VaultBootstrap` 往返字节与 canonical 编码不同 → 失败）
- [ ] T014 [P] [R3.3] 写 Red 字节 golden：既有 fixture（`EncryptionVectorTests` 向量、`Fixtures/` 内 vault 样例）字节不变断言——手写编码器输出与 `CanonicalJSONEncoder` 输出逐字节比对（当前不一致 → 失败）
- [ ] T015 [R3.3] 修复：`Packages/StickyCore/Sources/SecurityCore/EncryptedEnvelope.swift`、`SyncCore/VaultBootstrap.swift`、`SyncCore/SyncedAssetBlob.swift`、`SecurityCore/DiagnosticBundle.swift` 的 `encode` 改调 `Domain.CanonicalJSONEncoder`；日期策略统一（iso8601 或 `CanonicalJSONEncoder` 既有策略）；`SyncHTTPDateParser` 收敛（并入本任务或 R3.8，决策记录）
- [ ] T016 [R3.3] 验证：T013/T014 绿；全库仅剩 `CanonicalJSONEncoder` 一处 `sortedKeys` 定义（grep 门控）；`EncryptionVectorTests` 保持绿；全量测试绿

**Phase 4 验收**：canonicalJSON 单一实现；加密向量字节不变。

---

## Phase 5: R3.4 — Domain 模块边界修正（P1）

**Purpose**: `import os`（`Logging.swift`）与 `import CryptoKit`（`RemoteManifest.swift`）移出 Domain（A-1）

- [ ] T017 [P] [R3.4] 写 Red 边界守卫测试：`Packages/StickyCore/Tests/DomainTests/ModuleBoundaryTests.swift`——枚举 `Domain/Sources` 各文件 import 集合，断言仅 Foundation 系框架（当前含 os/CryptoKit → 失败）
- [ ] T018 [R3.4] 修复：`Logging.swift` 的 `import os` 移除（`OSLog` 改用 Foundation 可用替代或经注入日志器，决策记录）；`RemoteManifest.swift` 的 `import CryptoKit`（SHA256）改调 `SecurityCore.SHA256DigestHash`（若 `bootstrapObjectName` 依赖）或移入 SecurityCore；`bootstrapObjectName` 归属同步修订
- [ ] T019 [R3.4] 验证：T017 绿；Domain 无 os/CryptoKit 符号（grep 门控）；全量测试绿（含既有 `SyncCompositionTests` 的 `bootstrapObjectName` 断言）

**Phase 5 验收**：Domain 边界声明与实现一致（或 ADR 修订声明，二选一）。

---

## Phase 6: R3.5 — TodoHierarchy 迁入 Domain（P1）

**Purpose**: `maxDepth=6`/环检测规则单源化到生产（A-5）

- [ ] T020 [R3.5] Red（编译级）：删除测试 target 的 `TodoHierarchy` 副本 → 测试编译失败（强制生产导出）
- [ ] T021 [R3.5] 修复：规则迁移至 `Packages/StickyCore/Sources/Domain/`（`TodoHierarchy` 生产类型，含 `maxDepth`/环检测）；`Persistence`（`SQLiteTodoRepository`）改调生产规则；`Tests/` 深度/环测试改用生产符号重写
- [ ] T022 [P] [R3.5] 写行为漂移回归：构造深度 7 的 reparent，断言拒绝（`TodoRepositoryTests`）；断言与现行为一致（既有深度 6 通过用例保持绿）
- [ ] T023 [R3.5] 验证：T020 编译红转绿、T022 绿；规则只在 Domain 一份（grep 门控）；`TodoRepositoryTests` 不再自证副本；全量测试绿

**Phase 6 验收**：TodoHierarchy 规则生产单源；深度/环行为无漂移。

---

## Phase 7: R3.6 — 规则单源化（P1）

**Purpose**: `clampedOpacity`/摘要派生/`RemoteLayout.isOpaque`/status-item 窗口启发式/菜单目录单源化（A-3/A-4/A-7/A-10/A-11）+ 本地化缺陷

- [ ] T024 [P] [R3.6] Red：zh locale 注入下断言卡片摘要为本地化文案（当前 `firstMeaningfulLine` 硬编码 "Screenshot"/"Image" 英文 → 失败）
- [ ] T025 [P] [R3.6] Red：删除 App 侧 `clampedOpacity` 复制实现 → 编译失败（强制改调 Domain API）
- [ ] T026 [R3.6] 修复：`clampedOpacity`（`App/Sources/Features/NoteWindow/` 或相关）改调 Domain 实现；摘要/首行派生统一走 `NoteSummary`（`Packages/StickyCore/Sources/Domain/`），删除 `firstMeaningfulLine` 硬编码分支并本地化 "Screenshot"/"Image" 文案（`App/Resources/Localizable.xcstrings` 补 key）；`RemoteLayout.isOpaque` 复制删除；status-item 窗口启发式（`MenuBarLibraryScene.statusItemIconFrame` 等）统一到单处；`MenuCommandCatalog` 改为菜单构建的真实数据源（`App/Sources/App/MenuCommands.swift` 消费目录）
- [ ] T027 [P] [R3.6] 验证：T024/T025 绿；每项规则全库仅一份实现（grep 门控）；`MenuChecklistTests` 升级为"目录驱动菜单构建"结构断言；双 locale 测试绿

**Phase 7 验收**：规则单源化 grep 门控全过；本地化文案 zh/en 双绿。

---

## Phase 8: R3.7 — CardProjection 有界化（P1）

**Purpose**: previews 查询无 lifecycle/limit 过滤，全库 richText 块全量解码（A-9）

- [ ] T028 [P] [R3.7] 写 Red 有界解码测试：`Packages/StickyCore/Tests/PersistenceTests/CardProjectionBoundedTests.swift`——构造 2,000 条 note（1,500 trashed、1,000 richText 块），注入计数解码器（记录 `CardProjection` 解码的块行数），`fetchCardProjections(lifecycle: .active, limit: 500)` 断言解码次数 ≤ 500+ε 且 trashed note 的块不被解码（当前全量解码 → 失败）
- [ ] T029 [R3.7] 修复：`Packages/StickyCore/Sources/Persistence/CardProjection.swift` previews 查询补 lifecycle/limit 过滤（SQL 层 WHERE + LIMIT），解码行数与返回行数一致；注释与实际语义对齐（"bounded loads"）
- [ ] T030 [R3.7] 验证：T028 绿；500 行上限语义与注释一致；既有 SC-005 10k 性能基线测试保持绿；全量测试绿

**Phase 8 验收**：previews 查询解码有界；trashed 块零解码。

---

## Phase 9: R3.9 — macOS 27 Research Spike（P2，纯研究）

**Purpose**: 产出 ADR 决策记录，喂给 R3.8（不写产品代码）

- [ ] T031 [R3.9] 调研 ①：`AttributedTextSelection`（macOS 26+，Apple 文档 l_6_5）替换自建选区桥（`EditorSelectionBridge`/`EditorRegistry`/scalar↔UTF-16 换算）的可行性、与 NSTextView 编辑器（`RichTextView`）的共存性；产出采用/搁置结论 + 依据（Apple 文档/WWDC 链接）
- [ ] T032 [R3.9] 调研 ②：核对 `EditorAppBridge` "TextEditor 无 selection API" 论断（当前错误），更新为真实 API 面描述
- [ ] T033 [R3.9] 调研 ③：`CGRequestScreenCaptureAccess` 在 macOS 27 SDK 的废弃状态复核（`App/Sources/Features/Capture/` 调用点）
- [ ] T034 [R3.9] 调研 ④：Liquid Glass（`.glassEffect`/`.buttonStyle(.glass)`）使用面复核（`BlockInsertionControl`/`RichTextBlockView`/`MenuBarLibraryScene` 等）
- [ ] T035 [R3.9] 归档：`Documentation/adr/` 新增 ADR（每项采用/搁置 + 依据）；同步更新 `Documentation/toolchain.md` 与过时注释（`StickyNotesApp.swift`/`EditorAppBridge` 等）

**Phase 9 验收**：ADR 归档；决策项进入 R3.8 或明确关闭。

---

## Phase 10: R3.8 — API 现代化批次（P2）

**Purpose**: `Task.sleep(nanoseconds:)` 7 处 → `Task.sleep(for:)`；`DateFormatter` 每调用新建 3 处 → `Date.FormatStyle`；`SyncHTTPDateParser` 收敛（并入 R3.3 或独立）

- [ ] T036 [P] [R3.8] 写行为等价测试：对 `Task.sleep(for:)` 替换点断言超时/取消语义不变（`AppTests` + `CoreTests` 按归属）；日期格式化 golden 测试：新旧路径输出字节一致（zh/en locale 双跑）
- [ ] T037 [R3.8] 修复：`App/Sources` + `Packages/StickyCore/Sources` 内 `Task.sleep(nanoseconds:)` 7 处统一 `Task.sleep(for:)`（`Duration`）；`DateFormatter` 每调用新建 3 处改 `Date.FormatStyle`（`DisplayFormatters`/`SyncSettingsView`/`SyncCore` 按归属）；`SyncHTTPDateParser` 收敛
- [ ] T038 [R3.8] 验证：T036 绿；全库无 `sleep(nanoseconds:)`/字符串 `dateFormat` 残留（grep 门控）；全量测试绿

**Phase 10 验收**：API 现代化零行为变化；grep 门控零残留。

---

## Phase 11: R3.10 — 测试真实化批次（P1）

**Purpose**: 21 处裸 `#expect(true)`（含 FR-142 离线门禁）、常量策略自证测试、flaky sleep、locale 缺陷、Main Thread Checker 违规

- [ ] T039 [R3.10] FR-142 门禁重写：`OfflineCompletenessTests`（或既有 FR-142 门禁测试）——静态依赖扫描断言（SyncCore 符号在编辑路径不可达）+ 行为断言（断网/无 provider 环境下 P1 流程全通），替换裸 `#expect(true)`
- [ ] T040 [P] [R3.10] 策略测试真实化：`SystemBehaviorPolicy`/`GlassUsagePolicy`/`NoteControlsPresentation`/`FontPreferenceUI` 自证测试改为真实 `NSWorkspace` 探测注入（或删除自证断言，决策记录）
- [ ] T041 [P] [R3.10] locale 缺陷修复：`LibrarySearchFieldTests` zh 下断言英文文案 → 本地化键断言（双 locale 均可通过）；`NSSearchField` 构造移回主线程（Main Thread Checker）
- [ ] T042 [P] [R3.10] flaky sleep 修复：`EditorContinuityIntegrationTests` 的 500ms 裸 sleep 改确定性等待（既有 `waitUntil` 模式）
- [ ] T043 [R3.10] 验证：T039–T042 绿；裸 `#expect(true)` 零残留（T001 门控 G1 绿）；无 50ms+ 裸 sleep（门控扫描）；全量测试绿（含 zh locale job）

**Phase 11 验收**：测试真实化；G1/G4 门控全绿。

---

## Phase 12: Polish & Phase 3 验收门

**Purpose**: 收尾清理与全量验收

- [ ] T044 [P] 清理：`specs/006-remediation-phase3/` 文档核销（spec.md/plan.md 与 tasks.md 一致，无模板占位残留）；确认本 Phase 零新增依赖（`Package.resolved` 不变）
- [ ] T045 Phase 3 验收：全量测试绿（Core + App 578+ 基线参考）；G1/G2/G3/G4 门控全绿（含 xcodegen 漂移检查）；`check-dead-symbols.sh` 零告警；规则单源化 grep 门控全过；Domain 边界审计测试绿；macOS 27 Spike ADR 归档；审计对照核销——D-2/D-3、D-7…D-17、M-1…M-9、A-1/A-3/A-4/A-5/A-7/A-9/A-10/A-11、T-1…T-4 全部关闭或显式转入后续任务

**Phase 12 验收**：验收门全绿；未关闭项显式记录。

---

## 依赖与并行执行示例

**依赖链**：T004→T005→T006；T013→T015→T016；T017→T018→T019；T020→T021→T023；T024→T026→T027；T028→T029→T030；T031–T035（R3.9）→ T036（R3.8 选区相关项）；T001/T002→T003；T007→T008…T012

**并行批次（示例）**：
- 批次 A（Setup）：T001 ∥ T002
- 批次 B（Red 先行，互不依赖文件）：T004 ∥ T007 ∥ T013 ∥ T014 ∥ T017 ∥ T024 ∥ T025 ∥ T028 ∥ T036
- 批次 C（实现，依赖各自 Red）：T005 ∥ T008–T011 ∥ T015 ∥ T018 ∥ T021–T022 ∥ T026 ∥ T029 ∥ T037
- 批次 D（Spike 与测试真实化，独立）：T031–T035 ∥ T039–T042
- 批次 E（验证与验收）：T006 ∥ T012 ∥ T016 ∥ T019 ∥ T023 ∥ T027 ∥ T030 ∥ T038 ∥ T043 → T044 → T045

## 实施策略（依赖顺序优先）

- 里程碑 M1 = R3.1 + R3.2 + G2 门控（T004–T012）
- 里程碑 M2 = R3.3 + R3.4 + R3.5 + R3.7（T013–T023、T028–T030）
- 里程碑 M3 = R3.6 + R3.9 + R3.8（T024–T027、T031–T038）
- 里程碑 M4 = R3.10 + 验收门（T039–T045）
- 每个 story 独立可验证：Red Test 单独提交演示失败（`test(core|app): :white_check_mark: …`），实现单独提交（`refactor`/`fix`），遵循仓库 conventional commits 规范；**xcodegen 再生成不单独提交**（并入当批实现提交）
