# Plan: Remediation Phase 1 — 紧急止血与数据安全

**Input**: `Documentation/remediation-roadmap-2026-08-15.md` §2 + `specs/005-remediation-phase1/spec.md`

## 技术栈与结构（不变）

- 模块化单体：App target（`App/Sources`）+ `Packages/StickyCore`（7 模块：Domain/EditorCore/Persistence/AssetStore/SecurityCore/SyncCore/SystemBridge）
- Swift 6 语言模式、严格并发、`-warnings-as-errors`；macOS 26 最低部署目标；Xcode-beta（Swift 6.4 / macOS 27 SDK）本地验证
- 本 Phase 不新增任何第三方依赖

## 模块边界（每个任务严格归属）

| 任务 | 归属模块 | 边界约束 |
|---|---|---|
| R1.1 | App（`NoteWindowHostModel`）+ EditorCore（`AutoSaveDraftManager`） | 竞态修复的 token 校验逻辑放 EditorCore（可测），DB diff 语义在 App sink；App 不得新增 GRDB 直调 |
| R1.2 | App（`RichTextView`/`RichTextBlockView`/`EditorSelectionBridge`/`NoteWindowHostModel`） | 日志出口统一收敛到 `StickyLogger`（Domain 提供）；不引入新日志框架 |
| R1.3 | App（`CaptureFlow`/`NoteWindowHostModel`）+ AssetStore（验收） | 失败传播在 App 层完成；AssetStore 的 fail-closed 已有测试保护，不改 Core 行为 |
| R1.4 | App（`ScreenshotBlockView`/`RichTextBlockView`）+ AssetStore（`readData` 复用） | 渲染源状态机放 App 层可测类型；AssetStore 只暴露只读数据通路 |
| R1.5 | SyncCore（`WebDAVProvider`/`S3Provider`） | scheme 校验在适配器构造/verify 边界；错误映射复用 `StickyError.credentials(.invalidEndpoint)`（Domain） |
| R1.6 | App（`LibraryModel`/`SyncSettingsView`/`SyncStatusPresentation`） | 状态映射单一来源 `SyncStatusResolver` 不动；只修生产调用点的输入接线与动作分发 |
| R1.7 | App（`NoteExportImport`）+ Domain（`NoteDocumentSerializer` 复用，不修改 Core 能力） | 导入编排在 App 层（NSOpenPanel + 校验 + 仓库写入）；Domain 序列化器仅在其确有缺陷时微调并红测先行 |

## 测试策略（TDD 门控，Constitution XII）

- 每个 story 先落 Red Test（确定性失败优先：注入延迟/桩 provider/桩状态），再实现，再 Green，再全量回归
- 验证命令（AGENTS.md 前缀）：
  - Core: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore`
  - App: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- 竞态类修复（R1.1）DoD 强制：全量并行 3 轮 + 串行 1 轮零失败

## 依赖顺序

R1.3 → R1.4（捕获失败先正确传播，缩略图渲染才有真实输入）；R1.1 →（无下游 Phase 1 任务，但阻断 Phase 2 R2.2）；其余 R1.2/R1.5/R1.6/R1.7 相互独立可并行。CI 门控 G1/G3（Roadmap §5）在 Phase 1 首日挂接。

## 里程碑

- M1（Sprint 1 前半）：R1.1 + R1.2 + R1.5（数据一致性 + 日志 + 传输安全）
- M2（Sprint 1 后半）：R1.3 + R1.4 + R1.6 + R1.7 + Phase 1 验收门全绿
