# DirectiveHint Template v0

`DirectiveHint` 是把带 directive payload 的 `PreferenceSignal` 扇出成下游模块可直接消费的最小对象。

## 目标

- 只在 signal 已经给出明确 hindsight 时生成。
- 保留原始 `hint + proposedAction + scope`，不再让下游模块重复解析 signal。
- 第一版只服务 4 个消费者：
  - `assist_rerank`
  - `skill_mapper`
  - `repair_planner`
  - `review_suggestion`

## 对象字段

- `hintId`：稳定 hint 主键，格式 `directive-hint-{consumer}-{signalId}`
- `signalId`：回链源 `PreferenceSignal`
- `consumer`：下游消费者
- `signalType`：源 signal 类型
- `scope`：沿用 signal scope
- `hint`：1-3 句、可执行、只描述怎么改
- `proposedAction`：供下游做机器路由
- `confidence`
- `evidenceIds`
- `createdAt`

## 消费约定

### `assist_rerank`

- 只改排序，不改基础检索。
- 当候选命中同一 `scope` 时，优先提升更符合 `hint` 的候选。
- 对 `risk / procedure / style` 类 hint 默认更敏感；`locator` 只在候选显式包含 GUI 执行方案时参考。

### `skill_mapper`

- 把 `hint` 作为 prompt / template 约束直接注入。
- `proposedAction` 可作为结构化分流键，例如：
  - `updateSkillLocator`
  - `relocalize`
  - `require_teacher_confirmation`

### `repair_planner`

- 只消费“会改变 repair 优先级”的 hint。
- 第一版重点看：
  - `locator`
  - `repair`
  - 带 `replay / reteach / repair / locator` action token 的 `procedure` 或 `risk`

### `review_suggestion`

- 把 `hint` 作为审阅建议的可解释文案来源。
- 不自动替老师做决定，只用于排序和预填说明。

## v0 映射规则

- `procedure` -> `assist_rerank`, `skill_mapper`, `review_suggestion`
- `locator` -> `skill_mapper`, `repair_planner`, `review_suggestion`
- `style` -> `assist_rerank`, `skill_mapper`, `review_suggestion`
- `repair` -> `repair_planner`, `review_suggestion`
- `risk` -> `assist_rerank`, `skill_mapper`, `review_suggestion`
- 若 `proposedAction` 含有 `locator / replay / reteach / repair / confirmation` 等 token，可额外补入对应消费者。

## 非目标

- 不在这里做 signal 合并、晋升或冲突消解。
- 不复制 evidence 正文，只保留 `signalId / evidenceIds` 回链。
