# Feature Specification: Remediation Phase 3 — 架构净化与现代化

**Feature Branch**: `006-remediation-phase3`

**Created**: 2026-08-15

**Status**: Draft

**Input**: 《StickyNotes 技术债清偿与架构重构 Roadmap》（2026-08-15，`Documentation/remediation-roadmap-2026-08-15.md`）Phase 3（Sprint 3+）任务 R3.1–R3.10；依据审计发现 D-2/D-3、D-7…D-17、M-1…M-9、A-1/A-3/A-4/A-5/A-7/A-9/A-10/A-11、T-1…T-4。

## 设计依据

- Roadmap: `Documentation/remediation-roadmap-2026-08-15.md`（§4 Phase 3 任务表，含 Red Test 设计与 DoD；§5 门控 G2）
- 门控: Constitution Principle XII（TDD：Red Test 先行必须失败）；全程禁止引入任何新增依赖（宪法 XIII）；macOS 26 最低部署目标不变
- 前置: Phase 1（R1.1–R1.7）与 Phase 2（R2.1–R2.6）已全部落地并全量绿（578/100 App + Core 全绿）

## 用户场景与验收（技术债修复，非新功能）

每个修复项视为一个独立可验证的"story"。每个 story 的完成标准 = 该缺陷的 Red Test 转绿 + 对应 DoD。本 Phase 无用户可见新功能（R3.9 为纯研究，R3.8 为纯等价替换）。

### Story R3.1 - AppEnvironment 瘦身（Priority: P1）

**Why this priority**: `DomainServices`/`EditorServices`/`SecurityServices`/`SyncServices`/`SystemBridgeServices` 五个服务分组是空壳（仅 `init()` 与 `placeholder`），`tombstoneRepository`/`cardProjection` 属性无消费者，`localPreferences` 槽位与真实存储分离——组合根宣称的"服务"不存在，误导后续维护。

### Story R3.2 - 死代码批次清理（Priority: P1）

**Why this priority**: 审计 D-7…D-17 的 30+ 死符号（`AutoLinkDetector` 旧扫描器、`SecurityCoreModule`/`SyncCoreModule` 空壳、`CrossBlockSelection:126` 字面死循环、恒真 precondition、无消费者格式化/颜色 API 等）稀释代码库可信度，且阻碍 G2 死符号门控挂接。

### Story R3.3 - canonicalJSON 收敛（Priority: P1）

**Why this priority**: `EncryptedEnvelope`/`VaultBootstrap`/`SyncedAssetBlob`/`DiagnosticBundle.encode` 四处手写 `sortedKeys` 编码器与 `Domain.CanonicalJSONEncoder` 并存，日期策略不一致——同一 vault 字节在不同路径编码不同（M-9）。

### Story R3.4 - Domain 模块边界修正（Priority: P1）

**Why this priority**: Domain 声明 "Foundation-only" 但 `Logging.swift` `import os`、`RemoteManifest.swift` `import CryptoKit`（A-1）——模块边界声明与实现不符，破坏依赖拓扑可信度。

### Story R3.5 - TodoHierarchy 迁入 Domain（Priority: P1）

**Why this priority**: `maxDepth=6`/环检测规则双实现（测试 target 一份、Persistence 私有一份），测试验证的是副本（A-5）——规则漂移时测试与生产行为分裂。

### Story R3.6 - 规则单源化（Priority: P1）

**Why this priority**: `clampedOpacity`（App 复制 Domain）、摘要/首行派生双实现（`NoteSummary` vs `firstMeaningfulLine`，含硬编码 "Screenshot"/"Image" 本地化缺陷）、`RemoteLayout.isOpaque` 复制、status-item 窗口启发式双实现、`MenuCommandCatalog` 未被菜单构建消费（A-3/A-4/A-7/A-10/A-11）——每条规则两份实现，修一处漏一处。

### Story R3.7 - CardProjection 有界化（Priority: P1）

**Why this priority**: "bounded loads" 名不副实——previews 查询无 lifecycle/limit 过滤，全库 richText 块全量解码（A-9），500 行上限仅对显式查询生效。

### Story R3.8 - API 现代化批次（Priority: P2）

**Why this priority**: `Task.sleep(nanoseconds:)` 7 处、`DateFormatter` 每调用新建 3 处（M-1/M-2/M-3/M-7）——过期 API 面，非行为缺陷；`SyncHTTPDateParser` 收敛并入 R3.3。

### Story R3.9 - macOS 27 Research Spike（Priority: P2，纯研究）

**Why this priority**: `EditorAppBridge` 存在"TextEditor 无 selection API"错误论断（M-1）；`AttributedTextSelection`（macOS 26+）是否可替换自建选区桥、`CGRequestScreenCaptureAccess` 废弃状态、Liquid Glass 使用面均未评估——不写代码，产出 ADR 喂给 R3.8。

### Story R3.10 - 测试真实化批次（Priority: P1）

**Why this priority**: 21 处裸 `#expect(true)`（含 FR-142 离线门禁形同虚设）、常量策略自证测试（`SystemBehaviorPolicy`/`GlassUsagePolicy`/`NoteControlsPresentation`/`FontPreferenceUI`）、`EditorContinuityIntegrationTests` flaky sleep、`LibrarySearchFieldTests` locale 缺陷（zh 下断言英文文案）+ 后台线程构造 `NSSearchField`（T-1…T-4）——测试自身成为技术债。

## 非目标（明确排除）

- 不实现任何新用户功能；不改变既有 FR/SC 行为语义（R3.8 为等价替换，R3.3 为字节等价收敛）
- 不引入 SwiftLint/periphery 等新第三方工具（G2 以自建轻量脚本落地，宪法 XIII）
- 不做 AttributedTextSelection 等 macOS 27 API 的迁移实现（R3.9 仅评估并产出 ADR；若采用，迁移另立任务）
- 不修订 001 主文档行为定义（spec.md/plan.md 的 001 文档不动）
