# NextStateEvidence v0

## 目标

`NextStateEvidence` 是 `InteractionTurn` 之后的统一反馈证据层，用来回答两件事：

1. 这一步执行完后，外界到底给了什么反馈。
2. 这些反馈更偏“评价结果”，还是更偏“指导下一步怎么修”。

`v0` 先固定 6 类来源：

- `teacherReview`
- `executionRuntime`
- `replayVerify`
- `driftDetection`
- `chatgptSuggestion`
- `benchmarkResult`

## 核心字段

- `evidenceId / turnId / traceId / sessionId / taskId / stepId`
- `source`：统一来源枚举
- `summary`：只保留可读摘要，不复制大文件正文
- `rawRefs[]`：回链原始日志、review、report 或 LLM 输出
- `timestamp / confidence / severity`
- `role`：`evaluative / directive / mixed`
- `evaluativeCandidate`：供后续 `PreferenceSignal` 提炼 outcome / style / risk
- `directiveCandidate`：供后续 repair / reteach / planner hint 复用

## GUI failure bucket

当 evidence 明确指向 GUI 失败时，必须写 `guiFailureBucket`：

- `locator_resolution_failed`
- `action_kind_mismatch`
- `risk_blocked`

第一版约定：

- `teacherReview.fixLocator` -> `locator_resolution_failed`
- `teacherReview.tooDangerous` 或 runtime blocked -> `risk_blocked`
- execution / replay / drift / LLM 若明确指出动作种类不对，再写 `action_kind_mismatch`

## 落盘约定

- 单 turn 证据文件：`data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`
- 每行一条 `NextStateEvidence`
- 一个 turn 可以有多条 evidence，例如：
  - `executionRuntime`
  - `benchmarkResult`
  - `teacherReview`

`v0` 只落摘要和引用：

- 允许保留 `path + lineNumber + identifier`
- 不复制 execution log、benchmark review、drift report、LLM 原文的大段正文

## 当前回填策略

`scripts/learning/build_next_state_evidence.py` 当前会从已知 `InteractionTurn` 关联工件中回填：

1. `teacherReview`
2. `executionRuntime`
3. `benchmarkResult`

另外补 3 条固定 example fixture，锁定 schema 对以下来源的兼容性：

1. `replayVerify`
2. `driftDetection`
3. `chatgptSuggestion`

这样可以先满足 Phase 11 v0 的统一证据层要求，而不阻塞后续真实 replay/drift/LLM 工件继续入库。
