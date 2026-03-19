# ADR-0015 Preference Rule Promotion and Governance

## Status

Accepted

## Context

`PreferenceSignal` 只是候选学习结果，不能直接当作长期规则使用。Phase 11 进入偏好记忆层后，如果缺少默认晋升阈值和冲突治理：

- 单次偶发反馈会被过早固化为长期规则
- 高风险偏好可能绕过老师确认直接生效
- 同一作用域下的多条规则会缺少统一、可解释的覆盖顺序

## Decision

采用“阈值晋升 + 风险分级 + 可解释冲突排序”的 v0 默认策略。

### 默认晋升目标

- `global`
- `app`
- `taskFamily`

`skillFamily` 与更细粒度作用域先保留为扩展位，不作为 v0 默认自动晋升目标。

### 默认晋升阈值

- `low`
  - 至少 `3` 条 qualifying signals
  - 至少跨 `2` 个 session
  - 平均置信度 `>= 0.75`
- `medium`
  - 至少 `4` 条 qualifying signals
  - 至少跨 `3` 个 session
  - 最新一条同组 signal 不能是显式驳回
- `high`
  - 至少 `1` 条 qualifying signal
  - 必须 `teacherConfirmed = true`
  - 最新一条同组 signal 不能是显式驳回
- `critical`
  - 必须 `teacherConfirmed = true`
  - 默认不自动晋升，只保留 candidate

### qualifying / rejection 约定

- `candidate` 与 `confirmed` 计入晋升阈值。
- `rejected` 不计入阈值，但可阻止 `medium / high / critical` 自动晋升。
- `superseded` 不再计入新的晋升计算。

### 冲突排序

同一组候选规则冲突时，默认优先级固定为：

1. `active` 规则优先于 inactive 历史
2. 更具体的 scope 优先于更宽 scope
3. 更近的老师明确确认优先
4. 更低风险优先
5. 更近的更新时间优先
6. `ruleId` 作为稳定兜底 tie-break

冲突结果必须能输出结构化 explanation，说明“为什么 A 覆盖 B”。

## Consequences

正向影响：

- 单次噪声反馈不会直接成为长期偏好
- 高风险规则不会绕过老师确认
- `PreferenceMemoryStore`、后续 `PreferenceProfileBuilder` 与 GUI 展示可以共享同一套规则排序

代价：

- `critical` 风险默认保持 candidate，会延后部分自动化收益
- 需要维护作用域白名单、阈值和 rejection 语义的一致性

## Follow-up

- `PreferenceRulePromoter` 负责把阈值和 teacher confirmation 门槛固化为可运行逻辑。
- `PreferenceConflictResolver` 负责输出排序结果与 override explanation。
- `config/preference-governance.yaml` 作为正式治理配置；`config/preference-promotion.example.yaml` 保留为历史示例。
