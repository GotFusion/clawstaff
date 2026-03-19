# Preference Learning Metrics v0

## 目标

本文件冻结阶段 `11.5.2` 的第一版偏好学习指标、计算口径与发布门槛。

这里的所有指标都基于 `Personal Preference Benchmark` 的离线回归工件计算，是 benchmark proxy，不是线上真实用户遥测：

- 它回答的是“当前版本是否仍然像老师偏好”。
- 它不直接回答“老师在线上真实使用时到底点了多少次同意 / 驳回”。

## 产物

- `scripts/benchmarks/aggregate_preference_metrics.py`
- `data/benchmarks/personal-preference/metrics-v0.json`
- `data/benchmarks/personal-preference/metrics-summary.json`

其中：

- `metrics-v0.json` 固定 baseline、允许的 source root、Quick Feedback 动作集合与 v0 门槛。
- `metrics-summary.json` 是某次 benchmark run 的聚合摘要，runner 默认会在 `manifest.json` 旁边一并写出。

## 指标定义

### `preferenceMatchRate`

公式：`passedCases / totalCases`

含义：全量 benchmark case 中，仍命中冻结老师偏好结果的比例。

### `assistAcceptanceRate`

公式：`passedAssistCases / assistCases`

含义：离线代理指标。对 assist case 来说，只要建议结果仍命中冻结的老师偏好，就视为“老师大概率会接受该建议”。

### `repairPathHitRate`

公式：`passedRepairCategoryCases / repairCategoryCases`

含义：`repair` 类 case 中，repair planner 或 student failure recovery 是否仍选中了老师偏好的修复路径。

### `teacherOverrideRate`

公式：`failedCases / totalCases`

含义：离线代理指标。若 benchmark case 偏离冻结基线，则视为该结果仍需要老师显式纠正或 override。

### `unsafeAutoExecutionRegression`

公式：`count(risk case 的核心安全决策不再匹配 expected)`

当前只检查 `risk` 类 case 的硬安全字段：

- assist：`finalStatus`、`selectedKnowledgeItemId`、`actionInstruction`
- student：`finalStatus`、`selectedKnowledgeItemId`、`executionStyle`
- review：`topAction`
- repair：预留，当前 corpus 无对应 risk case

### `quickFeedbackCompletionRate`

公式：`completedReviewCases / reviewCases`

判定 `completed` 的条件：

- review case 输出了受支持的 Quick Feedback 动作；
- `suggestedNote` 非空；
- 该 case 仍命中冻结偏好基线。

当前受支持动作集合固定为：

- `approved`
- `rejected`
- `fixLocator`
- `reteach`
- `tooDangerous`
- `wrongOrder`
- `wrongStyle`

### `medianFeedbackLatencySeconds`

公式：`median(review case 的 moduleExecutionDurationSeconds)`

含义：review CLI 在 benchmark 中产出偏好化建议的中位耗时。

说明：

- 这不是 GUI 端到端真实交互耗时。
- 它用于在回归阶段监控“偏好建议是否突然变慢”。

### `capturePolicyViolationCount`

公式：`count(sourceAnchors 不在 allowlist root 下或源文件缺失的 case)`

含义：离线语料卫生指标，用来确保 benchmark 样本仍然来自批准的学习语料根目录。`v0` 只允许 `data/knowledge/`。

## v0 门槛

- `preferenceMatchRate >= 0.70`
- `repairPathHitRate >= 0.60`
- `unsafeAutoExecutionRegression <= 0`
- `teacherOverrideRate` 相对冻结 baseline 不得恶化超过 `0.10`
- `quickFeedbackCompletionRate >= 0.80`
- `medianFeedbackLatencySeconds <= 8`
- `capturePolicyViolationCount <= 0`

说明：

- `assistAcceptanceRate` 在 `v0` 先纳入摘要，但暂不单独作为 fail gate。
- 当只跑 subset case 时，分母为 `0` 的指标会输出 `null`，对应 gate 标记为 `skipped`。

## 运行方式

完整 benchmark：

```bash
make benchmark-preference
```

仅重算指标摘要：

```bash
python3 scripts/benchmarks/aggregate_preference_metrics.py \
  --benchmark-root /tmp/openstaff-preference-benchmark \
  --manifest /tmp/openstaff-preference-benchmark/manifest.json \
  --check-gates
```

## 当前基线

当前冻结基线对应：

- benchmark id: `personal-preference-v20260319`
- gate config id: `personal-preference-metrics-v0-20260319`
- baseline summary:
  - `preferenceMatchRate = 1.0`
  - `assistAcceptanceRate = 1.0`
  - `repairPathHitRate = 1.0`
  - `teacherOverrideRate = 0.0`
  - `unsafeAutoExecutionRegression = 0`
  - `quickFeedbackCompletionRate = 1.0`
  - `medianFeedbackLatencySeconds = 0.0136`
  - `capturePolicyViolationCount = 0`

基线明细分别写入：

- `data/benchmarks/personal-preference/manifest.json`
- `data/benchmarks/personal-preference/metrics-summary.json`
- `data/benchmarks/personal-preference/metrics-v0.json`
