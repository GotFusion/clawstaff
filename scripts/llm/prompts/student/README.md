# Student Planner Prompts

该目录用于承接 student planner 的模型化提示词约束。

当前仓库默认仍以 `rule-v0` / `preference-aware-rule-v1` 规则规划为主，但从 Phase 11.4.5 开始，student planner 已经具备以下可稳定外化到 prompt 的约束：

- `executionStyle`
  - `conservative`
  - `assertive`
- `failureRecoveryPreference`
  - `repairBeforeReteach`
  - `reteachBeforeRepair`
- `appliedRuleIds`
- `PreferenceProfile.plannerPreferences` 中的规则摘要

使用原则：
- prompt 只在 feature flag + benchmark-safe attestation 都满足时参与 student planner。
- prompt 需要保持“先安全、再效率”的优先级，不可绕过现有 `SafetyPolicyEvaluator`、teacher confirmation 或紧急停止链路。
- prompt 输出必须能回写到 `StudentExecutionPlan.preferenceDecision` 的同构字段，便于 rule planner 与 model planner 共享审阅面板解释。
