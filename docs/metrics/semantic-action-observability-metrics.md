# Semantic Action Observability Metrics v0

## 目标

本文件冻结 `SEM-303` 第一版语义执行观测口径，用于迁移期持续回答两个问题：

- 语义执行是否还在稳定命中 selector，而不是越来越依赖深层 fallback。
- 安全门是否确实拦住了潜在误触发，而不是把风险静默吞掉。

这里的指标来自 `semantic_actions` SQLite 中的 `action_execution_logs`，是执行期事实数据，不是 benchmark proxy。

## 产物

- `scripts/observability/build_semantic_action_dashboard.py`
- `config/semantic-action-observability.v0.json`
- `data/reports/semantic-action-observability/metrics-summary.json`
- `data/reports/semantic-action-observability/dashboard.md`

其中：

- `metrics-summary.json` 保存结构化指标、环境分桶、gate 结果与告警。
- `dashboard.md` 提供老师和开发者可直接阅读的 Markdown 看板。
- `config/semantic-action-observability.v0.json` 固定第一版环境、阈值与 fail gate。

## 指标定义

### `selectorHitRate`

公式：`matchedNonCoordinateLocatorExecutions / selectorEligibleExecutions`

说明：

- 仅统计 `switch_app / focus_window / click / type / drag`。
- 若动作在 resolver 之前就被 `contextGuard` 或 `teacherConfirmation(required)` 拦下，不计入分母。
- 命中必须是非 `coordinateFallback` 的语义 locator。

### `fallbackLayerDistribution`

公式：按 `matchedLocatorType` 聚合计数

含义：最终到底是通过 `axPath / roleAndTitle / textAnchor / imageAnchor / app_context / window_context` 的哪一层命中。

### `interceptRate`

公式：`blockedExecutions / totalExecutions`

含义：有多少动作在执行前或执行中被 guard 明确拦截。当前会同时输出 `reasonCounts`，用于区分 `context mismatch / confirmation required / unsupported drag intent` 等原因。

### `replaySuccessRate`

公式：

- 若存在 live execution：`succeededLiveExecutions / liveExecutions`
- 否则回退到：`succeededExecutions / totalExecutions`

含义：迁移期优先看真实执行成功率；若当前环境只在做 dry-run，也能先得到过渡期口径。

### `manualConfirmationRate`

公式：`teacherConfirmation(required or approved) / totalExecutions`

含义：有多少动作需要老师显式确认，或已经在老师确认后执行。

### `misTriggerRiskEventCount`

公式：以下事件的去重执行日志数量：

- `SEM202-CONTEXT-MISMATCH`
- `SEM203-ASSERTION-FAILED`
- `SEM201-COORDINATE-FALLBACK-DISALLOWED`

含义：与“误触发风险”直接相关的红线告警数。只要该值大于 `0`，看板会自动生成告警。

## 环境维度

默认环境桶固定为：

- `dev`
- `staging`
- `prod`

环境来源优先级：

1. `build_semantic_action_dashboard.py --source env=/path/to/db`
2. `action_execution_logs.result_json.environment`
3. `--environment`
4. `config.defaultEnvironment`

这保证单库、多库和混合工件三种场景都能稳定分桶。

## v0 门槛

- `selectorHitRate >= 0.95`
- `replaySuccessRate >= 0.95`
- `manualConfirmationRate <= 0.10`
- `misTriggerRiskEventCount <= 0`

同一套门槛会同时评估：

- overall
- `dev`
- `staging`
- `prod`

若某个环境当前没有样本，对应 gate 会标记为 `skipped`。

## 运行方式

单库：

```bash
make semantic-observability-dashboard
```

直接按 gate fail：

```bash
make semantic-observability-gates
```

多环境聚合：

```bash
python3 scripts/observability/build_semantic_action_dashboard.py \
  --source dev=/tmp/openstaff-dev/semantic-actions.sqlite \
  --source staging=/tmp/openstaff-staging/semantic-actions.sqlite \
  --source prod=/tmp/openstaff-prod/semantic-actions.sqlite \
  --check-gates
```

## 告警说明

`SEM-303` 当前只对“误触发风险”做自动告警，不对所有质量退化都升级为红线：

- `contextMismatchCount > 0`：critical
- `postAssertionFailureCount > 0`：critical
- `coordinateFallbackAttemptCount > 0`：warning

其它指标退化会作为 `gateFailure` 告警写进 summary，但不改变上述风险分级。
