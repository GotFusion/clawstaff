# Semantic Action Store v0

更新时间：2026-03-27

## 1. 目标

`semantic action store` 是 `SEM-002` 的最小落地结果：先把语义动作事实层独立成可迁移、可查询、可回填的 SQLite 资产，而不是继续把动作语义散落在 `turn / skill / execution log` 多份文件里。

本版优先解决：

1. 给后续 `SEM-101/103/201/203` 提供统一表结构。
2. 让历史 `InteractionTurn` 能回填成结构化语义动作记录。
3. 在保持现有文件型学习资产不变的前提下，引入可前后滚动的 schema migration。

## 2. 路径与入口

- 默认库路径：`data/semantic-actions/semantic-actions.sqlite`
- migration SQL：
  - `scripts/learning/migrations/semantic_actions/0001_semantic_actions.up.sql`
  - `scripts/learning/migrations/semantic_actions/0001_semantic_actions.down.sql`
- repository / DAO：`scripts/learning/semantic_action_store.py`
- SEM-101/103 builder：`scripts/learning/semantic_action_builder.py`
- SEM-102 selector extractor：`scripts/learning/semantic_selector_extractor.py`
- builder CLI：`scripts/learning/build_semantic_actions.py`
- 回填脚本：`scripts/learning/migrate_semantic_actions.py`
- SEM-201 executor：`OpenStaffReplayVerifyCLI --semantic-action-db <db> --action-id <id> [--dry-run]`

## 3. 表结构

### 3.1 `semantic_actions`

一条 `InteractionTurn` 最终回填成一条主动作记录，核心字段：

- `action_id`
- `session_id`
- `task_id`
- `turn_id`
- `trace_id`
- `step_id`
- `step_index`
- `action_type`
- `selector_json`
- `args_json`
- `context_json`
- `confidence`
- `source_event_ids`
- `source_frame_ids`
- `source_path`
- `preferred_locator_type`
- `manual_review_required`
- `legacy_coordinate_json`
- `created_at`
- `updated_at`

说明：

- `selector_json / args_json / context_json` 先保持 JSON 扩展，避免过早冻结 DSL。
- `source_event_ids / source_frame_ids` 用 JSON 数组文本保存，方便审计和后续导出。
- `legacy_coordinate_json` 只保留为诊断来源，不作为执行依据。

### 3.2 `action_targets`

保存动作的多个 selector 候选：

- `target_role`：`primary / candidate / fallback`
- `locator_type`
- `selector_json`
- `context_json`
- `confidence`
- `is_preferred`

### 3.3 `action_assertions`

保存动作执行前后的结构化断言，v0 默认回填：

- `requiredFrontmostApp`
- `windowTitlePattern`
- `selectorResolvable`

### 3.4 `action_execution_logs`

保存动作级执行日志回链：

- `status`
- `error_code`
- `selector_hit_path_json`
- `result_json`
- `duration_ms`
- `execution_log_path`
- `execution_result_path`
- `review_id`
- `executed_at`

`SEM-201` 之后，这张表已由 `OpenStaffReplayVerifyCLI` 的 semantic executor 直接写入，默认记录：

- `status`
- `selector_hit_path_json`
- `duration_ms`
- `result_json.summary / matchedLocatorType / dryRun`

## 4. 回填来源优先级

`migrate_semantic_actions.py` 的回填顺序：

1. 读取 `data/learning/turns/**/*.json`
2. 优先使用 `InteractionTurn.semanticTargetSetRef`
3. 如 turn 带 `sourcePath / skillBundle`，再反查 skill bundle：
   - `provenance.stepMappings[*]`
   - `mappedOutput.executionPlan.steps[*]`
4. 组装：
   - 主 selector
   - 候选 targets
   - 默认 assertions
   - execution logs

动作类型映射当前遵循：

- `input -> type`
- `openApp / switchApp -> switch_app`
- `focusWindow -> focus_window`
- `drag* -> drag`

其中 `SEM-103` 生成的 `drag` 记录额外约定：

- `selector_json` 保存 source selector
- `args_json.sourceSelector / targetSelector` 保存元素对元素拖动的双目标
- `args_json.dragPath` 保存拖动轨迹摘要（起点、终点、中间点数量）
- `args_json.intent` 当前支持 `window_move / list_reorder / drag_and_drop`
- `action_targets` 会同时记录 source/target 的 primary/candidate/fallback selector

若缺少显式 `actionType`，则退回 instruction 关键字推断；再不行则 `guiAction -> click`。

## 5. 人工审核标记

以下情况会自动写 `manual_review_required = true`：

- 只有 `coordinateFallback`
- selector 缺失，只能落 `unknown / context-only` 选择器
- turn 风险等级为 `high / critical`

这保证迁移期虽然能留住历史动作资产，但不会把低质量 selector 误当成可自动执行结果。

## 6. 当前边界

v0 暂不做：

- 把 `semantic_actions` 并入 `learning bundle`
- GUI 主执行链默认切到 `semantic_actions` store
- drag intent 的跨 App/跨控件细分策略学习
- 跨设备 locator repair

这些属于后续 `SEM-202 / 203 / 301` 的接续工作。
