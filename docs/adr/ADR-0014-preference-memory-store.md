# ADR-0014 Preference Memory Store

## Status

Accepted

## Context

Phase 11 进入偏好记忆层后，`PreferenceSignal` 已经不是最终产物。系统还需要：

- 把候选 signal 升级成长期 `PreferenceRule`
- 把当前生效规则聚合成 `PreferenceProfile`
- 保留 superseded / revoked 历史以支持审计、回滚和漂移分析
- 在 assist / skill / repair / review 装配时，按 `app / task family / skill family` 快速查询相关规则

如果继续直接遍历 review、execution 或 signal 原工件：

- 查询路径会越来越慢
- 回滚会缺少统一审计入口
- 下游模块很难解释“这次为什么套用了这些偏好”

## Decision

采用文件事实源的 `PreferenceMemoryStore`。

### 目录

- `data/preferences/signals/{date}/{sessionId}/{turnId}.json`
- `data/preferences/rules/{ruleId}.json`
- `data/preferences/profiles/{profileVersion}.json`
- `data/preferences/audit/{date}.jsonl`

### 辅助索引

- `data/preferences/signals/index/by-id/{signalId}.json`
- `data/preferences/rules/index/all/__all__.json`
- `data/preferences/rules/index/global/global.json`
- `data/preferences/rules/index/by-app/{appBundleId}.json`
- `data/preferences/rules/index/by-task-family/{taskFamily}.json`
- `data/preferences/rules/index/by-skill-family/{skillFamily}.json`
- `data/preferences/profiles/latest.json`

### 生命周期

- `PreferenceRule` 固定支持 `active / superseded / revoked`
- 状态变更一律保留在原规则文件上，同时写入 audit JSONL
- `PreferenceProfileSnapshot` 只保存聚合快照，不覆盖历史版本

## Consequences

正向影响：

- 规则查询不再依赖遍历全部 review 工件
- `signal -> rule -> profile -> audit` 路径可完整回溯
- 删除或撤销规则后，可以从 signal 重新生成 profile

代价：

- 需要维护轻量索引和 latest pointer
- 规则文件与索引文件之间会有额外一致性维护成本
- 后续 promoter / profile builder 需要遵守当前目录与生命周期约定

## Follow-up

- `PreferenceRulePromoter` 直接复用 `PreferenceMemoryStore` 的 rules / audit 落点。
- `PreferenceProfileBuilder` 统一输出 `PreferenceProfileSnapshot`，不再自己定义旁路存储。
- Phase 11.6 的 rollback / drift monitoring 继续沿用本 ADR 的审计与索引结构。
