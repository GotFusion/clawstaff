# InteractionTurn v0

## 目标

`InteractionTurn` 是学习层的最小事实单元，用来回答两件事：

1. 这一主线动作到底是什么。
2. 它后续关联到了哪些 skill、执行结果和老师反馈。

Phase 11 v0 先覆盖：

- `taskProgression`
- `skillExecution`
- `repair`

其中 `taskProgression` 主要来自 teaching capture，`skillExecution` 主要来自 assist / student / benchmark runtime，`repair` 预留给后续 repair request 与 drift 修复闭环。

## 核心字段

- `turnId / traceId / sessionId / taskId / stepId`
- `mode`：`teaching / assist / student`
- `turnKind`：`taskProgression / skillExecution / repair`
- `actionKind`：第一版固定 `nativeAction / guiAction`
- `learningState`：`captured / linked / reviewed / excluded`
- `privacyTags`：开放字符串列表，用于记录 `excluded-app`、`sensitive-muted`、`capture-redacted` 等上下文
- `observationRef`：回链 raw event log、task chunk、窗口上下文，以及后续补上的 screenshot / AX / OCR refs
- `semanticTargetSetRef`：GUI turn 的 locator 候选摘要与来源路径
- `execution / review / sourceRefs`：把 skill、执行日志、benchmark review、teacher feedback 串起来

## ObservationBundle 过渡策略

当前仓库还没有正式的 `ObservationBundle` 文件层，因此 `InteractionTurn.observationRef` 暂时接受等价 sidecar：

- `source-record.json`
- `data/raw-events/**/*.jsonl`
- `data/task-chunks/**/*.json`
- `ContextSnapshot` / `windowTitle` / `windowSignature`
- step 级 `sourceEventIds`

这样可以先满足 Phase 11 的“学习工件可审计、可回填”要求，同时不给后续正式 `ObservationBundle` 定稿制造兼容负担。

## 回填策略

`scripts/learning/build_interaction_turns.py` 目前分两路回填：

1. `benchmark generated case -> teaching turn + student skillExecution turn`
2. `student log/report/teacher feedback -> student skillExecution turn`

说明：

- benchmark case 让 turn 能一次性回链 capture、knowledge、skill、execution、benchmark review。
- student log/report/teacher feedback 让 turn 能承接真实老师审阅样本。
- assist 的真实历史日志在当前仓库中尚未冻结，因此 v0 先把 builder 与 schema 设计成可兼容 assist，等真实 assist log 样本入库后直接补跑脚本即可。

## 风险分级

builder 默认按以下规则估算 `riskLevel`：

- `tooDangerous` -> `critical`
- 命中排除/敏感/脱敏 privacy tag -> `high`
- `coordinateFallback` 或执行错误码存在 -> `high`
- `nativeAction` -> `medium`
- 其余 -> `low`

## 兼容性

- schemaVersion 固定为 `openstaff.learning.interaction-turn.v0`
- v0 允许 `screenshotRefs / axRefs / ocrRefs` 为空数组
- `privacyTags` 与 `sourceRefs.artifactKind` 先保持开放字符串，避免回填脚本被固定枚举卡死
