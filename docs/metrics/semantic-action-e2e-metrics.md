# Semantic Action E2E Metrics v0

## 目标

本文件冻结 `SEM-402` 的第一版性能与鲁棒性指标、计算口径与发布门槛。

这里的所有指标都基于 `Semantic Action E2E Benchmark` 的离线回归工件计算，是 benchmark proxy，不是线上真实桌面遥测：

- 它回答的是“当前版本的语义执行链路是否仍然稳定、足够快、没有明显超时或抖动回归”。
- 它不直接回答“线上真实老师会不会感知到卡顿”，但它能把明显的性能/稳定性退化在 PR 和 release 前拦下。

## 产物

- `scripts/benchmarks/aggregate_semantic_action_e2e_metrics.py`
- `data/benchmarks/semantic-action-e2e/metrics-v0.json`
- `<benchmark-root>/metrics-summary.json`

其中：

- `metrics-v0.json` 固定 baseline 与 v0 gate。
- `metrics-summary.json` 是某次 benchmark run 的聚合摘要，`benchmark-semantic-e2e-preflight`、release regression 和 GitHub Actions 都会生成它。

## 指标定义

### `casePassRate`

公式：`passedRuns / totalRuns`

含义：被选中的 semantic benchmark run 中，仍命中冻结 expected 的比例。

### `selectorResolutionRate`

公式：`resolvedSemanticLocatorRuns / totalRuns`

判定 `resolvedSemanticLocatorRuns` 的条件：

- `selectorHitPath` 非空；
- `matchedLocatorType` 不是 `coordinateFallback`；
- 当前 run 未偏离冻结 expected。

含义：语义 selector 是否仍能在离线快照里稳定命中，而不是退化到不可解释路径。

### `p50ActionDurationMs`

公式：`durationMs` 的 P50。

含义：中位语义动作执行耗时，用于观察整体时延水平是否抬升。

### `p95ActionDurationMs`

公式：`durationMs` 的 P95。

含义：高分位时延门槛，是 `SEM-402` 的核心性能 gate。

### `maxActionDurationMs`

公式：`max(durationMs)`

含义：观察是否出现单条异常慢动作，即使 P95 还未失守，也能帮助识别长尾退化。

### `timeoutCount`

公式：`count(errorCode contains TIMEOUT)`

含义：结构化超时错误次数。只要出现 timeout，默认就视为明显鲁棒性回归。

### `flakeRecoveryRate`

公式：`flakyRecoveredCases / totalRuns`

含义：需要重跑后才恢复通过的 run 比例，用来监控 benchmark 环境或执行器是否变得脆弱。

### `stabilityPassRate`

公式：`passedRepeatedRuns / totalRepeatedRuns`

前提：只有 `repeatCount > 1` 时才计算。

含义：把同一组 case 顺序重复执行，作为“长会话压力代理”后的通过率。当前 release/CI 默认 `repeatCount=3`。

### `postActionSnapshotRecoveryRate`

公式：`recoveredAfterRetryPostAssertions / postAssertionRuns`

含义：live actuation 后，为了得到稳定 post-assertion snapshot，需要额外重试才能恢复的比例。它不一定是失败，但若比例持续升高，往往说明 UI 稳定性在恶化。

## v0 门槛

- `casePassRate >= 1.0`
- `selectorResolutionRate >= 0.85`
- `p95ActionDurationMs <= 25`
- `maxActionDurationMs <= 50`
- `timeoutCount <= 0`
- `flakeRecoveryRate <= 0.05`
- `stabilityPassRate >= 1.0`

说明：

- `postActionSnapshotRecoveryRate` 在 `v0` 先纳入摘要与观察，但暂不单独作为 fail gate。
- 当 `repeatCount == 1` 时，`stabilityPassRate` 会输出 `null`，对应 gate 标记为 `skipped`；release regression 与 GitHub Actions 会默认传 `repeatCount=3`，避免这个 gate 被长期跳过。

## 运行方式

完整 benchmark + gate：

```bash
make benchmark-semantic-e2e-preflight
```

仅重算指标摘要：

```bash
python3 scripts/benchmarks/aggregate_semantic_action_e2e_metrics.py \
  --benchmark-root /tmp/openstaff-semantic-action-e2e \
  --manifest /tmp/openstaff-semantic-action-e2e/manifest.json \
  --config data/benchmarks/semantic-action-e2e/metrics-v0.json \
  --output /tmp/openstaff-semantic-action-e2e/metrics-summary.json \
  --check-gates
```

## 当前基线

当前冻结 gate 配置对应：

- benchmark id: `semantic-action-e2e-v20260328`
- gate config id: `semantic-action-e2e-metrics-v0-20260328`
- release / CI 默认压力参数：
  - `repeatCount = 3`
  - `sourceCaseCount = 8`

当前 v0 baseline 固定在：

- `casePassRate = 1.0`
- `selectorResolutionRate = 0.875`
- `p95ActionDurationMs = 1.0`
- `maxActionDurationMs = 1.0`
- `timeoutCount = 0`
- `flakeRecoveryRate = 0.0`

压力 run 的 `stabilityPassRate` 会在 release regression 与 GitHub Actions 中按实际 `repeatCount=3` 重新计算并 gate。
