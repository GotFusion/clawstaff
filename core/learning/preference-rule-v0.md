# PreferenceRule v0

`PreferenceRule` 是从重复出现、可追溯的 `PreferenceSignal` 晋升出来的长期偏好记忆。

## 目标

- 把一次性 signal 和长期稳定规则区分开。
- 保留 `signalId -> evidenceIds -> turnId/sessionId/taskId` 的完整回链。
- 为后续 `PreferenceRulePromoter`、冲突解决器和 profile 聚合提供统一事实源。

## 最小字段

- `ruleId`
- `sourceSignalIds`
- `scope`
- `type`
- `polarity`
- `statement`
- `hint`
- `proposedAction`
- `evidence`
- `riskLevel`
- `activationStatus`
- `teacherConfirmed`
- `supersededByRuleId`
- `lifecycleReason`
- `createdAt`
- `updatedAt`

## 生命周期

- `active`：当前可被 `PreferenceProfile` 聚合。
- `superseded`：已被新规则替代，但必须保留以支持审计、比较和回滚。
- `revoked`：老师或治理策略显式撤销，不再参与默认查询。

## 存储

- 事实文件：`data/preferences/rules/{ruleId}.json`
- 查询索引：`data/preferences/rules/index/{global,by-app,by-task-family,by-skill-family}/*.json`
- 审计日志：`data/preferences/audit/{date}.jsonl`

## v0 约束

- 每条规则至少回链 `1` 条 `sourceSignalId` 和 `1` 条 `PreferenceRuleEvidence`。
- `PreferenceRuleEvidence` 只存轻量结构化引用，不复制上游 evidence 正文。
- `windowPattern` 作用域先保留扩展位，默认查询索引只保障 `global / app / taskFamily / skillFamily`。
