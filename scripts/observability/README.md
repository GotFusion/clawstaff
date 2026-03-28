# scripts/observability/

语义执行链路的可观测性脚本与指标看板入口。

## 当前脚本

- `build_semantic_action_dashboard.py`
  - 读取一个或多个 `semantic_actions` SQLite 库中的 `action_execution_logs`
  - 聚合 `selectorHitRate / fallbackLayerDistribution / interceptRate / replaySuccessRate / manualConfirmationRate`
  - 按环境输出 `metrics-summary.json` 与 `dashboard.md`
  - 将 `SEM202-CONTEXT-MISMATCH / SEM203-ASSERTION-FAILED / SEM201-COORDINATE-FALLBACK-DISALLOWED` 统一归类为 `misTriggerRiskEventCount`
  - 支持通过 `--check-gates` 按配置阈值直接 fail，用于 CI 或发布前预检

## 推荐命令

单环境默认库：

```bash
python3 scripts/observability/build_semantic_action_dashboard.py \
  --db-path data/semantic-actions/semantic-actions.sqlite \
  --json
```

多环境聚合：

```bash
python3 scripts/observability/build_semantic_action_dashboard.py \
  --source dev=/tmp/openstaff-dev/semantic-actions.sqlite \
  --source staging=/tmp/openstaff-staging/semantic-actions.sqlite \
  --source prod=/tmp/openstaff-prod/semantic-actions.sqlite \
  --check-gates
```

产物默认写到：

- `data/reports/semantic-action-observability/metrics-summary.json`
- `data/reports/semantic-action-observability/dashboard.md`
