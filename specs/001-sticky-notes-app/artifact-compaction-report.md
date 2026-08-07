# Artifact Compaction Report — 001-sticky-notes-app

**日期**: 2026-08-07 | **状态**: 分析报告（第一步，未修改任何 artifact）

**目标**: 将 SDD artifacts 的"当前有效状态"与"历史记录"分离，降低后续
`speckit.plan` / `speckit-tasks` / `speckit-implement` 的上下文消耗。

**分析方法**: 全文阅读 constitution / spec / plan / research / tasks /
data-model / contracts / checklists / quickstart，交叉核对实现代码
（`Packages/StickyCore/Sources`、`App/Sources`）与 git history
（最近 8 个提交），区分"当前约束"与"已被取代的决策"。

---

## 1. 总体结论

- 所有稳定标识符（FR-*、US-*、AC-*、SC-*、T-*、R0–R43、CHK*）全部仍被引用，
  无一需要删除或重编号。
- constitution.md 不修改（规则 1）。
- contracts/ 不修改（规则 8）——它们是当前有效的契约，且已高度精炼。
- 主要可压缩来源是 **plan.md（25–30%）** 和 **tasks.md（20–30%）**；
  spec.md 只可移动 ~1–2%（Clarifications Q/A 日志），research.md 可减 7–9%
  （propagation 历史块）。
- 建议新建 `history/` 子目录承载所有归档内容（规则 11：默认不进入 implement
  上下文）。
- 发现 8 项 NEEDS_REVIEW（见 §8），其中 2 项是"文档描述 vs 实现代码"的过时
  描述，2 项是残留旧值示例，均在执行阶段需要用户确认。

**当前规模与建议目标**：

| 文件 | 当前行数 | 建议减少 | 目标行数 | 说明 |
|------|---------:|---------:|---------:|------|
| spec.md | 1497 | ~1–2% | ~1480 | 仅归档 Clarifications Q/A 段 |
| plan.md | 1145 | ~25–30% | ~800–850 | 归档 6 个 propagation 块 + 压缩 post-design Check |
| research.md | 1359 | ~7–9% | ~1240 | 归档 6 个 propagation 块 + R0 caveat 压缩 |
| tasks.md | 926 | ~20–30% | ~650–750 | 压缩已完成任务的实施日志、标记 superseded 任务 |
| data-model.md | 688 | ~1% | ~680 | 修复残留旧示例值 |
| contracts/ | ~540 | 0% | 不变 | 规则 8 |
| checklists/ | ~490 | 0% | 不变 | 审计产物，CHK 状态即当前状态 |
| quickstart.md | 235 | 0% | 不变 | 验证指南 |
| **合计** | **~6846** | **~10–15%** | **~6000–6200** | |

---

## 2. 逐文件分析

### 2.1 constitution.md（.specify/memory/）— 不动

- **必须保留**: 全部十四条原则 + Governance + Version 行。无任何 superseded
  内容。
- **问题（轻）**: 文件头 1–84 行是 `<!-- -->` 包裹的 "Sync Impact Report" 模板
  初始化注释。它记录了一次性操作历史（initial adoption），对当前无约束力。
- **建议**: 规则 1 禁止删除/弱化原则，但头部注释不是原则内容。**建议移入
  history/ 或删除**（提交历史已保留该记录）——需用户确认（见 §8 NEEDS_REVIEW-1）。
- **缩减**: 最多 -84 行（5.8 KB 的 12%）。

### 2.2 spec.md（1497 行）— 当前有效需求，微调

**必须保留（全部）**: US1–US10 及所有 Acceptance Scenarios、Edge Cases、
Scope（in/out）、全部 FR（FR-001…FR-191，含 FR-012a/014a/014b/020a/022a/
022b/023a/031a/040a/041a/043a/050a/054/072a/072b/090a/090b/094a/094b/095a/
110a/140a/141a/152a/160a–160e/162a/180a/001a 等所有 a/b 变体）、NFR/约束
（FR-090b 数值、FR-160c 参数、FR-022a 数值等）、Key Entities、SC-001…SC-011、
Assumptions。这些全部是当前有效需求，逐条核对过——没有任何 FR 被后续决定
取代。

**可归档（唯一移动项）**:
- §Clarifications 的 "### Session 2026-08-07" Q/A 日志（spec.md:22–49，26 行）。
  这 26 条 Q/A **全部**已编码为对应 FR（FR-001a/FR-012a/FR-014b/FR-020a/
  FR-022a/FR-022b/FR-031a/FR-040a/FR-041a/FR-043a/FR-050a/FR-054/FR-072b/
  FR-090b/FR-094b/FR-095a/FR-110a/FR-141a/FR-152a/FR-160e/FR-180a 等），
  正文 FR 已完整承载其语义。按规则 3，属历史信息。
- **保留替代**: 文件头 11–21 行的 FR 编号清单（"clarifications encoded in
  FR-001a, FR-012a…"）保留——它是当前有效的 traceability 索引。
- 注意：文件头 19 行说 "The original question-and-answer log is preserved in
  the feature branch history"——git history 中并不存在独立 Q/A 文件（仅有
  提交记录）。归档时必须真正创建 `history/clarifications.md`，不能依赖该
  声称。

**问题**:
- "Status: Draft"（第 7 行）与实际状态不符——实现已进行到 Phase 16–19
  收敛完成、Phase 20–23 规划中。需更新为 "In Implementation"（NEEDS_REVIEW-2）。
- FR-094b（spec.md:1036）正文引用 "per tasks.md T152"——spec 引用 tasks
  实施细节，违反职责分离（规则 10）的轻微情况；但该引用是 FK 约束的落地
  依据，建议改为仅描述约束本身（FK 存在性由 T152 验证），删除 "tasks.md
  T152" 字样——需用户确认（NEEDS_REVIEW-3）。

**缩减**: -17～-25 行（~1–2%）。spec 是 WHAT 的权威，压缩空间天然很小。

### 2.3 plan.md（1145 行）— 主要压缩对象

**必须保留**: Summary、Technical Context（当前基线：Swift 6.3 / macOS 26 /
GRDB+Argon2id）、Project Structure、全部架构章节（Module boundaries、Scenes、
State/concurrency、Local storage、Canonical representation、Editor、Markdown、
Todo、Code blocks、Auto-save、Search、Asset storage、Note appearance、
Screenshot capture、File-reference、Widgets、Global shortcuts、Permissions、
Encryption、Remote vault layout、Provider protocol、WebDAV/S3 adapter、Sync
engine、Conflict model、Deletion/tombstones、Repository replacement、
Diagnostics、Error model、Accessibility、Localization）、Constitution Check
表（第一张）、Delivery Milestones、测试策略结论。

**可归档（历史记录）**:
1. **6 个 "clarification propagation" 引用块**（plan.md:109–228，约 120 行）。
   每一块都是 "2026-08-07 第 N 次 clarify 已编码为 FR-xxx" 的**变更日志**，
   其内容已全部落入 spec FR 与 plan 正文。按规则 4（不要为了保存开发日志而
   保留 obsolete plan），整体移入 `history/plan-superseded.md`。
2. **Toolchain note（plan.md:73–83，约 11 行）**: "生成此计划的环境只有 CLT，
   xcodebuild 不可用"——这是 2026-08-06 生成时的环境历史。当前仓库已有
   Xcode-beta 可编译 GUI 原型（tasks T158），该 caveat 不再反映现状。
   压缩为一行（"部署目标基线见 research R0"）或移入 history。
3. **"tasks.md NOT produced by this command" 注记（plan.md:7–9）**:
   tasks.md 现已存在（926 行），此注记是历史。
4. **"Constitution Check (re-evaluated after Phase 1 design)" 长段**
   （plan.md:992–1143，约 150 行）: 其中约 40 条逐条重述了 6 个 propagation
   块的内容（每条 "FR-xxx (clarified 2026-08-07)…" 重复正文已述内容）。
   建议压缩为 ~40 行：保留结论（PASS、无 violation、无 Complexity
   Tracking 例外）+ 一份 FR 编号清单（指向 spec），删除逐条 rationale 复述。

**正文重复（压缩但不删除）**:
- Encryption architecture 中的 FR-160e（3 段）、FR-162a（3 段）长文
  （plan.md:730–759）与 spec FR-160e/FR-162a 全文重复。plan 应保留 HOW
  （"boot-timestamp 比较是重启检测机制"）而删除对 spec 条文的大段复述
  （WHAT 在 spec）。预计 -40～-60 行。
- 多处 "clarified 2026-08-07" 标注本身保留（它们标识当前有效），但"决策
  理由"已在 research.md 的 R 条目中，plan 中重复的 Rationale 句可删除。

**缩减**: -280～-350 行（25–30%）。

### 2.4 research.md（1359 行）— WHY 的权威，微调

**必须保留**: R0–R43 的 Decision / Rationale / Alternatives / Risks /
Validation / Constitution impact 结构。逐条核对：**没有任何 R 条目被后续
决定推翻**（R15/R21/R9/R17 的 "refined" 都是增强而非取代，其原文段落
已包含最新语义，无需移动）。"Resolved NEEDS CLARIFICATION" 段保留
（它是当前有效声明）。

**可归档（历史记录）**:
- **6 个 "clarification propagation" 引用块**（research.md:1253–1345，约
  93 行）。与 plan.md 同类：变更日志，内容已落入 R15–R43 正文。
  移入 `history/research-superseded.md`。

**问题**:
- R0 的 "Verification caveat"（research.md:10–18）与 R0 内文（"this plan was
  generated without a full Xcode install"）是生成环境历史；R0 的**决策**
  （macOS 26 / Xcode 26.x / Swift 6.3 基线）仍是当前基线。建议保留决策、
  将 caveat 压缩为一行（详见 §8 NEEDS_REVIEW-4）。

**缩减**: -100～-120 行（7–9%）。

### 2.5 tasks.md（926 行）— NEXT / 执行状态，主要压缩对象之二

**必须保留**: 全部 T-* 标识符、依赖关系（Phase dependencies、User Story
dependencies、Within-story 顺序）、未完成任务（`[ ]`）的语义、测试优先
规则、Phase 结构。按规则 6：不重新设计任务、不改变未完成任务语义、不因
压缩重编号。

**可压缩（仅限已完成 [X] 任务的实施日志）**:
- Phase 16–19 已勾选任务的**长描述**（T176–T221，每条 2–5 行的 audit/
  rationale 注记，如 "**partial**: headless prototypes PASS…"）——实施完成
  后，这些过程性注记属于开发日志。建议压缩为一行（ID + 状态 + 文件路径），
  详细注记移入 `history/tasks-log.md`（规则 6：只在安全情况下归档）。
- Phase 14/15 已勾选任务（T152–T157、T173）同理。

**可标记 superseded（不删除，保留 ID）**:
- Phase 15 的 Note 已声明 "T159–T172 supersede T032–T119 中仍为 [ ] 的任务"
  （tasks.md:488–492）。Phase 3–12 中仍为 `[ ]` 的原始任务（T029/T032–
  T037/T041/T044/T048–T049/T052–T055/T059–T060/T062–T063/T065–T067/T075/
  T080–T081/T086/T091–T093/T098–T101/T105/T119–T120/T121–T130 等）与被
  T159–T172 取代的任务：**保留任务行**（ID、依赖、所属 story），但可在
  描述末尾追加一行 "→ superseded by T1xx（当前有效）" 标记，将原长描述
  压缩。这符合规则 6（保留 ID 和依赖关系）与规则 4（历史方案不占据当前
  上下文）。
- 注意：**不要**在本次压缩中勾选或取消任何任务状态——状态对账是 T174/
  T158 等任务自己的职责。

**已发现的问题（过时描述，NEEDS_REVIEW）**:
- T031（tasks.md:109）仍写 "debounce ~300ms"，但实现
  `EditorCore/AutoSave.swift` 的 `defaultDebounceInterval = 0.5`（500 ms，
  FR-141a 已落地）；T238 的 audit 注记 "debounce exists ~300 ms" 也已过时。
  这是"任务描述 vs 实现"的漂移，不是任务语义——压缩时改为引用 FR-141a
  （NEEDS_REVIEW-5）。
- T046 已自行标注 "textSize portion superseded by FR-043a (enum→integer
  model, re-verified by T252/T257)"——正确的 superseded 处理范例，保留。

**缩减**: -200～-300 行（20–30%）。

### 2.6 data-model.md（688 行）— 微调

**必须保留**: 全部实体表、Synced? 列、Constraints、State Transitions、
Indexes、Migration strategy、Asset/Tombstone/Conflict-copy lifecycle、
Version lineage。这些是当前权威（Persistence 迁移与契约的源头），且已
高度浓缩。FR-022a/FR-040a/FR-041a/FR-043a/FR-090b/FR-094a/FR-160c/
FR-162a/FR-174/FR-191 的数值已正确内嵌在字段注释中。

**问题（残留旧值示例）**:
- "Example records" 段的 Note 示例（data-model.md:615）仍写
  `"textSize": "regular"`，与同文件 §Note 字段表（"9–24 整数，默认 13"）及
  contracts/note-document.schema.json（integer 9–24）矛盾。FR-043a 已明确
  枚举→整数模型且无迁移。这是残留的旧示例，执行阶段更新为 `13`
  （NEEDS_REVIEW-6）。TodoItem 示例中 `"depth": 0`（顶层应为 1，见 FR-072a
  "depth 从顶层=1 起算"）也需核对（NEEDS_REVIEW-7）。

**缩减**: 0～-10 行（<2%），主要是示例值修正。

### 2.7 contracts/（13 文件，~540 行）— 不动

规则 8：schema/API/约束/兼容性/性能/安全要求不得通过概括弱化。全部 13 个
文件已含精确约束与 FR 引用（$comment 引用 FR-160d/160e/090b/094a 等），
无重复内容，无 superseded 内容。**不修改**。

### 2.8 checklists/（4 文件，~490 行）— 不动

- requirements.md: 全部勾选 + 1 条历史注记（menu-bar re-click 澄清记录）。
  该注记是 2026-08-06 的历史，但已编码为 FR-009 且在 git 提交中；可移入
  history 或保留（仅 ~7 行，保留成本低）。
- ux.md / data.md / security.md: CHK 编号是稳定标识符；未勾选项（CHK006/
  CHK009/CHK014/CHK015/CHK055/CHK061/CHK063/CHK076/CHK080/CHK084/CHK095）
  代表**开放要求**，必须保留。CHK 条目的 Gap/Ambiguity 标注是当前审计状态。
  **不修改**（除 requirements.md 的历史注记可选归档外）。

### 2.9 quickstart.md（235 行）— 不动

验证/运行指南，无历史包袱。FR-014a/SC-004a/FR-141a 等验证步骤均为当前
有效。**不修改**。

---

## 3. 跨文件重复内容清单（规则 10：spec=WHAT / plan=HOW / research=WHY）

| 主题 | spec（保留） | plan（压缩/引用） | research（保留） | 其他权威副本 |
|------|-------------|------------------|-----------------|-------------|
| FR-160c Argon2id 参数 (19MiB/2/1) | FR-160c | Encryption arch. 大段复述 → 引用 | R9 | vault-bootstrap.schema.json |
| FR-160d fail-closed 八输入 | FR-160d | 复述 → 引用 | R24 | encrypted-envelope.schema.json $comment |
| FR-160e 无锁定策略 | FR-160e | 3 段复述 → 引用 | R31 | encrypted-envelope.schema.json $comment |
| FR-162a remember-unlock | FR-162a | 3 段复述 → 引用 | R21/R33 | data-model §VaultConfiguration |
| FR-174 长离线 tombstone 协调 | FR-174 | Deletion 段复述 → 引用 | R15 | data-model §Tombstone lifecycle |
| FR-191 诊断包字段枚举 | FR-191 | Diagnostics 段复述 → 引用 | R22 | data-model §DiagnosticSnapshot + diagnostic-bundle.schema.json |
| FR-012a meaningful-text | FR-012a | Auto-save 段复述 → 引用 | R30 | tasks T212/T217 |
| FR-022a/022b sort-key | FR-022a/022b | Local storage/Conflict 段 → 引用 | R25/R32/R35 | data-model §Conventions/Constraints |
| FR-090a/094a 资产同步/缩略图 | FR-090a/094a | Asset storage 段 → 引用 | R27/R25 | data-model §Asset + asset-metadata.schema.json |
| FR-141a/152a debounce | FR-141a/152a | Auto-save/Sync engine → 引用 | R17/R25 | 实现 AutoSave.swift (0.5s) |
| FR-001a/020a/043a/095a/054 | FR-xxx | 各处 → 引用 | R40–R43 | tasks Phase 23 |

处理原则：**保留所有事实的唯一权威副本**（通常 spec 或 contracts），plan 中
的重复段落压缩为一句"见 spec FR-xxx / research Rxx"；**不把同一事实复制到
两处**。

---

## 4. Superseded 内容清单（已被后续决定替代）

| 内容 | 位置 | 被什么取代 | 处理 |
|------|------|-----------|------|
| textSize 枚举 small/regular/large/extraLarge | 旧 spec/plan/data-model 描述 | FR-043a 整数 9–24 | 已更新；仅残留 data-model 示例 (615 行) 需修 |
| 缩略图 512px 默认 | 旧 plan §Asset storage | FR-094a 256px（T197 已改实现） | 已更新，无残留 |
| autosave "~300ms" 描述 | tasks T031/T238 注记 | FR-141a 500ms（实现已 0.5s） | 压缩时修正（NEEDS_REVIEW-5） |
| 6 个 propagation 变更日志 | plan.md:109–228 | 正文已融合 | → history/plan-superseded.md |
| 6 个 propagation 变更日志 | research.md:1253–1345 | R15–R43 已融合 | → history/research-superseded.md |
| 26 条 clarify Q/A | spec.md:22–49 | 已编码为 FR | → history/clarifications.md |
| plan Toolchain caveat | plan.md:73–83 | 环境已变化 | → history/ 或压缩为一行 |
| post-design Check 的 40 条逐条复述 | plan.md:992–1143 | 正文已述 | 压缩为结论 + FR 清单 |

---

## 5. 可归档内容清单（→ 新建 history/ 目录）

| 目标文件 | 来源 | 内容 | 约行数 |
|---------|------|------|-------:|
| history/clarifications.md | spec.md:22–49 | 26 条 clarify Q/A 日志（含原问题、答案、对应 FR） | 26 |
| history/plan-superseded.md | plan.md:109–228, 7–9, 73–83, 992–1143 | 6 个 propagation 块 + 过时注记 + post-design Check 原文 | ~280 |
| history/research-superseded.md | research.md:1253–1345 | 6 个 propagation 块 | ~93 |
| history/tasks-log.md（可选） | tasks.md 已完成任务的详细注记 | T152–T157/T173/T176–T221 等的 audit/partial 注记 | ~150–250 |

history/ 各文件头部须注明：**"本目录内容为历史记录，后续 speckit.plan /
tasks / implement 默认无需阅读；如需追溯某决定的演变过程再查阅。"**
（规则 11）

---

## 6. 必须保留内容清单（压缩时零容忍）

- constitution.md 全部原则（规则 1）。
- spec.md：全部 US/AC/Edge Cases/Scope/FR/NFR 数值/Key Entities/SC/Assumptions。
- plan.md：架构决策全部章节 + 第一张 Constitution Check 表 + Milestones。
- research.md：R0–R43 的 Decision/Rationale/Alternatives/Validation。
- tasks.md：全部 T-ID、依赖关系、未完成任务语义、测试优先规则。
- data-model.md：全部实体/约束/迁移/生命周期。
- contracts/ 13 个文件逐字节。
- checklists/ 全部 CHK 条目与未勾选状态。
- 稳定标识符：FR-*、NFR-*（本 feature 无 NFR- 前缀编号，NFR 以 FR- 内嵌）、
  US-*、AC-*、SC-*、T-*、R0–R43、CHK*——一律不重编号。

---

## 7. NEEDS_REVIEW 清单（无法单凭文档判定"历史 vs 当前"，不删除、待确认）

1. **constitution.md 头部 84 行 Sync Impact Report 注释**：是初始化一次性
   记录。建议删除或移入 history（原则内容零损失），但需用户确认。
2. **spec.md "Status: Draft"**：实现已进行，状态过时。建议改
   "In Implementation"。
3. **spec.md FR-094b 引用 "tasks.md T152"**：spec 引用任务编号，违反
   职责分离。建议删该字样、保留 FK 约束描述本身。
4. **research.md R0 caveat**：生成环境历史 vs 当前基线决策。建议保留决策、
   压缩 caveat 为一行。
5. **tasks.md T031/T238 的 "~300ms" 描述**：实现已是 500ms（FR-141a）。
   压缩时改为引用 FR-141a；但这是"任务描述变更"，需用户确认是否超出
   规则 6 允许范围。
6. **data-model.md Example records `"textSize": "regular"`**：与 schema
   (integer 9–24) 矛盾。建议更新为 `13`。
7. **data-model.md Example records `"depth": 0`**：FR-072a 定义顶层 depth=1，
   示例值存疑。建议核对后修正为 1 或加注。
8. **checklists/requirements.md 的 menu-bar re-click 历史注记**：可选归档。
   保留（7 行）成本更低，倾向保留。

---

## 8. 建议修改后的目录结构

```text
specs/001-sticky-notes-app/
├── spec.md                        # WHAT — 当前有效需求（微调）
├── plan.md                        # HOW — 当前实现方案（压缩 25–30%）
├── research.md                    # WHY — 当前技术决策（压缩 7–9%）
├── data-model.md                  # 数据模型 — 当前权威（修正示例）
├── tasks.md                       # NEXT / 执行状态（压缩 20–30%）
├── quickstart.md                  # 验证指南（不变）
├── contracts/                     # 契约（不变，规则 8）
│   └── …13 个文件…
├── checklists/                    # 审计清单（不变）
│   ├── requirements.md
│   ├── ux.md
│   ├── data.md
│   └── security.md
├── artifact-compaction-report.md  # 本报告
└── history/                       # 历史归档（新增；默认不进入 implement 上下文）
    ├── clarifications.md          # spec 旧 Q/A 日志（已融合为 FR 的）
    ├── plan-superseded.md         # plan 旧 propagation 块与过时注记
    ├── research-superseded.md     # research 旧 propagation 块
    └── tasks-log.md               # 已完成任务的详细实施日志（可选）
```

---

## 9. 执行原则（第二步执行时的约束）

1. 先处理 NEEDS_REVIEW 的 8 项确认，再动手。
2. 每次修改一个文件；spec/plan/research/tasks/data-model 逐个执行，每步
   后核对标识符引用（grep FR-/T-/R- 编号无断链）。
3. history/ 内容从原文件**移动**而非复制（规则 10：不保留双份）。
4. tasks.md 只压缩已完成任务的注记与标记 superseded；不勾选/取消任务、
   不修改依赖、不改变 [ ] 任务描述语义。
5. contracts/、checklists/、quickstart.md、constitution.md 默认不动
   （除 NEEDS_REVIEW-1/8 经确认后）。
6. 压缩完成后对 spec/plan/research 运行一次全文一致性抽查（如 grep
   FR-094b 的 T152 引用是否已清理）。

**预期收益**: 总行数 ~6846 → ~6000–6200；plan/tasks 的上下文消耗显著
下降；spec/plan/research 职责边界清晰（WHAT/HOW/WHY 各一份权威）。
