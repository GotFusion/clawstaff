# ADR-0019 Preference Drift Monitoring

## Status

Accepted

## Context

Phase 11 已经有：

- `PreferenceRule`
- `PreferenceProfileSnapshot`
- `PreferenceAuditLogStore`
- `PolicyAssemblyDecisionStore`

但在这些能力都落地后，系统仍缺一个关键闭环：

- 规则生效后，怎么判断它是不是已经开始过时？

如果没有漂移监控，偏好系统会出现 3 个问题：

1. 旧规则会一直停留在 active profile 里，即使老师早就不这么做了。
2. 高风险规则即使和当前行为不一致，也不会主动暴露出来。
3. 回滚、撤销和治理虽然存在，但缺少“何时该触发复核”的前置信号。

## Decision

采用 `PreferenceDriftMonitor` 作为 Phase 11 的第一版漂移检测器。

它遵守 4 条原则：

1. 只做检测与解释，不直接自动改写规则。
2. 只依赖已存在的文件事实源：`rules / profiles / audit / assembly`。
3. 优先给出规则级 finding，而不是抽象总分。
4. 数据不足时明确降级，不凭空推断。

## First Version Rules

v0 固定落 5 类 finding：

1. `longTimeNoHit`
2. `overrideRateElevated`
3. `teacherRejectedRepeatedly`
4. `stylePreferenceChanged`
5. `highRiskBehaviorMismatch`

其中 roadmap 最小要求的 3 条规则全部覆盖：

- `30` 天未命中
- 最近 `10` 次相关任务里 override 超过 `50%`
- 最近 `3` 次明确被老师驳回

## Evidence Model

每条 finding 必须带：

- `ruleId`
- `summary`
- `rationale`
- `metrics`
- `evidence[]`

`evidence[]` 第一版允许来自：

- `policyAssemblyDecision`
- `auditEntry`
- `rule`

这样后续 GUI 可以直接解释：

- 为什么说这条规则 stale
- 是没命中、被 override，还是被老师显式驳回
- 对应证据落在哪个 decision / audit / rule 文件上

## Why Not Auto-Roll Back

当前不让 drift detector 自动回滚，原因是：

1. `stale` 不等于错误，有可能只是最近没遇到相关任务。
2. `override` 可能来自 scope 更具体的规则，不一定意味着原规则应删除。
3. 高风险规则更需要人工复核，而不是静默撤销。

因此 v0 只输出“建议复核”的 finding；真正的撤销仍走：

- `PreferenceRollbackService`
- `OpenStaffPreferenceProfileCLI --rollback-*`

## Consequences

正向结果：

- 偏好治理第一次具备“何时需要复核”的前置感知。
- 审计、回滚、装配日志开始形成闭环，而不只是独立能力。
- CLI / GUI 后续都能统一消费同一种 drift report。

代价与限制：

- 若没有开启 `PolicyAssemblyDecisionStore`，usage-based drift 只能降级。
- 第一版仍无法直接读取 `teacher.feedback.v2` 的原始快评，需要通过 audit 语义近似。
- style drift 目前还是规则级 heuristic，不是行为序列级模型。

## Follow-Up

- 把 drift report 接入 GUI 审阅台与治理面板。
- 允许对 finding 进行老师确认、忽略、转回滚建议。
- 将 `teacher.feedback.v2` 与 `NextStateEvidence` 接入，缩小“teacher reject”近似判断误差。
