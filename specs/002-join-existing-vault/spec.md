# Feature Specification: Join Existing Vault (Cross-Device Sync)

**Feature Branch**: `002-join-existing-vault`

**Created**: 2026-08-08

**Status**: Draft

**Input**: User description: "用户在一个设备上配置同步（WebDAV 或 S3）并创建加密 vault；在另一台设备上指向同一仓库位置、输入相同密码，即可加入同一 vault 并双向同步笔记。当前 001 只支持'创建新 vault'（每次生成随机 locator，两端各自独立、互不可见），'加入现有 vault' 未实现。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 第二台 Mac 加入现有 vault（P1）

用户在两台 Mac 上使用同一 WebDAV/S3 仓库同步笔记。设备 A 已配置同步并创建了 vault（生成随机 vault locator）。设备 B 在同步设置中选择"加入现有 vault"，输入设备 A 的 vault locator 与相同的同步密码，加入同一 vault，两端笔记双向同步。

**Why this priority**: 跨设备同步是 001 同步功能的承诺（US9/US10），但缺少"加入"路径则第二台设备永远无法同步。这是 P3 功能（001）中用户最直接缺失的环节，单独交付即有完整价值。

**Independent Test**: 设备 A 创建 vault 后，在设备 B 上用同一仓库配置 + 相同密码加入，创建一条笔记，设备 A 通过手动同步看到该笔记（反之亦然）。

**Acceptance Scenarios**:

1. **Given** 设备 A 已配置仓库并创建 vault，**When** 设备 B 在同步设置选择"加入现有 vault"并输入正确的 locator 与密码，**Then** 加入成功，设备 B 显示与设备 A 相同的 vault（同一 locator），两端状态行显示同一协议与最近同步时间。
2. **Given** 设备 B 输入错误密码，**When** 用户提交加入，**Then** 加入失败并显示明确错误（密码错误），**And** 不写入任何本地配置、不修改任何远程数据。
3. **Given** 设备 B 输入不存在的 locator，**When** 用户提交加入，**Then** 加入失败并显示明确错误（远程未找到该 vault），不创建任何远程对象。
4. **Given** 设备 B 本地已有笔记，**When** 加入成功后首次同步，**Then** 本地笔记加密上传到该 vault（而非被远程覆盖），设备 A 可看到它们。
5. **Given** 两端离线分别编辑同一笔记，**When** 两端同步，**Then** 产生冲突副本（复用 001 冲突处理），不静默覆盖。
6. **Given** 设备 B 已配置另一个 vault（本地存在旧配置），**When** 用户选择加入，**Then** 按 001 的替换语义：本地笔记保留、新 vault 加入、旧远程数据不删除。

---

### User Story 2 - 通过配置文件导入/导出 locator（P2）

用户不手动抄录 vault locator，而是从设备 A 导出同步配置文件（含 locator 与协议信息，不含凭据/密钥），在设备 B 导入后只需输入密码即可加入。

**Why this priority**: 手动输入随机 32 字符 locator 容易出错；配置导出/导入显著降低配置成本。复用 001 已有的 `contracts/sync-profile-export.schema.json` 契约。

**Independent Test**: 设备 A 导出配置文件 → 设备 B 导入 → 输入密码 → 加入成功。

**Acceptance Scenarios**:

1. **Given** 设备 A 已配置同步，**When** 用户导出同步配置文件，**Then** 生成的文件包含协议类型、vault locator 与来源设备显示名及重删减的连接配置（端点、前缀/容器路径等连接所需信息；不含凭据、密钥或任何笔记内容），**And** 文件符合 `sync-profile-export.schema.json`。
2. **Given** 设备 B 收到该配置文件，**When** 用户导入并输入密码，**Then** 自动填充协议与 locator（界面显示来源设备名，仅需密码），加入成功。
3. **Given** 导入的文件损坏或 schema 版本不支持，**When** 用户导入，**Then** 失败关闭（fail closed）：不写入任何本地配置。
4. **Given** 设备 B 已配置仓库但未抄录 locator，**When** 用户在加入模式扫描仓库，**Then** 显示仓库中现有 vault 列表（创建时间 + locator 前缀），选择后自动填充 locator，输入密码即可加入；仓库为空时提示"未找到现有 vault"。

---

### User Story 3 - 加入后的多设备安全边界（P3）

加入同一 vault 的设备之间遵循 001 已确立的安全与数据完整性保证：错误密码不产生状态累积、删除传播有 30 天墓碑、长期离线设备不复活/不自动删除本地内容。

**Why this priority**: 这些是 constitution（VII/VIII）的既有保证，本 feature 必须验证其在"加入"路径下同样成立，而非重新实现。

**Independent Test**: 设备 B 加入后模拟错误密码、离线 30 天、删除冲突等场景，验证行为与 001 一致。

**Acceptance Scenarios**:

1. **Given** 已加入的 vault，**When** 用户连续输入错误密码（加入/解锁），**Then** 每次失败关闭，无速率限制/锁定（FR-160e 复用）。
2. **Given** 设备 B 离线超过 30 天，**When** 重新同步，**Then** 不自动删除任何本地内容（FR-174 复用）。

---

### Edge Cases

- 加入时输入的 locator 格式非法（非预期字符集/长度）：加入前校验，提示格式错误。
- 加入的远程位置存在 bootstrap 但 vaultId 与设备 B 本地残留配置冲突：fail closed（wrong vault 检测复用）。
- 设备 A 在设备 B 加入过程中删除了远程 bootstrap：加入失败且不产生本地配置。
- 设备 B 本地已有大量笔记（>1000）：首次上传分次进行，不阻塞 UI（非主线程加解密）。
- 两端同时"加入"同一 vault：vault 只读加入，无写入竞争（bootstrap 只读）。
- 密码错误与 locator 错误的消息必须可区分（帮助用户排查）。

## Scope *(mandatory)*

### In-Scope

- 同步设置中新增"加入现有 vault"模式（与"创建新 vault"并列），输入 locator + 密码完成加入；加入模式可在配置好仓库后**扫描仓库中现有 vault 并列表选择**（自动发现 locator，无需手动抄录）。
- 加入流程只读获取远程 vault 元数据（bootstrap）并验证，不创建/覆盖任何远程对象。
- 加入成功后复用 001 的同步基础设施立即双向同步；本地已有笔记加密上传。
- 同步配置文件导出（schema v2）与导入（兼容 v1/v2），跨设备传递 locator 与来源设备名。
- 加入/导出/导入的失败关闭（fail closed）语义与可区分错误消息。
- 状态行展示加入后的协议与最近同步状态。

### Out-of-Scope

- 账号系统、设备注册、邀请链接或任何形式的服务器编排。
- 修改 001 的加密格式、同步协议、冲突处理或墓碑语义。
- 多配置同时激活（单配置约束 FR-150/FR-154 不变）。
- 同步配置文件的云端托管（文件传递方式由用户负责；**vault 自动发现/扫描**为本次新增 In-Scope 能力，见 FR-013）。
- 加入后的密码找回或恢复（Constitution VII：不承诺无法提供的密码恢复）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 同步配置弹窗 MUST 提供两种模式：创建新 vault（现状）与加入现有 vault。
- **FR-002**: 加入模式 MUST 要求用户提供 vault locator 与同步密码。
- **FR-003**: 加入流程 MUST 从远程仓库按 locator 获取 vault bootstrap（只读，不创建/覆盖任何远程对象）。
- **FR-004**: 密码错误时 MUST fail closed：不写入本地配置、不修改远程数据，并显示可区分于 locator 错误的明确消息（FR-160d 复用）。
- **FR-005**: locator 不存在时 MUST fail closed：不创建任何远程对象，显示"未找到该 vault"消息。
- **FR-006**: 加入成功后 MUST 复用 001 的同步引擎开始双向同步；本地已有笔记 MUST 加密上传到该 vault。
- **FR-007**: 加入成功后 MUST 将配置持久化为设备本地配置（单配置约束，替换语义沿用 001 FR-154）。
- **FR-008**: 加入成功后 MUST 显示当前协议与最近同步状态（沿用 001 状态行）。
- **FR-009**: 导出同步配置文件 MUST 仅包含协议类型、vault locator、来源设备显示名（`originDeviceName`，可读标识，底层仍以 locator 为固定标识；schema v2，兼容读取 v1 文件）与重删减的 providerConfig（端点/前缀等连接所需信息，不含凭据、密钥或笔记内容），MUST 符合 `sync-profile-export.schema.json`（v2）。
- **FR-010**: 导入同步配置文件 MUST 校验 schema 版本（v1/v2）并 fail closed；导入成功后展示来源设备名，仅需密码即可加入。
- **FR-011**: 加入/导出/导入流程 MUST 保持 FR-160e（错误密码无速率限制）与 FR-174（长期离线协调）语义。
- **FR-012**: 加入过程中 MUST NOT 阻塞本地编辑（网络/加解密不在主线程）。
- **FR-013**: 加入模式 MUST 支持在配置好仓库（协议 + 端点 + 凭据）后扫描仓库中现有 vault 并列表展示（vault 创建时间 + locator），用户可直接选择要加入的 vault，无需手动抄录 locator；扫描为只读操作、无需 vault 密码（bootstrap 元数据可公开枚举，Constitution VII：vaultId/locator 为不透明标识）。

### Key Entities *(include if feature involves data)*

- **Vault Locator**: 标识远程 vault 存储位置的随机不透明标识符（001 已定义，本 feature 将其作为用户可见的加入凭据之一）。
- **Sync Profile**: 可导出的设备无关配置描述（协议类型 + vault locator + 重删减的连接配置 + 来源设备名），用于跨设备传递加入信息；不含任何秘密。
- **Vault Bootstrap**: 远程加密的 vault 元数据对象（001 已定义）；加入流程只读取它。

## Data & Migration Implications

- 本地配置持久化遵循 001 单配置约束：加入成功后以单行配置替换语义持久化（FR-154 复用），本地笔记数据不受影响、不删除。
- 导出契约升级为 schema v2（新增可选 `originDeviceName`）：v1 文件必须可被 v2 校验器读取（向后兼容）；升级不改变已存在的 v1 字段含义。
- 导出文件为单文件 JSON（复用 001 契约，含重删减的 providerConfig），不含凭据、密钥或笔记内容；旧版 v1 文件在导入时仍有效。
- 无本地数据库 schema 变更；vault 元数据与加密格式完全复用 001，无迁移任务。

## Privacy & Permission Implications

- 导出文件边界（Constitution VI/VII）：100% 不含凭据、密钥、笔记内容；仅含协议类型、locator、来源设备显示名与重删减的连接配置（端点/前缀等，非秘密）。
- 日志与诊断（Constitution VI）：不含端点 URL 之外的敏感信息；locator 作为不透明标识可记录（Constitution VII：远程对象名随机/不透明）。
- 加入流程不请求任何新系统权限（网络权限由 001 已建立的同步能力承担）。
- 同步密码只存在于 Keychain（001 既定），导出/导入文件永不包含密码。

## Accessibility Implications

- 新增控件（模式选择、locator 输入、导入/导出按钮）支持键盘操作与 VoiceOver 标签（Constitution X）。
- 错误消息以文字呈现（不只依赖颜色），可被 VoiceOver 读取。

## Performance Expectations

- 加入过程中的网络与加解密操作不得阻塞本地编辑（Constitution XI：主线程外执行）。
- 加入后首次同步 <100 笔记在 1 分钟内双向收敛（SC-002）。
- 本地已有 >1000 笔记时首次上传分次进行，不冻结 UI。

## Failure & Recovery Behavior

- 密码错误 / locator 不存在 / 远程对象损坏 / vault 上下文冲突：一律 fail closed（无本地配置写入、无远程对象创建），并给出可区分的错误消息。
- 加入过程中远程 bootstrap 被删除：加入失败，无本地配置写入，可重试。
- 离线 >30 天设备重新同步：不自动删除本地内容（FR-174 复用）。
- 连续错误密码：无速率限制/锁定（FR-160e 复用），错误后可直接重试。

## Required Tests *(Constitution XII/XIV)*

- 契约测试：schema v1/v2 读兼容、非法版本拒绝、bootstrap 对象名在创建/加入路径一致。
- 安全测试：错误密码、损坏 bootstrap、vault 上下文冲突 → fail closed 且无可观测状态累积。
- 组合测试：加入 → 持久化 → 首次同步双向收敛；本地笔记不删除；远程对象不新建（错误路径）。
- 扫描测试：仓库级 list → 推导 locator → 只读 fetch bootstrap → 枚举 vault（无需密码）；空仓库返回空列表。
- 内容边界测试：导出文件 100% 不含凭据/密钥/笔记内容。
- 导入校验测试：v1/v2 导入成功、损坏/不支持版本 fail closed。
- 回归：001 全部套件 + AppTests + UI 旅程保持绿色。
- 性能验证：<100 笔记首次同步 ≤1 分钟；加入过程无主线程阻塞。
- 无障碍与本地化测试：新控件键盘/VoiceOver 可访问，zh-Hans/en 文案完整。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 第二台设备从打开设置到完成加入（含输入密码）MUST 不超过 3 分钟（对已了解 locator 的用户）。
- **SC-002**: 加入后首次手动同步 MUST 在 1 分钟内完成两端小数据量（<100 笔记）的双向收敛。
- **SC-003**: 错误密码 / 错误 locator 的加入尝试 MUST 在 100% 的测试中不产生任何本地配置写入或远程对象创建。
- **SC-004**: 导出文件 MUST 在 100% 的校验测试中不含凭据、密钥或笔记内容（SC-010 复用）。

## Assumptions

- 复用 001 的全部同步基础设施：同步引擎、加密（Argon2id/AES-GCM/Keychain）、WebDAV/S3 适配器、冲突处理、墓碑与离线协调。
- 用户在加入前已知 vault locator（来自另一台设备的手动告知或导出文件）。
- 同一时间一台设备只维护一个 vault 配置（001 FR-150/FR-154 约束不变）。
- 加入不要求账号系统；locator + 密码即全部凭据（constitution I/III）。
- 本 feature 不修改 001 的加密格式、契约 schema（除 v2 扩展外）或同步协议 —— 只新增"加入"入口与配置传递方式。
- 导出文件为单文件 JSON（复用 001 的 sync-profile-export.schema.json）；发送方式（AirDrop/网盘/即时消息）由用户自行负责。
