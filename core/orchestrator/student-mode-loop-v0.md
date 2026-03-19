# OpenStaff 学生模式闭环 v0（Phase 4.3）

## 1. 目标

实现学生模式最小可演示闭环：
- 输入任务目标。
- 自动规划执行步骤。
- 调用技能执行（当前为 OpenClaw 调用模拟）。
- 输出结构化审阅报告。

实现位置：
- `core/contracts/StudentModeContracts.swift`
- `core/orchestrator/StudentModeLoop.swift`
- `core/executor/StudentSkillExecutor.swift`
- `core/storage/StudentLoopLogWriter.swift`
- `core/storage/StudentReviewReportWriter.swift`
- `apps/macos/Sources/OpenStaffStudentCLI/*`

## 2. 闭环流程

1. 输入 `goal` 和知识来源（单文件或目录）。  
2. 默认由 `RuleBasedStudentTaskPlanner` 生成 `StudentExecutionPlan`；当 student planner feature flag + benchmark-safe attestation 同时开启时，改由 `PreferenceAwareStudentPlanner` 生成带 `preferenceDecision` 的计划。  
3. 通过 `ModeStateMachine` 切换到 `student` 模式（带守卫条件）。  
4. `StudentSkillExecutor` 按计划步骤顺序执行技能。  
5. `StudentReviewReportWriter` 输出结构化审阅报告。  
6. `StudentLoopLogWriter` 写入全过程结构化日志。  

## 3. 自动规划策略（先规则后模型）

### 规则策略 `rule.v0`
- 支持按 `goal` 匹配 `KnowledgeItem`（`appName/appBundleId/item.goal`）。
- 支持 `preferredKnowledgeItemId` 人工优先。
- 选择得分最高知识条目，按其 `KnowledgeStep` 顺序生成计划步骤。

### 偏好策略 `preference-aware-rule.v1`（Feature Flag）
- 读取 `PreferenceProfile.plannerPreferences`，对同一批候选知识条目做二次重排。
- 可区分 `保守 / 积极` 两种执行姿态，并调整步骤信心分。
- 可显式记录“失败后先 repair 还是先 re-teach”的偏好。
- 默认关闭：
  - CLI 需要同时传入 `--enable-preference-aware-planner` 与 `--student-planner-benchmark-safe`
  - App 需要同时设置 `OPENSTAFF_ENABLE_PREFERENCE_AWARE_STUDENT_PLANNER=1` 与 `OPENSTAFF_STUDENT_PLANNER_BENCHMARK_SAFE=1`

### 模型策略（预留）
- `modelV1Placeholder` 已在契约中预留，后续可接模型规划。

## 4. 技能执行

执行器：`StudentSkillExecutor`
- 当前为 OpenClaw 调用模拟输出（保留 `skillId` 语义）。
- 默认 `dry-run`。
- 支持 `--simulate-failure-step` 指定步骤失败验证失败链路。
- 内置高风险关键词拦截（返回 `EXE-ACTION-BLOCKED`）。

## 5. 结构化审阅报告

报告结构：`StudentReviewReport`（JSON）  
默认路径：
- `data/reports/{yyyy-mm-dd}/{sessionId}-{taskId}-student-review.json`

关键字段：
- `goal`
- `plan`
- `stepResults`
- `totalSteps/succeededSteps/failedSteps/blockedSteps`
- `finalStatus`
- `summary`

## 6. 日志

日志文件：`data/logs/{yyyy-mm-dd}/{sessionId}-student.log`（JSONL）

常见状态码：
- `STATUS_ORC_STUDENT_PLAN_READY`
- `STATUS_EXE_STUDENT_EXECUTION_STARTED`
- `STATUS_EXE_STUDENT_EXECUTION_COMPLETED`
- `STATUS_EXE_STUDENT_EXECUTION_FAILED`
- `STATUS_ORC_STUDENT_REVIEW_GENERATED`

## 7. CLI 验收

成功闭环：

```bash
make student ARGS="--goal '在 Safari 中复现点击流程' --knowledge core/knowledge/examples/knowledge-item.sample.json"
```

失败闭环（第 1 步模拟失败）：

```bash
make student ARGS="--goal '在 Safari 中复现点击流程' --knowledge core/knowledge/examples/knowledge-item.sample.json --simulate-failure-step 1"
```
