# Semantic-Only Cutover Runbook

更新时间：2026-03-28

## 1. 目标

将 OpenStaff/OpenClaw 执行链路正式固定为 semantic-only：
- 不再依赖调用方显式传入 `--semantic-only`。
- 不再提供任何恢复坐标执行的发布开关。
- 坐标字段仅继续保留为 provenance、审计和诊断事实。

## 2. 切流前门禁

在 staging 放量前，至少完成以下检查：

1. `make release-preflight`
2. `make benchmark-semantic-e2e-preflight`
3. `make semantic-observability-gates`
4. 对高风险 skill 抽样执行 `make openclaw ARGS="--skill-dir <skill-dir> --teacher-confirmed --json-result"`

通过标准：
- `release-preflight` 无失败项。
- `SEM-402` benchmark gate 无失败项。
- `SEM-303` 看板中 `misTriggerRiskEventCount = 0`。
- 抽样 OpenClaw 执行不存在坐标成功路径；coordinate-only skill 只能被 preflight 拒绝。

## 3. Staging 放量

1. 使用当前发布候选版本部署到 staging。
2. 运行一轮 `semantic-observability-gates`，确认 `staging` 维度无 gate fail。
3. 对高风险类别至少各抽样一条：
   - `switch_app`
   - `type`
   - `drag`
   - 低置信或 `manual_review_required`
4. 记录以下摘要并归档到发布记录：
   - `selectorHitRate`
   - `replaySuccessRate`
   - `manualConfirmationRate`
   - `misTriggerRiskEventCount`

## 4. Prod 放量

1. staging 验证通过后，按既定发布节奏部署到 prod。
2. 切流当天重新执行一次多环境聚合看板：

```bash
python3 scripts/observability/build_semantic_action_dashboard.py \
  --source staging=/tmp/openstaff-staging/semantic-actions.sqlite \
  --source prod=/tmp/openstaff-prod/semantic-actions.sqlite \
  --check-gates
```

3. 放量后连续 `7` 天跟踪核心指标：
   - `selectorHitRate`
   - `replaySuccessRate`
   - `manualConfirmationRate`
   - `misTriggerRiskEventCount`
   - `postAssertionFailureCount`

## 5. 异常处置与回滚

若出现以下任一信号，应停止继续放量：
- `misTriggerRiskEventCount > 0`
- `replaySuccessRate` 明显退化
- `manualConfirmationRate` 异常升高并持续
- 高风险动作出现 post-assertion failure 聚集

允许的处置方式：
- 回滚到上一版本发布包。
- 临时提高老师确认覆盖范围。
- 暂停相关自动执行入口。

不允许的处置方式：
- 恢复坐标执行。
- 重新引入 `coordinateFallback` 作为执行决策输入。
- 绕过 `Context Guard` / `Post-Assertion` / `Teacher Confirmation`。

## 6. 验收结论

`SEM-501` 的工程切流在以下条件下视为完成：
- gateway / runner 已默认 semantic-only。
- 发布链路不存在坐标执行开关。
- rollback 预案明确限定为“只回滚版本，不恢复坐标执行”。

“全量后一周核心指标稳定”属于生产运行验收项，需在真实 prod 观测窗口结束后回写到 backlog。
