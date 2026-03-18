# TurnLearningEligibility v0

## 目标

`TurnLearningEligibility` 用来回答一个很具体的问题：

1. 这条 `InteractionTurn` 是否应该进入后续偏好学习。
2. 如果不该进，或者暂时还不确定，原因是什么。

`v0` 固定输出：

- `eligible`
- `ineligible`
- `needs_review`

并且每次判断都必须带一个稳定 `reasonCode`。

## 当前规则

判定优先级按下面顺序执行：

1. `privacy_excluded`
   - 只要 `privacyTags` 命中 `excluded / sensitive / redacted`，直接排除。
2. `synthetic_fixture`
   - 样例夹具、示意 turn 不进入真实偏好学习。
3. `mainline_repair`
   - `turnKind = repair` 直接视为主线修复行为。
4. `assist_prediction_only`
   - `assist + taskProgression` 但没有执行/确认回执时，进入人工复核。
5. `status_only / log_only / background_only`
   - 缺少真实任务推进证据，且文本或来源更像状态播报、日志镜像、后台整理时，直接排除。
6. `mainline_task_progression / mainline_skill_execution`
   - 有真实任务推进证据的 `taskProgression / skillExecution` 进入学习。
7. `insufficient_task_context`
   - 既没有足够结构化证据，也不明显属于状态/日志/后台类时，进入人工复核。

## 主线证据

`v0` 认为以下任一条件成立即可视为“有主线任务推进证据”：

- 有 `execution` 或 `semanticTargetSetRef`
- `observationRef` 带 `rawEventLogPath / taskChunkPath / eventIds`
- `stepReference` 带 `knowledgeStepId / skillStepId / planStepId / sourceEventIds`
- `sourceRefs` 中出现 `rawEventLog / taskChunk / knowledgeItem / skillBundle / executionResult`
- 文本摘要中包含明确动作词，例如：
  - `click / open / run / save`
  - `点击 / 打开 / 运行 / 输入 / 选择`

## reasonCode 一览

- `mainline_task_progression`
- `mainline_skill_execution`
- `mainline_repair`
- `privacy_excluded`
- `synthetic_fixture`
- `assist_prediction_only`
- `status_only`
- `log_only`
- `background_only`
- `insufficient_task_context`

## 使用约定

- `eligible`：允许进入下一层 `NextStateEvidence` / `PreferenceSignal` 提炼。
- `ineligible`：保留审计记录，但不自动进入偏好更新。
- `needs_review`：先挂到人工复核或后续 richer classifier，不直接丢弃。

`v0` 先追求可解释和稳健降噪，不追求把所有边界 case 一次判死。
