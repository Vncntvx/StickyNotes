# Contracts: macOS 27 原生质感重设计（Liquid Glass）

**Feature**: `003-macos27-liquid-glass-redesign` | **Date**: 2026-08-09

## 契约状态：全部不变

本特性为纯呈现层重设计。`specs/001-sticky-notes-app/contracts/` 下全部契约在本特性中 **MUST NOT 变更**（FR-090）：

| 契约 | 状态 |
|---|---|
| `note-document.schema.json`（笔记导出/同步信封） | 不变 |
| `block-payloads.schema.json` | 不变 |
| `rich-text.schema.json` | 不变 |
| `tombstone.schema.json` | 不变 |
| `encrypted-envelope.schema.json` / `encrypted-manifest.schema.json` | 不变 |
| `vault-bootstrap.schema.json` | 不变 |
| `asset-metadata.schema.json` | 不变 |
| `sync-profile-export.schema.json`（v2） | 不变 |
| `diagnostic-bundle.schema.json` | 不变 |
| `provider-protocol.md` / `provider-errors.md` | 不变 |
| `deep-links.md` | 不变（`stickynotes://search` 行为补全不影响 URL 契约） |

## 本特性新增"契约"

无外部接口契约新增。同步状态呈现映射（内部错误代码 → 七类可读状态 → 恢复动作）是**纯呈现层内部映射**，不属于外部契约；其确定性由 `AppTests` 穷举测试保证（spec FR-012）。

## 实现约束

- 任何实现不得修改 `StickyCore` 的公开序列化/加密/同步格式；新增 App 层类型不得改变 `contracts/` 所指 schema。
- 迁移测试夹具（001 `Fixtures/`）继续有效；升级路径为"旧数据 + 新 UI"夹具测试（FR-090）。
