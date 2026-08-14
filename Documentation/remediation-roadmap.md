# 《StickyNotes 技术债清偿与架构重构 Roadmap》

> 依据：《StickyNotes 架构与代码质量深度审计报告》（2026-08-14，54,729 行 Swift 逐文件静态审计，全部高危发现经人工复核 + 联网核实）。
> 门控：Constitution Principle XII（TDD：测试先行必须失败，再实现）。**本文档只含架构规划、任务拆解、依赖关系与测试策略——不含任何实现代码。**
> 基线：`main@cd54bd0`；工作区 `StickyNotes-remediation-roadmap`（branch `feat/remediation-roadmap`）。

---

## 0. 基线期任务 (Baseline, Sprint 0)

> 2026-08-14 基线调查产出：全量 479 tests / 85 suites 中唯一失败
> `EditorContinuityIntegrationTests.selectionRectRefreshesAfterResizeReflow` 的根因已定位（判别实验：并行 ✘ 2.277s / 串行 ✔ 0.069s）。

| 任务 ID | 任务名称 | 归属模块 | 前置依赖 | 🧪 Red Test 设计 | 验收标准 (DoD) |
|---|---|---|---|---|---|
| ~~R0.1~~ ✅ | ~~去 flaky：测试初始发布改用权威路径 + 套件串行化~~（**已完成 2026-08-14**） | AppTests（测试，非生产） | 无 | 并行模式复跑套件确认复现（✘ "the selection never published through the bridge"）→ 修改后并行 + 全量双跑均绿 | ✅ 全量 479/479 绿（35.2s）；resize 真实 reflow 重发布断言保留 |
| ~~R0.2~~ ✅ | ~~去 flaky：wrappingTextBold… selection 轮询恢复~~（**已完成 2026-08-14**） | AppTests（测试，非生产） | 无 | 全量并行复现（✘ selectedRange/bold/undo 三断言连锁）→ 修改后全量绿 | ✅ 全量 479/479 绿；被测语义（格式化作用于已选范围 + 保持行距）不变 |

**根因摘要（证据链）**：
1. 发布链路首次发布必须 `hasFocus == true`（`RichTextView.swift:786`），authority 过滤在身份未建立时丢弃非聚焦发布（`EditorSelectionBridge.swift:118-121`）
2. Swift Testing 默认并行 → 同套件 7 个窗口测试 + 全量 85 套件争夺唯一 `NSApplication.keyWindow`；测试 100×20ms=2s 重试预算耗尽 → `guard published` 失败（`:443-444`）
3. 串行运行 0.069s 即成功 → 非环境性故障，纯竞争致因
4. resize 阶段依赖 `focusedTextView` 身份（建立后非聚焦发布放行，`:122-123`），故仅在初始阶段裸奔

**修复方向（待实施批准）**：A（推荐）初始发布改用 bridge 文档化权威路径 `publish(from: nil, …)` 建立身份，resize 仍走真实 `onWidthReflow → republishSelection` 断言；B（双保险）套件加 `@Suite(.serialized)`。

---

## 1. 依赖与风险拓扑图 (Dependency & Risk Graph)

### 依赖链

```mermaid
flowchart TD
    subgraph P1["Phase 1 · Sprint 1 — 紧急止血与数据安全"]
        direction TB
        R1_1[R1.1 AssetStore 启动恢复] --> R1_2[R1.2 cleanupOrphans 安全化]
        R1_3[R1.3 vault master key 生命周期]
        R1_4[R1.4 FTS update 原子化]
        R1_5[R1.5 Argon2 空盐/随机源守卫]
        R1_6[R1.6 捕获菜单真实化]
        R1_7[R1.7 fileAvailability 接线或移除]
        R1_8[R1.8 NoteAutoDiscard 迁入生产]
        R1_9[R1.9 exportDocument 真实守卫]
        R1_10[R1.10 库错误 UI 渲染]
    end

    subgraph P2["Phase 2 · Sprint 2 — 核心链路修复"]
        direction TB
        R2_1[R2.1 transport 注入 + 契约测试] --> R2_2[R2.2 S3 list 虚拟主机修复]
        R2_1 --> R2_3[R2.3 状态码语义修正 501/405/412]
        R2_1 --> R2_4[R2.4 真实服务测试真实化]
        R2_5[R2.5 SyncCore 死码清理]
    end

    subgraph P3["Phase 3 · Sprint 3+ — 架构净化与现代化"]
        direction TB
        R3_1[R3.1 窗口系统统一] 
        R3_2[R3.2 NotificationCenter 直调化]
        R3_3[R3.3 死代码批次清理]
        R3_4[R3.4 activate() 废弃 API 替换 ×9]
        R3_5[R3.5 造轮子收敛 NSDataDetector/FTS5Pattern/RTF]
        R3_6[R3.6 SHA256/HTTP-date/canonicalJSON 收敛]
        R3_7[R3.7 🔬 macOS 27 Research Spike]
        R3_8[R3.8 陈旧文档同步]
    end

    R1_1 -. 恢复未落地前禁启清理 .-> R1_2
    R1_6 -. 捕获真实验证依赖系统能力 .-> R2_1
    R1_4 -. FTS 契约回归作为 R2 同步对账前提 .-> R2_3
    R3_2 -. 菜单清单测试同步 .-> R3_3
    R3_7 -. 结论决定 R3 是否新增任务 .-> R3_8
```

### 依赖拓扑要点

| 边 | 语义 | 违例后果 |
|---|---|---|
| R1.1 → R1.2 | 恢复逻辑必须先于清理逻辑存在 | 若先启用 `cleanupOrphans`：空记录表会把磁盘全部资产当孤儿删除（**删库级事故**） |
| R2.1 → R2.2/2.3/2.4 | 契约测试基建必须先于一切状态码/URL 修复 | 无注入点则修复无法被测试证明，回到"测试自证"老路 |
| R1.6 / R1.4 → R2 | 捕获与 FTS 修复引入的真实行为变化是同步对账的前提 | 同步层在错误基线上做对账会污染远端 |

### 各 Phase 最高风险与缓解预案

| Phase | 最高风险 | 风险等级 | 缓解预案 (Mitigation) |
|---|---|---|---|
| P1 | **数据丢失**：R1.2 在恢复未落地时启用清理 → 全量资产删除 | 🔴 CRITICAL | R1.1 与 R1.2 同 Sprint 且顺序强制（任务表前置依赖锁定）；R1.2 验收含"空记录表 + 非空磁盘 ⇒ 拒绝清理"守卫测试；R1.2 合入前 R1.1 必须绿 |
| P1 | **密钥不可逆**：R1.3 删除 master key 后用户忘密码 → 数据永久不可解 | 🔴 CRITICAL | 删除仅限 `lockVault`/`disableRememberUnlock` 显式路径；先补"密钥可读回"测试再删；keychain 条目删除前做存在性断言 |
| P1 | **UI 状态机回归**：R1.6 接线捕获引入权限弹窗/授权流 | 🟠 HIGH | 权限拒绝路径降级为 toast + 结构化日志（FR-165 净化），绝不在菜单动作中 crash；SystemBridge 契约测试先行 |
| P2 | **远端数据不一致**：R2.3 修复 501"假成功"后，历史"已同步"对象与真实远端不符 | 🟠 HIGH | 修复后执行一次完整 reconcile（引擎幂等设计天然支持）；R2.3 验收含"条件创建失败 ⇒ 引擎不 adoption"断言 |
| P2 | **基建成本失控**：transport 注入改造 provider 内部结构 | 🟡 MED | 注入面最小化（仅 URLSession 层）；禁止重写 URLSession 封装；LocalProvider 保留为纯本地对照 |
| P3 | **窗口/菜单行为回归**：R3.1/R3.2 双轨统一期间 Settings/About/Insert 路径失效 | 🟠 HIGH | 每步保持 scene-first + 注册表身份查找；`NoteWindowLifecycleTests` 与菜单清单测试作为回归锚；标题查找逐处替换而非批量 |
| P3 | **范围蔓延**：macOS 27 Spike 结论引发新功能立项 | 🟡 MED | Spike 只产出评估报告 + ADR 建议，立项与否由用户决策；不在本 Roadmap 内自动展开 |

---

## 2. Phase 1: 紧急止血与数据安全 (Sprint 1)

> 目标：两周内消灭三颗数据雷（AssetStore 不可恢复、master key 永久落盘、FTS 搜索列清空）与全部"功能假象"。
> Sprint 原则：**每项先写 Red Test（构造当前实现必然失败的用例），再实现；无法构造 Red Test 的任务重新评估。**

| 任务 ID | 任务名称 (Epic/Story) | 归属模块 | 前置依赖 | 🧪 Red Test 设计 (如何构造失败用例) | 验收标准 (DoD) |
|---|---|---|---|---|---|
| ~~R1.1~~ ✅ | AssetStore 启动恢复：`recordsByID` 从磁盘重建（`restoreFromDisk` + App bootstrap 接线）| AssetStore | 无 | ① store A 写入一个资产 → 销毁实例 → 同目录新建 store B → 断言 B `readData` 返回原字节。当前实现 B 的记录表为空、必然抛 `.notFound` → **红** | 重启后 `readData`/`url`/`delete` 对历史资产全部可用；恢复源为 `originals/` 目录扫描（文件名→contentKey 逆映射或磁盘直扫）；App bootstrap 无需改动即可访问历史资产 |
| ~~R1.2~~ ✅ | cleanupOrphans 安全化（空记录表拒绝清理）| AssetStore | **R1.1** | ② 构造"记录表为空 + 磁盘存在文件"态 → 断言 `cleanupOrphans` 不删除任何文件。当前实现"无记录 = 孤儿"全删 → **红** | 清理前置条件 = 恢复已完成且记录表非空；删除前双重确认（记录表命中 或 内容哈希匹配）；R1.1 未绿时本任务不得合入 |
| ~~R1.3~~ ✅ | vault master key 生命周期：死密钥落盘移除，remember-unlock 为唯一持久路径 | SecurityCore | 无 | ③ `createVault(rememberUnlock:false)` → `lockVault` → 断言 keychain 中 `vaultKeySecretKey` 条目不存在。当前实现无条件落盘且永不删除 → **红**；④ 同场景断言 `rememberedUnlockKeychainRef` 删除 | 密钥仅在 remember-unlock 生命周期内存续；锁定/禁用后密钥不可读；全仓出现第一条"读回"该密钥的测试路径（此前零读取）；keychain 清理顺序有断言 |
| ~~R1.4~~ ✅ | FTS update 原子化：仅刷新 title 列（`updateSearchTitle`）| Persistence | 无 | ⑤ insert 含正文 note → 调 `update`（仅改标题）→ FTS 查询正文关键词 → 断言仍命中。当前 upsert 全列替换为 `""` → 命中 0 → **红** | `update()` 只触碰 title 列（`ON CONFLICT DO UPDATE` 限定列），或仓储内部强制 `update`+`reindex` 成对；新增"update 后正文可搜"回归测试入库 |
| ~~R1.5~~ ✅ | Argon2 空盐与随机源守卫（`requireProductionMinimum` 拒空盐；`generateSalt` throws）| SecurityCore | 无 | ⑥ 断言 `Argon2Parameters.recommended.salt` 非空。当前公开常量为空盐 → **红**；⑦ 注入随机源失败场景 → 断言 KDF 拒绝生成而非静默全零盐 | `recommended` 不再可被直接消费（内部化或 failable）；`requireProductionMinimum` 校验盐非空 + `SecRandomCopyBytes` 返回码；`changePassword` 与 `createVault` 守卫一致化 |
| R1.6 | 捕获菜单真实化：接线 SystemBridge 捕获流 **或** 移除假菜单项（二选一，禁留假象） | App + SystemBridge | 无（若选接线：依赖权限流契约） | ⑧ 菜单动作注入 capture service 替身 → 断言"建笔记 + 调用捕获"两动作都发生。当前 `createNoteAndCapture` 只建笔记不捕获 → **红**（替身从未被调用） | 选"接线"：Region/Window 捕获真实产出截图附件入笔记、权限拒绝降级不崩溃；选"移除"：两个菜单项移除、`MenuChecklistTests` 与 HelpView 同步更新；两者都消灭"菜单说捕获、行为建空白笔记" |
| ~~R1.7~~ ✅ | fileAvailability 接线真实求值器（`RichTextBlockView` provider 通道 + Coordinator 接线；构造提取解类型检查超时）| App | 无 | ⑨ 注入 `availabilityProvider` 替身 → 断言卡片渲染替身返回的状态。当前 `FileReferenceCardView` 默认闭包恒 `onAnotherDevice` 且生产无人传参 → **红** | `NoteWindowHostModel.fileAvailability` 获得生产调用点，或指示器 UI 整体移除；UI 不再展示恒假信息 |
| ~~R1.8~~ ✅ | NoteAutoDiscard 迁入生产（`NoteLifecycle.swift`）；App 平行实现 `isMeaningful` 删除改委托（补 FR-013）| Domain | 无 | ⑩ 将测试 target 中的规则迁移为 `NoteLifecycle` 生产实现 → 原 `NoteAutoDiscard` 用例改为直接测生产类型（当前生产无此规则，测试引用测试 target 定义 → 迁移即红→绿） | 生产存在规则实现且被调用点使用（或明确标记为 spec 降级）；测试不再引用测试 target 内的"伪生产"定义 |
| ~~R1.9~~ ✅ | exportDocument 删 throws 与假守卫（payload 物理上无路径数据，契约一致化）| Domain | 无 | ⑪ 携带 fileReference 块的文档 → 断言导出行为符合文档注释声明（拦截或剥离）。当前守卫循环为 no-op、注释承诺的 `fileReferencePayloadCorrupt` 永不抛 → **红**（行为与契约不符） | 注释/签名/行为三者一致：要么实现真实校验并补负向用例，要么删除 `throws` 与守卫并修正文档 |
| R1.10 | 库错误面 UI 化：statusMessage 可被读取渲染 | App | 无 | ⑫ 触发 `LibraryModel` 失败路径 → 断言错误状态可被视图读取（注入视图观察替身）。当前状态写入但零读取、空 `catch` 吞错 → **红** | FR-011a 错误 toast/banner 真实可见；`NoteWindowCoordinator.swift:359` 等空 catch 全部消除或指向真实 UI 面 |

**Phase 1 退出标准**：R1.1–R1.10 全部绿；三颗数据雷有回归测试锚定；无"菜单/指示器假象"残留；Sprint 回顾记录风险表（§1）命中情况。

---

## 3. Phase 2: 核心链路修复 (Sprint 2)

> 目标：让 WebDAV/S3 真实传输层首次进入测试覆盖（当前是**唯一从未被任何测试执行的子系统**），并修正状态码语义。
> 前置事实：`ProviderContractTests` 只实例化 LocalProvider；全测试树无 URLProtocol/mock 注入；`RealServiceCompatibilityTests` 两用例为 `#expect(true)`。

| 任务 ID | 任务名称 (Epic/Story) | 归属模块 | 前置依赖 | 🧪 Red Test 设计 (如何构造失败用例) | 验收标准 (DoD) |
|---|---|---|---|---|---|
| R2.1 | transport 注入 + WebDAV/S3 契约测试套件 | SyncCore | 无（Phase 2 最高优先） | ⑬ 注入 `URLProtocol` 替身（记录请求、回放响应）→ 对 WebDAVProvider 断言 PUT 请求方法/头/体、GET 往返、DELETE。当前 provider 内部 `URLSession` 不可注入、替身无法生效 → **红**（无注入点即测试无法构造 = 必须先建基建） | 两 provider 同跑一套契约测试（替换 LocalProvider 独占现状）；注入面仅限 URLSession 层，不重写封装；`AdapterTests` 的纯函数用例保留 |
| R2.2 | S3 `list()` 虚拟主机模式修复（host 缺 bucket + prefix 双次） | SyncCore | **R2.1** | ⑭ 契约测试断言虚拟主机模式请求 URL：host 含 bucket、`prefix` query item 恰一次。当前实现 host 无 bucket 且 prefix 追加两次 → **红** | pathStyle 与虚拟主机两模式均有契约断言；`verify()` 虚拟主机模式补 bucket 组件 |
| R2.3 | 状态码语义修正：501 假成功 / 405 误映射 | SyncCore | **R2.1** | ⑮ 回放 501 响应 → 断言条件创建抛错而非成功；⑯ 回放 405 → 断言独立错误而非 `conditionalFailed`；⑰ 412 → 保持 `conditionalFailed`。当前 501 静默成功、405 误映射 → **红** | 501 显式失败；405 独立错误用例；`SyncEngine` 对条件创建失败不再静默 adoption；新增"失败不产生远端条目"断言 |
| R2.4 | RealServiceCompatibilityTests 真实化（凭据存在时必须真实构造 provider） | SyncCore | **R2.1** | ⑱ 设置 `STICKY_WEBDAV_TEST_URL` 环境变量 → 断言测试真的实例化 `WebDAVProvider` 并执行一次往返。当前凭据存在也仅 `#expect(true)` → **红** | 凭据存在时执行真实往返（创建容器/条件 PUT/GET/DELETE）；缺凭据 skip 语义保留；`#expect(true)` 清零 |
| R2.5 | SyncCore 死码清理：mapStatus / key(fromURL:) / 永不抛的错误用例 | SyncCore | 无 | ⑲ 清理后全仓 grep 零引用 + 编译绿（编译期门控，无需行为测试） | `WebDAVProvider.mapStatus`、`S3Provider.key(fromURL:)`、`ProviderError` 未抛用例（.corrupt/.schemaUnsupported/.clockSkew/.wrongVault 之四选三）移除；同步删除引用它们的测试代码 |

**Phase 2 退出标准**：R2.1–R2.5 全绿；WebDAV/S3 真实传输路径进入每日 CI 覆盖（mock 契约套件）；凭据化套件在 CI 有凭据时真实执行。

---

## 4. Phase 3: 架构净化与现代化 (Sprint 3+)

> 目标：消灭双轨窗口系统与字符串消息传递；批量清理死代码；收敛重复实现；替换已确认废弃 API。
> 说明：P3 各任务无强依赖链（可并行批次），但 R3.1/R3.2 共享"窗口/菜单回归锚"，建议同一批次内先后合入。

| 任务 ID | 任务名称 (Epic/Story) | 归属模块 | 前置依赖 | 🧪 Red Test 设计 (如何构造失败用例) | 验收标准 (DoD) |
|---|---|---|---|---|---|
| R3.1 | 窗口系统统一：死 scenes 与手动 NSWindow 二选一；标题查找替换 | App | 无 | ⑳ 新建笔记首行含 "Settings" → 打开 Settings → 断言焦点落在 Settings 窗口而非笔记窗口。当前 `title.contains("Settings")` 查找必然抢错 → **红** | About/Help 只保留一种实现（scene 或手动窗）；`NSApp.windows.first(where: $0.title...)` 全部移除，改场景/注册表身份；`NoteWindowLifecycleTests` 增"标题撞名"回归 |
| ~~R3.2~~ ✅ | NotificationCenter Insert 直调化（4 条菜单动作直调 coordinator；通知定义/观察者/deinit 清理全删）| App | 无 | ㉑ 移除通知定义与观察者后，菜单清单测试（Insert 四条动作）仍绿 = 行为等价。当前动作依赖通知、直接调用不存在 → 先改调用再删通知（红=缺直调路径） | `SettingsView` 中的 Notification.Name 扩展与 Coordinator 观察者全部移除；`postInsertion` 删除；菜单行为不变（清单测试作锚） |
| R3.3 | 死代码批次清理（全清单：TrashView / MenuCommandCatalog / TodoCardProgress App 副本 / CardPreview / importNoteJSON / ShortcutRecorderPolicy / makeUndoManager / 恒真 precondition 等） | App + Core（各归属模块） | 无 | ㉒ 每删一个符号：全仓 grep 零引用 + 编译绿（编译期门控） | 审计 §3.2 清单清零；同步删除仅测试引用的测试用例；`EmptyStateView`/`MenuCommands` 假注释修正 |
| ~~R3.4~~ ✅ | `activate(ignoringOtherApps:)` → `activate()`（生产 9 + 测试 2，残留 0）| App + SystemBridge | 无 | ㉓ 无行为测试（机械替换）；门控 = 全仓 grep 残留 0 处 | 9 处清零；编译绿 + 启动冒烟（macOS 14+ 语义等价） |
| ~~R3.5~~ ✅ | AutoLinkDetector → NSDataDetector（电话 E.164 归一化/本地号保留原文）；FTS MATCH → FTS5Pattern；手写 RTF 因 EditorCore 模块边界（不可 import AppKit）保留，记录为已知项 | EditorCore + Persistence | 无 | ㉔ AutoLinkDetector 输出与 NSDataDetector 对同一语料断言一致（URL/email/phone）；㉕ 替换 FTS 查询构造后，既有搜索用例断言等价 | 手写扫描器/手拼查询/手写 RTF 删除；等价性回归测试入库；电话号码本地号不再被破坏 |
| ~~R3.6~~ ✅ | SHA256 收敛到 SecurityCore.SHA256DigestHash（顺带修复 SyncEngine 字节-hex 假哈希真 bug）；HTTP-date×3→SyncHTTPDateParser；canonicalJSON 统一 sortedKeys+withoutEscapingSlashes | SecurityCore + SyncCore | 无 | ㉖ 收敛后所有调用方改用单点导出（编译门控）+ 既有向量测试保持绿 | 每类收敛到一处导出；`canonicalJSON` 全部采用 sortedKeys + withoutEscapingSlashes 同配置；跨模块契约文档（contentHash 格式）同步 |
| ~~R3.7~~ ✅ | 🔬 Research Spike：macOS 27 (Golden Gate) App Actions / Spotlight 集成评估 | App | 无（研究型） | 不适用（无行为断言） | **评估结论（2026-08-14）**：① **App Actions 建议立项**——AppIntents 暴露 "New Note"/"Search Notes"（菜单栏 app 的 Siri/Spotlight 可执行性，中等成本）；② **Spotlight 索引默认关闭**——便签内容入系统索引违反隐私优先宪法（内容不离开 app），仅可作未来 opt-in；③ 统一工具栏/边到边侧栏/Liquid Glass 为系统自动适配，App 的 .unified 工具栏与统一圆角方向已对齐，无需代码动作（手动 UI 验证项） |
| ~~R3.8~~ ✅ | AGENTS.md/Package.swift/HelpView(+xcstrings)/AppEnvironment/SyncAttentionBanner 全同步；**xcstrings 接入 Xcode 项目**（原 folder 引用不编译——本地化首次真正生效）| specs + App | R3.7 结论（如需并入） | 不适用（文档）；门控 = 人工一致性复核 | AGENTS.md 删除"无应用代码/仅一个 commit"过期声明并修正工具链目录；Package.swift 移除 WidgetExtension 提及；HelpView 文案与真实编辑路径一致 |

**Phase 3 退出标准**：R3.1–R3.8 完成；`#expect(true)` 与常数自断言清零；CI 门控（§5）生效后无新债产生。

---

## 5. CI/CD 与工程化门控建议

针对审计发现的"测试自证（`#expect(true)`）"与"死代码"两类系统性问题，设计三条可落地的自动化拦截规则：

### 门控 G1：空断言拦截（`#expect(true)` 清零）

- **机制**：CI 新增 job（或复用现有 test job 的 pre-flight 步骤），对 `Packages/StickyCore/Tests` 与 `AppTests` 全量扫描以下模式，任一命中即构建失败：
  - `#expect(true)` / `#expect(true == true)` / `XCTAssertTrue(true)` 等恒真断言
  - `guard … else { #expect(true); return }` 类"权限分支空通过"模式（CaptureTests 形态）
- **豁免**：注释标注 `// coverage-only` 的显式例外需 code review 批准（白名单文件）。
- **落地形态**：`scripts/scan-vacuous-asserts.sh` + CI workflow 步骤；或 SwiftLint `custom_rules`（regex 规则，`severity: error`）。

### 门控 G2：常数自断言拦截（防"断言常量 vs 自身"）

- **机制**：扫描 `#expect(<标识符链> == <字面量>)` 形态——左端为无参静态/常量属性（如 `FontPreferenceUI.singleNoteFontConcept == true`、`DatabaseStore.defaultBusyTimeout == 5.0`），右端为字面量，且断言不经过任何方法调用/输入构造——命中即失败。
- **原理**：该形态只证明"源码与测试同步编辑"，不证明行为；合法场景（如"默认值文档化"）必须改写为行为断言（通过真实调用路径观察副作用）。
- **落地形态**：SwiftLint custom rule（regex 分两条：布尔字面量与数字字面量）；初始一次全量清理后再开启 error 级。

### 门控 G3：死代码与"仅测试引用"守卫

- **机制 A（硬门）**：CI 对项目 target 构建开启 unused-declaration 告警转错误（Swift 6 `-warnings-as-errors` 已生效，补充 `-enable-upcoming-feature` 相关告警面）；对"生产 public 符号仅测试引用"输出清单。
- **机制 B（软门/报告）**：`scripts/dead-code-scan.sh` 每周或发布前运行：grep 生产 `public`/`internal` 声明，过滤后输出"零生产引用"清单；超过阈值（如 10 个符号）CI 失败并链接到审计 §3.2 清单。
- **机制 C（漂移守卫）**：菜单/命令一致性——`MenuChecklistTests` 类测试与真实 `.commands` 双源对齐：CI 脚本断言"手写菜单中的每个 Button 文案/快捷键在清单测试中有对应断言"，防止 catalog 式假单一来源卷土重来。

### 门控执行顺序（合入门定义）

```
PR 门:  G1 + G2（扫描） + G3-A（编译告警）   → 失败即阻塞合入
每周:   G3-B（死代码报告）                 → 失败仅告警，纳入下 Sprint 清理
发布门: G3-C（菜单一致性）+ 全量基线回归     → 失败即阻塞发布
```

### 度量与回顾

- 每个 Sprint 末统计：空断言数（应恒为 0）、死代码符号数（应单调下降）、契约测试覆盖 provider 数（P2 后应 = 2）。
- 指标进入 Sprint 回顾；连续两 Sprint 归零后可降级 G1/G2 为告警级（防止规则本身变成技术债）。

---

## 附：与审计报告的映射索引

| Roadmap 任务 | 审计报告证据（file:line） |
|---|---|
| R1.1/R1.2 | `AssetStore.swift:74-75, 287-304`；`AppEnvironment.swift:124`；`NoteWindowHostModel.swift:1183-1209` |
| R1.3 | `VaultBootstrap.swift:142, 217, 442-460` |
| R1.4 | `NoteRepository.swift:93-99, 642-650` |
| R1.5 | `KeyDerivation.swift:31-36, 117`；`VaultBootstrap.swift:186-214` |
| R1.6 | `StickyNotesApp.swift:167-173, 335-342` |
| R1.7 | `CodeBlockView.swift:182, 187`；`RichTextBlockView.swift:396-399`；`NoteWindowHostModel.swift:1025-1039` |
| R1.8 | `NoteLifecycleTests.swift:185`；`NoteLifecycle.swift:16-17` |
| R1.9 | `NoteDocumentSerializer.swift:75-90` |
| R1.10 | `LibraryModel.swift:53-54, 217-343`；`NoteWindowCoordinator.swift:359-361` |
| R2.1 | `ProviderContractTests.swift:11-27`；`AdapterTests.swift:15-20` |
| R2.2 | `S3Provider.swift:209-229, 104-123` |
| R2.3 | `S3Provider.swift:166-169`；`WebDAVProvider.swift:116-117`；`SyncEngine.swift:318-320` |
| R2.4 | `RealServiceCompatibilityTests.swift:24-44` |
| R2.5 | `WebDAVProvider.swift:236-263`；`S3Provider.swift:94-100`；`ProviderErrors.swift:12-36` |
| R3.1 | `StickyNotesApp.swift:123-131, 531-533, 551, 581-624`；`NoteWindowDerivations.swift:142-150` |
| R3.2 | `SettingsView.swift:173-180`；`StickyNotesApp.swift:712-714`；`NoteWindowCoordinator.swift:71-91` |
| R3.3 | 审计 §3.2 全清单（TrashView/MenuCommandCatalog/TodoCardProgress/CardPreview/importNoteJSON 等） |
| R3.4 | `StickyNotesApp.swift:304, 328, 339, 458, 484, 529, 691`；`NoteWindowCoordinator.swift:262`；`NoteWindowBridge.swift:117`（官方：macOS 14.0 起废弃） |
| R3.5 | `AutoLinkDetector.swift:27-135`；`FullTextSearch.swift:61-69`；`CrossBlockSelection.swift:116-184, 227-244` |
| R3.6 | `EncryptedEnvelope.swift:157`；`SyncEngine.swift:915`；`S3Provider.swift:507`；`AssetStore.swift:317`；`RemoteManifest.swift:108`；`WebDAVProvider.swift:265, 298`；`S3Provider.swift:312` |
| R3.7 | 审计 §2.4（macOS 27 Golden Gate 方向核实） |
| R3.8 | `AGENTS.md:3`；`Package.swift` 头注释；`HelpView.swift:38-39, 49`；`AppEnvironment.swift:25-26, 74-75`；`SyncAttentionBanner.swift:9-14` |
