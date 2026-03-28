# Semantic Action E2E Benchmark 规范

## 目标

`Semantic Action E2E Benchmark` 用来冻结语义执行链路在高风险桌面交互上的回归基线。它直接覆盖：

1. `semantic_actions` SQLite 物化是否稳定。
2. `OpenStaffReplayVerifyCLI` 对语义动作的解析、context guard、teacher confirmation policy override 与 dry-run 执行是否稳定。
3. 失败时是否能留下结构化上下文，便于后续复现和定位。

这套 benchmark 不依赖实时桌面环境，而是复用 committed snapshot 做离线端到端回归，因此既适合 PR CI，也适合 nightly 跑满。

## 当前基线

- benchmark id: `semantic-action-e2e-v20260328`
- case 总数: `8`
- 场景覆盖:
  - `switch_app`: `1`
  - `focus_window`: `1`
  - `type`: `1`
  - `shortcut`: `1`
  - `drag_window`: `1`
  - `drag_list`: `1`
  - `multi_display`: `1`
  - `browser_url`: `1`
- 当前基线结果:
  - `manifest.json` 冻结结果为 `8 / 8` 通过
  - `browser_url` mismatch case 固定返回 `SEM202-CONTEXT-MISMATCH`
  - 其余 `7` 条 dry-run case 固定返回 `STATUS_SEMANTIC_ACTION_DRY_RUN_SUCCEEDED`

## 目录结构

- `data/benchmarks/semantic-action-e2e/catalog.json`
  - 冻结的 case 清单、snapshot 引用与 expected 结果。
- `data/benchmarks/semantic-action-e2e/manifest.json`
  - 最近一次完整 benchmark run 的汇总基线。
- `data/benchmarks/semantic-action-e2e/snapshots/*.json`
  - committed `ReplayEnvironmentSnapshot` fixture。
- `<benchmark-root>/generated/<caseId>/source-record.json`
  - case 的快照引用、SHA-256 与 action fingerprint。
- `<benchmark-root>/generated/<caseId>/case-report.json`
  - 单 case 汇总，供 manifest 聚合。
- `<benchmark-root>/generated/<caseId>/attempts/attempt-XX/semantic-actions.sqlite`
  - benchmark 物化出的 `semantic_actions` SQLite。
- `<benchmark-root>/generated/<caseId>/attempts/attempt-XX/{cli-report,execution-log,attempt-report}.json`
  - replay verify 输出、落库执行日志与本次 attempt 判定。
- `<benchmark-root>/generated/<caseId>/attempts/attempt-XX/{cli.stdout,cli.stderr}.txt`
  - CLI 原始输出，便于精确复现。

默认 `benchmark-root` 为 `data/benchmarks/semantic-action-e2e/`。如果只是做 smoke test，建议传临时目录，避免本地工作区留下额外工件。

## Case 组成

每条 benchmark case 固定包含以下元素：

- `snapshotPath`
  - 指向 committed `ReplayEnvironmentSnapshot` fixture。
- `action`
  - 要物化进 `semantic_actions` SQLite 的语义动作记录，包含 `actionType / selector / args / context / confidence`，必要时还会补 `teacherConfirmationPolicy` override。
- `expected`
  - runner 会按子集比较 `exitCode / report / executionLog`，确保 CLI 输出与 SQLite `action_execution_logs` 同时不回归。
- `coverage`
  - 标记这条 case 覆盖的风险场景，供 manifest 聚合与 CI 报告展示。

其中：

- `switch_app / drag` case 默认显式关闭对应的 teacher confirmation 策略，避免 benchmark 因 SEM-302 安全门被噪声阻断。
- `browser_url` case 固定验证 `Context Guard` 能在 host 不匹配时阻断执行。
- `multi_display` case 使用 secondary display 坐标快照，确保 selector 解析不被单屏假设绑死。

## 运行方式

优先使用 Make 入口：

```bash
make benchmark-semantic-e2e
```

也可以显式指定输出目录：

```bash
make benchmark-semantic-e2e ARGS="--benchmark-root /tmp/openstaff-semantic-action-e2e --report /tmp/openstaff-semantic-action-e2e/manifest.json"
```

或者直接运行脚本：

```bash
python3 scripts/benchmarks/run_semantic_action_e2e_benchmark.py \
  --benchmark-root /tmp/openstaff-semantic-action-e2e \
  --report /tmp/openstaff-semantic-action-e2e/manifest.json
```

常用参数：

- `--case-id <id>`：只跑指定 case，可重复传入。
- `--case-limit <n>`：只跑前 `n` 条 case，用于 smoke test。
- `--replay-verify-executable <path>`：复用已编译 `OpenStaffReplayVerifyCLI`。
- `--environment <name>`：写入执行日志环境标签，默认 `benchmark`。
- `--max-retries <n>`：失败后追加重跑次数，默认 `1`，用于固定 flake 恢复策略。

## 通过标准

一次 benchmark run 通过，需要同时满足：

1. catalog 固定 `8` 条 case，且八类高风险覆盖全部命中。
2. 每条 case 都能成功生成 `source-record.json`、`case-report.json` 与 attempt 级结构化工件。
3. 每条 case 的 `exitCode / report / executionLog` 都匹配 `catalog.json` 中冻结的 `expected` 结果。
4. `manifest.json` 中 `passedCases == totalCases`，当前基线要求为 `8 / 8`。
5. 若出现失败，至少能从 `attempt-report.json + cli-report.json + execution-log.json` 复现阻断原因与 selector/context 命中路径。

## 设计说明

- benchmark 走的是 `semantic action -> SQLite -> ReplayVerifyCLI -> action_execution_logs` 的完整链路，而不是单测级别的局部函数调用。
- committed snapshot 替代 live accessibility 环境，保证 PR / nightly 能稳定复现结果。
- `--max-retries` 只用于吸收编译或环境级偶发抖动；expected 结果本身仍是确定性的，不允许通过“模糊匹配”掩盖行为变化。
- nightly workflow 会在失败时上传整套 benchmark output artifact，确保回归不是只有一个红灯，而是能直接看到具体哪条 case、哪次 attempt、哪份 CLI/SQLite 结果出了问题。
