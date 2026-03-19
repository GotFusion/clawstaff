# ADR-0023 Learning Hooks And Gateway Contracts

## Status

Accepted

## Context

Phase 11 到当前为止，learning 资产已经具备：

- `turn / evidence / signal / rule / profile / audit` 文件事实源
- `PolicyAssemblyDecision` 装配解释日志
- learning bundle 导出 / 校验 / 恢复闭环

但如果没有一层稳定对外边界，外部插件或 worker 仍会面临两个问题：

1. 只能直接读 `PreferenceMemoryStore`、`PolicyAssemblyDecisionStore` 或 `data/**` 私有目录。
2. 一旦内部索引、脚本参数或目录布局调整，外部集成就会一起断裂。

## Decision

采用“公开 contract + hook 事件 + gateway 方法”的 v0 集成边界。

### v0 hook 事件

固定四类：

- `learning.turn.created`
- `learning.signal.extracted`
- `preference.rule.promoted`
- `preference.profile.updated`

这些事件统一通过 `LearningHookEventMetadata + LearningHookEnvelope<Payload>` 表达。

### v0 gateway 方法

固定三类：

- `preferences.listRules`
- `preferences.listAssemblyDecisions`
- `preferences.exportBundle`

其中：

- `listRules` 返回规则集合与可选最新 profile snapshot。
- `listAssemblyDecisions` 返回装配解释结果与可选最新 profile snapshot。
- `exportBundle` 返回 bundle 导出结果、counts、indexes 与 verification issues。

### 边界约束

外部集成只允许依赖：

- `core/contracts/LearningIntegrationContracts.swift`
- 其引用到的其它公开 contract
- `LearningGatewayServing` 实现

外部集成不允许直接依赖：

- `PreferenceMemoryStore`
- `PolicyAssemblyDecisionStore`
- `PreferenceRuleQuery`
- `PolicyAssemblyDecisionQuery`
- bundle 脚本内部 helper
- `data/learning/**` / `data/preferences/**` 私有目录布局

## Why Not Let Plugins Read Stores Directly

不采用“插件直接读内部 store / 目录”的原因：

1. 当前存储层的首要职责是本地事实源与内部索引，不是对外稳定 API。
2. `PreferenceRuleQuery`、bundle 脚本参数拼装等对象偏实现细节，变化频率会高于公开 contract。
3. 将查询与导出统一挂到 gateway 后，可以在不改外部调用方的前提下替换内部索引、目录布局甚至实现语言。

## Consequences

正向结果：

- learning 层第一次具备了稳定的“事件 + 查询 / 导出”外部边界。
- worker / plugin 可以只依赖公开 contract 消费学习结果。
- 后续即使 `PreferenceMemoryStore` 或 bundle 脚本重构，也能通过 gateway 保持兼容。

代价与限制：

- v0 仍是文件系统 gateway，不包含网络 transport、权限认证与分页协议。
- hook 事件目前只固化了最核心 4 类，旁路治理事件留待后续扩展。
- `preferences.exportBundle` 目前仍复用 Python 脚本，运行环境要求可执行 `python3`。

## Follow-Up

- 视需要补充 rollback / drift / quick feedback 相关 hook 事件。
- 若外部消费量增大，再评估分页、游标与 RPC transport。
- 当 OpenClaw 或其它 worker 要长期接入时，优先扩展 gateway 方法，不让其回退到直接读内部目录。
