# ADR-0024 Semantic-Only Execution Freeze

- Status: Accepted
- Date: 2026-03-26
- Owners: OpenStaff Core Team

## Context

OpenStaff 已经在 capture、knowledge、replay verify 和 skill preflight 中引入了 `SemanticTarget`，但 OpenClaw gateway 入口仍然存在两个不一致点：

- legacy skill 仍可能通过 `target=coordinate:x,y` 或仅剩 `coordinateFallback` 的 click step 进入执行链路。
- gateway 作为独立入口时，调用方未必会显式声明“本次执行只接受语义 locator”。

这与 `docs/semantic-action-capture-migration-backlog-2026-03.md` 中 `SEM-001` 的冻结原则不一致，也会让后续真实执行器接入时重新暴露误点风险。

## Decision

### 1. 执行入口冻结为 `semantic_only=true`

- `OpenClawExecutionRequest.semanticOnly` 默认 `true`。
- `SEM-501` 起 gateway 会无条件按 semantic-only 执行，不再依赖调用方显式透传 `--semantic-only`。
- legacy `--semantic-only` flag 继续接受，但只作为兼容性 no-op，不再作为功能开关。

### 2. 坐标仅保留为诊断与 provenance 字段

- `coordinate`
- `coordinateFallback`
- instruction 中遗留的 `coordinate:x,y`

这些字段仍允许出现在 capture、knowledge、skill provenance 和审计日志里，但不能再作为执行决策输入。

### 3. 仅坐标 click step 视为不可执行 skill

当 click step 满足以下任一条件时，skill preflight 必须失败，而不是退化为“老师确认后可执行”：

- 只有 legacy `target=coordinate:x,y`
- provenance 缺失语义 locator，只剩 `coordinateFallback`

统一返回：

- preflight issue code: `SPF-COORDINATE-EXECUTION-DISABLED`
- runner / gateway error code: `OCW-COORDINATE-EXECUTION-DISABLED`

### 4. gateway 不得绕过 runner 安全结论

gateway 必须重复执行与 runner 一致的 semantic-only preflight，并透传：

- `--safety-rules`
- `--teacher-confirmed`

避免出现“runner 判定通过、gateway 因配置缺失重新走旧路径”的分叉。

## Consequences

### Positive

- 坐标从执行链路中被彻底移除，只保留为观测/审计事实。
- legacy 调用方会得到稳定错误码，不再发生“误以为还能人工确认后继续跑”的模糊行为。
- 为后续接入真实语义执行器提供了统一、可测试的入口契约。

### Negative

- 历史上只有坐标的 click skill 会立即失效。
- direct gateway 不再有“显式开关”可回退，问题场景只能通过版本回滚或人工确认降级处理。

## Follow-up

- `SEM-002`：把新的 semantic action DSL / storage 模型落地到独立表结构。
- `SEM-003`：在 CI 中阻止新增 coordinate execution 调用重新流入主干。
