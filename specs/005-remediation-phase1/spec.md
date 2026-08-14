# Feature Specification: Remediation Phase 1 — 紧急止血与数据安全

**Feature Branch**: `005-remediation-phase1`

**Created**: 2026-08-15

**Status**: Draft

**Input**: 《StickyNotes 技术债清偿与架构重构 Roadmap》（2026-08-15，`Documentation/remediation-roadmap-2026-08-15.md`）Phase 1（Sprint 1）任务 R1.1–R1.7；依据《StickyNotes 架构与代码质量深度审计报告》（2026-08-14，静态审计 + 动态验证）。

## 设计依据

- Roadmap: `Documentation/remediation-roadmap-2026-08-15.md`（§2 Phase 1 任务表，含 Red Test 设计与 DoD）
- 审计报告: 上一轮审计输出（S-1…S-8、A-2 发现 + 动态验证新增保存竞态）
- 门控: Constitution Principle XII（TDD：Red Test 先行必须失败）；全程禁止引入任何新增依赖；macOS 26 最低部署目标不变

## 用户场景与验收（技术债修复，非新功能）

每个修复项视为一个独立可验证的"story"，按数据风险排序。每个 story 的完成标准 = 该缺陷的 Red Test 转绿 + 对应 DoD。

### Story R1.1 - 保存链路竞态修复（Priority: P0）

**Why this priority**: 已删块可能被旧保存快照复活（数据一致性雷，`emptyBlockRemovalPersists` 间歇失败实证），威胁用户笔记数据完整性。

### Story R1.2 - DiagnoseLog 发布版调试日志清除（Priority: P0）

**Why this priority**: 发布版每次拖动/聚焦同步写临时文件明文日志，违反 FR-165/191 消毒约束，且为主线程磁盘 I/O。

### Story R1.3 - 捕获失败吞错修复（Priority: P0）

**Why this priority**: 捕获失败被吞成空 `Data` 并被当成功截图入库插块，击穿 Core fail-closed 契约（T303），污染笔记内容。

### Story R1.4 - 截图/图片块真实缩略图渲染（Priority: P1）

**Why this priority**: FR-094a 声明"渲染 256px 缩略图"实际只渲染占位图标，功能假象。

### Story R1.5 - HTTPS-only 传输强制（Priority: P0）

**Why this priority**: 宪法 VIII 声明 HTTPS-only 但 WebDAV/S3 适配器均无 scheme 校验，凭据可能明文传输。

### Story R1.6 - Banner/同步状态真实接线（Priority: P1）

**Why this priority**: `vaultLocked` 硬编码 `false` 使 needsUnlock 类别不可达；banner 4/5 按钮空操作——可见控件无功能。

### Story R1.7 - 便签 JSON 导入 + 资产 sidecar 真实化（Priority: P1）

**Why this priority**: 导入无 UI/流程（悬空注释），导出丢弃 `assetBytes` 不写 sidecar——导出即丢图（FR-031a 数据丢失）。

## 非目标（明确排除）

- 不实现任何新功能（除 R1.7 导入为既有契约 FR-031a 的落地）
- 不改动 spec.md/plan.md 的 001 主文档行为定义（仅按审计缺陷修正实现）
- 不做 macOS 27 新 API 迁移（属 Phase 3 R3.9 Spike 范围）
