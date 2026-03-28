# scripts/learning/

学习层脚本负责把历史工件回填成可复用的 `turn / evidence / preference extraction` 产物，并把学习闭环导出为可迁移的 `learning bundle`。

## 当前脚本

- `build_interaction_turns.py`
  - 回填 `InteractionTurn`
  - 同步补 execution log / benchmark review / repair request 侧 source refs
  - 为缺失关键回链的 turn 写出结构化 `buildDiagnostics`
- `build_next_state_evidence.py`
  - 回填 `NextStateEvidence`
- `extract_preference_signals.py`
  - 读取 `turn.json + evidence.jsonl + teacher note`
  - 固定构造 4 段输入：`actionSummary / nextStateSummary / nextStateRole / teacherNote`
  - 用 `3-vote` 提炼结构化偏好 JSON
  - 做 schema 校验、hint 句数校验、可执行性校验、低置信度降级
  - 输出 `accepted` 或 `needs_review` 报告
- `migrate_semantic_actions.py`
  - 创建 / 回滚 `semantic_actions` SQLite schema
  - 从 `data/learning/turns/**` 回填 `semantic_actions / action_targets / action_assertions / action_execution_logs`
  - 优先复用 `InteractionTurn.semanticTargetSetRef` 与关联 skill bundle 的 `actionType / locatorStrategyOrder / coordinate legacy ref`
  - 对仅剩 `coordinateFallback / unknown` 的历史步骤，回读 `rawEventLog + taskChunk` 并基于 `sourceEventIds` 自动恢复 semantic selector / args / assertions
  - 对无法可靠恢复的步骤写 `context.historicalConversion.reasonCode`，并在 CLI 摘要输出 `historicalAutoConversionRate / historicalConversionReasonCounts`
- `build_semantic_actions.py`
  - 执行 `SEM-101 Action Builder v1` + `SEM-102` 选择器抽取 + `SEM-103` 拖动动作语义化
  - 读取 `data/task-chunks/** + data/raw-events/**`，按“时间邻近 + 上下文一致”聚合事件窗口
  - 识别并写入 `switch_app / focus_window / click / type / shortcut / drag` 到 `semantic_actions`
  - 为 click/type/shortcut/drag 动作抽取 `automation_id -> role + name/text -> role + ancestry_path -> bounds_norm -> absolute coordinate` selector 链
  - `drag` 动作会额外写出 `sourceSelector / targetSelector / dragPath / intent`，并绑定 source/target app context
  - 把 `app/window/url` 绑定、fallback selector chain 与 candidate count 一并写入 action context / targets
  - 输出 `semanticizedEventRatio / conflictDiagnosticCount / manualReviewRequiredCount` 摘要
- `semantic_selector_extractor.py`
  - 执行 `SEM-102` Accessibility 优先选择器抽取
  - 负责稳定 selector 优先级、同会话 fallback 链去重，以及 `urlHost / boundsNorm / ancestryPath` 等补充字段
- `export_learning_bundle.py`
  - 导出 `turns / evidence / signals / rules / profiles / audit`
  - 生成 `manifest.json` 与 `verification.json`
  - 支持按 `session / task / turn` 过滤，同时自动补齐依赖闭环
- `verify_learning_bundle.py`
  - 校验 bundle manifest、payload checksum 与对象引用
  - 支持恢复前 dry-run 预览
  - 支持恢复到新的 workspace root，并可选 `--overwrite`

## LLM 提炼器 v1

默认行为：

- 默认 `3` 票，多数一致才接受
- `hint` 必须是 `1-3` 句
- `hint` 必须是“怎么改”的可执行建议
- `confidence < 0.75` 默认进入 `needs_review`
- 严格记录 `provider / model / promptVersion / inputHash`

输出落点：

- `data/preferences/extractions/{date}/{sessionId}/{turnId}--{evidenceId}.json`
- `data/preferences/needs-review/{date}/{sessionId}/{turnId}--{evidenceId}.json`

示例：

```bash
python3 scripts/learning/extract_preference_signals.py \
  --turn data/learning/turns/2026-03-10/session-gui-023212a2-teaching-20260310-202613/turn-teaching-taskProgression-task-session-gui-023212a2-teaching-20260310-202613-001-step-001.json \
  --evidence data/learning/evidence/2026-03-10/session-gui-023212a2-teaching-20260310-202613/turn-teaching-taskProgression-task-session-gui-023212a2-teaching-20260310-202613-001-step-001.jsonl \
  --teacher-note "先确认当前窗口和目标按钮标题，再执行点击。" \
  --provider heuristic \
  --output-root data/preferences
```

## Learning Bundle v0

导出示例：

```bash
python3 scripts/learning/export_learning_bundle.py \
  --learning-root data/learning \
  --preferences-root data/preferences \
  --output /tmp/openstaff-learning-bundle \
  --session-id session-001 \
  --json
```

校验示例：

```bash
python3 scripts/learning/verify_learning_bundle.py \
  --bundle /tmp/openstaff-learning-bundle \
  --json
```

恢复前 dry-run：

```bash
python3 scripts/learning/verify_learning_bundle.py \
  --bundle /tmp/openstaff-learning-bundle \
  --restore-workspace-root /tmp/openstaff-restored \
  --json
```

执行恢复：

```bash
python3 scripts/learning/verify_learning_bundle.py \
  --bundle /tmp/openstaff-learning-bundle \
  --restore-workspace-root /tmp/openstaff-restored \
  --apply \
  --json
```

更多字段与结构约定见：

- `docs/learning-bundle-spec.md`
- `docs/semantic-action-store-v0.md`

## Semantic Actions SQLite

从 raw event / task chunk 直接构建动作序列：

```bash
python3 scripts/learning/build_semantic_actions.py \
  --db-path data/semantic-actions/semantic-actions.sqlite \
  --workspace-root . \
  --task-chunks-root data/task-chunks \
  --raw-events-root data/raw-events \
  --clean \
  --json
```

或直接用 Makefile：

```bash
make semantic-actions-build ARGS="--clean --json"
```

建库并回填示例：

```bash
python3 scripts/learning/migrate_semantic_actions.py \
  --db-path data/semantic-actions/semantic-actions.sqlite \
  --workspace-root . \
  --turns-root data/learning/turns \
  --clean \
  --json
```

输出摘要除 `writtenActions / manualReviewRequiredCount` 外，还会附带：

- `historicalCoordinateCandidateCount`
- `historicalAutoConvertedCount`
- `historicalAutoConversionRate`
- `historicalConversionReasonCounts`

只做 schema rollback：

```bash
python3 scripts/learning/migrate_semantic_actions.py \
  --db-path data/semantic-actions/semantic-actions.sqlite \
  --direction down \
  --json
```
