# Requirements Checklist: Join Existing Vault

**Purpose**: Coverage check for the 002 join-existing-vault spec — every FR, user-story acceptance scenario, and security/privacy boundary has a testable task.
**Created**: 2026-08-08
**Feature**: [spec.md](./spec.md)

## Functional Coverage

- [X] CHK001 FR-001 — 配置弹窗提供"创建新 vault / 加入现有 vault"两种模式；加入模式字段完整（协议配置 + locator + 密码）
- [X] CHK002 FR-002 — 加入模式要求 vault locator + 同步密码输入
- [X] CHK003 FR-003 — 加入流程只读获取远程 bootstrap（按 locator 定位），不创建/覆盖远程对象
- [X] CHK004 FR-004 — 错误密码 fail closed：不写本地配置、不改远程数据、消息可区分于 locator 错误
- [X] CHK005 FR-005 — locator 不存在 fail closed：不创建远程对象、显示"未找到该 vault"
- [X] CHK006 FR-006 — 加入成功后立即同步（用户决策），本地笔记自动加密上传，双向同步复用 SyncEngine
- [X] CHK007 FR-007 — 配置持久化：单配置替换语义（001 FR-154），本地笔记不被删除
- [X] CHK008 FR-008 — 加入后状态行显示协议 + 最近同步时间
- [X] CHK009 FR-009 — 导出文件含协议/locator/来源设备显示名（schema v2），不含凭据/密钥/笔记内容
- [X] CHK010 FR-010 — 导入校验 v1/v2，展示来源设备名，仅需密码；损坏/不支持版本 fail closed
- [X] CHK011 FR-011 — 加入/导出/导入保持 FR-160e（错误密码无锁定）与 FR-174（长期离线协调）语义
- [X] CHK012 FR-012 — 加入过程不阻塞本地编辑（网络/加解密不在主线程）

## User Story Coverage

- [X] CHK013 US1/AC1 — 设备 B 正确 locator + 密码加入成功，两端同一 vault、状态一致
- [X] CHK014 US1/AC2 — 错误密码 → 明确错误，无本地/远程写入
- [X] CHK015 US1/AC3 — 不存在 locator → 明确错误，无远程对象创建
- [X] CHK016 US1/AC4 — 本地已有笔记加入后自动加密上传，设备 A 可见
- [X] CHK017 US1/AC5 — 两端离线编辑冲突 → 冲突副本，不静默覆盖
- [X] CHK018 US1/AC6 — 已有本地 vault 配置时加入 → 替换语义，本地笔记保留、旧远程不删
- [X] CHK019 US2/AC1 — 导出文件含协议/locator/设备名，无秘密，符合 schema v2
- [X] CHK020 US2/AC2 — 导入自动填充 + 仅需密码 + 显示设备名
- [X] CHK021 US2/AC3 — 损坏/不支持版本导入 fail closed，不写本地配置
- [X] CHK022 US3/AC1 — 连续错误密码无速率限制/锁定（FR-160e 复用验证）
- [X] CHK023 US3/AC2 — 离线 >30 天设备重新同步不自动删除本地内容（FR-174 复用验证）

## Edge Cases

- [X] CHK024 locator 格式非法（字符集/长度）→ 加入前校验并提示
- [X] CHK025 远程存在 bootstrap 但 vaultId 与本地残留配置冲突 → fail closed（wrong vault）
- [X] CHK026 设备 A 在加入过程中删除远程 bootstrap → 加入失败，无本地配置写入
- [X] CHK027 两端同时加入同一 vault → 只读加入，无写入竞争
- [X] CHK028 密码错误与 locator 错误消息可区分

## Security & Privacy

- [X] CHK029 导出文件 100% 不含凭据/密钥/笔记内容（SC-004，内容边界测试）
- [X] CHK030 加入失败路径 100% 不产生本地配置写入或远程对象创建（SC-003）
- [X] CHK031 导出/导入文件名与内容遵循 FR-191 净化边界（无路径/无主机名泄露到诊断）
- [X] CHK032 日志与诊断不含 locator 之外的敏感信息（locator 为不透明标识，可记录）

## Success Criteria

- [X] CHK033 SC-001 — 第二台设备从打开设置到加入完成 ≤3 分钟（流程可用性）
- [X] CHK034 SC-002 — 首次同步 <100 笔记 1 分钟内双向收敛（性能验证）
- [X] CHK035 SC-003 — 错误密码/错误 locator 100% 测试无本地/远程写入
- [X] CHK036 SC-004 — 导出文件 100% 校验测试不含秘密

## Notes

- 复用 001 全部同步/加密/冲突/墓碑基础设施；本 feature 零新依赖。
- 契约变更：sync-profile-export.schema.json v2（可选 originDeviceName，v1 读兼容）。
- 测试 FIRST（Constitution XII）；加入路径用 001 InMemorySyncProvider 组合测试模式。
