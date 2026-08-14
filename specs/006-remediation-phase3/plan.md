# Plan: Remediation Phase 3 — 架构净化与现代化

**Input**: `Documentation/remediation-roadmap-2026-08-15.md` §4 + `specs/006-remediation-phase3/spec.md`

## 技术栈与结构（不变）

- 模块化单体：App target（`App/Sources`）+ `Packages/StickyCore`（7 模块：Domain/EditorCore/Persistence/AssetStore/SecurityCore/SyncCore/SystemBridge）
- Swift 6 语言模式、严格并发、`-warnings-as-errors`；macOS 26 最低部署目标；Xcode-beta（Swift 6.4 / macOS 27 SDK）本地验证
- 本 Phase 不新增任何第三方依赖（宪法 XIII）；G2 死符号门控用自建脚本（`scripts/check-dead-symbols.sh`），不引入 periphery

## 模块边界（每个任务严格归属）

| 任务 | 归属模块 | 边界约束 |
|---|---|---|
| R3.1 | App（`AppEnvironment.swift`） | 只删空分组/死属性，不触碰 Core 服务类型；`PersistenceServices`/`AssetServices` 真实槽位保留 |
| R3.2 | 按符号归属（EditorCore/Domain/SecurityCore/SyncCore/App） | 删除前 grep 门控确认零消费者；`AccessibilityAdaptations` 先核运行时消费者再删 |
| R3.3 | SecurityCore/SyncCore（消费方）+ Domain（提供方） | 编码统一走 `Domain.CanonicalJSONEncoder`/`CanonicalJSONDecoder`；字节级 golden 防回归；加密向量测试必须保持绿 |
| R3.4 | Domain + SecurityCore | `import os`/`import CryptoKit` 移出 Domain；`bootstrapObjectName` 改调 `SecurityCore` 哈希；或 ADR 修订边界声明（二选一，推荐前者） |
| R3.5 | Domain（规则）+ Persistence（消费）+ Tests（迁移） | 生产规则单源；测试 target 副本删除；深度/环行为断言与现行为一致 |
| R3.6 | App + Domain（按符号归属） | 每项规则全库仅一份实现；本地化缺陷测试注入 zh locale；菜单目录驱动菜单构建 |
| R3.7 | Persistence（`CardProjection`） | 解码计数有界断言；不回归 SC-005 10k 基线 |
| R3.8 | App、SyncCore（按符号归属） | 纯机械等价替换；`Task.sleep(for:)`/`Date.FormatStyle`；grep 门控零残留 |
| R3.9 | App + EditorCore（评估对象） | 不写代码；ADR 归档 `Documentation/adr/`；结论同步 toolchain.md 与过时注释 |
| R3.10 | AppTests | 裸 `#expect(true)` 零残留（CI 门控）；双 locale 断言；确定性等待替代 flaky sleep |

## 测试策略（TDD 门控，Constitution XII）

- 结构断言类 Red（R3.1/R3.4/R3.6）：以"符号存在 = 失败态"编译期/门控断言先行
- 删除即验证（R3.2）：每批删除后全量编译 + 测试绿；疑似误删风险符号先 grep 确认零引用
- 字节等价（R3.3）：golden 测试固定 fixture 字节
- 行为等价（R3.8）：超时/取消语义测试 + 日期格式化双 locale golden
- 验证命令（AGENTS.md 前缀）：
  - Core: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path Packages/StickyCore`
  - App: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project StickyNotes.xcodeproj -scheme StickyNotes -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`

## 依赖顺序

R3.3/R3.4 → R3.5（canonicalJSON 收敛与 Domain 边界修订先行，TodoHierarchy 迁移不触碰编码层）；R3.9 → R3.8（Spike 结论决定选区相关项采用/搁置；RTF/DateFormatter/Task.sleep 项不依赖 Spike 可并行）；R3.2 → G2 门控挂接（先清存量再禁增量）。R3.1/R3.6/R3.7/R3.10 相互独立，可并行批次。

## 里程碑

- M1：R3.1 + R3.2 + G2 门控（结构净化 + 死符号清零）
- M2：R3.3 + R3.4 + R3.5 + R3.7（编码/边界/规则生产化）
- M3：R3.6 + R3.9 + R3.8（规则单源 + Spike 决策 + API 现代化）
- M4：R3.10 + Phase 3 验收门全绿（测试真实化 + 全量回归 + CI 门控核对）

## 风险与缓解

| 风险 | 缓解 |
|---|---|
| R3.2 误删仍有隐藏消费者的符号 | 每批删除前 grep 全仓（含测试/资源）零引用门控；删除后立即全量编译 + 测试 |
| R3.3 收敛改变既有加密向量字节 | golden 测试固定既有 fixture；`EncryptionVectorTests` 为硬性验收 |
| R3.5 生产规则行为与测试副本漂移 | 深度 7 reparent 拒绝回归测试显式断言"生产拒绝、与测试预期一致" |
| R3.8 等价替换引入时序变化 | `Task.sleep(for:)` 替换点保留取消/超时语义；行为等价测试 |
| R3.9 Spike 结论为"不迁移" | R3.8 范围收缩至不依赖 Spike 的项（RTF/DateFormatter/Task.sleep），ADR 记录决策 |
