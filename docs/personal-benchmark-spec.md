# Personal Desktop Benchmark 规范

## 目标

`Personal Desktop Benchmark` 用来冻结老师在真实桌面上的高频任务样本，并把这些样本转成可重复回归的基线。它覆盖三条链路：

1. 原始教学数据是否还可追溯。
2. `KnowledgeItem -> OpenClaw skill` 的转换是否稳定。
3. skill 预检与 OpenClaw 模拟执行结果是否符合预期基线。

## 当前基线

- benchmark id: `personal-desktop-v20260314`
- case 总数: `22`
- 类别:
  - `developer-tools`: `12`
  - `browser-operations`: `7`
  - `file-organization`: `1`
  - `daily-office`: `2`
- 当前基线结果:
  - `9` 条 case 预检结果为 `needs_teacher_confirmation`，在注入老师确认后可模拟执行成功。
  - `13` 条 case 预检结果为 `failed`，对应当前历史知识中缺失 locator/窗口上下文的任务；benchmark 将这些阻断结果作为已知基线冻结下来，用于监控后续版本是否意外改变行为。

## 目录结构

- `data/benchmarks/personal-desktop/catalog.json`
  - 冻结的 case 清单与预期结果。
- `data/benchmarks/personal-desktop/manifest.json`
  - 最近一次完整 benchmark run 的汇总。
- `data/benchmarks/personal-desktop/generated/<caseId>/source-record.json`
  - 源工件引用与 SHA-256 摘要。
- `data/benchmarks/personal-desktop/generated/<caseId>/benchmark-*/`
  - 由 benchmark 生成的 skill bundle。
- `data/benchmarks/personal-desktop/generated/<caseId>/skill-preflight.json`
  - `validate_skill_bundle.py` 的结构化输出。
- `data/benchmarks/personal-desktop/generated/<caseId>/execution-result.json`
  - `OpenStaffOpenClawCLI --json-result` 的结构化执行结果。
- `data/benchmarks/personal-desktop/generated/<caseId>/review-result.json`
  - benchmark 对当前 case 的最终判定。
- `data/benchmarks/personal-desktop/generated/<caseId>/case-report.json`
  - 单 case 汇总，供 manifest 聚合。

## Case 组成

每条 benchmark case 固定关联以下工件：

- 原始轨迹: `data/raw-events/**/*.jsonl`
- 抽象知识: `data/task-chunks/**/*.json` + `data/knowledge/**/*.json`
- skill 产物: benchmark 生成的 `SKILL.md` + `openstaff-skill.json`
- 执行日志: benchmark run 输出的 OpenClaw review log
- 审阅结果: benchmark 生成的 `review-result.json`

`source-record.json` 会记录原始工件路径与哈希，保证 benchmark 可追溯到最初的教学样本，而不需要重复拷贝原始数据。

## 运行方式

优先使用 Make 入口：

```bash
make benchmark-personal ARGS="--openclaw-executable apps/macos/.build/debug/OpenStaffOpenClawCLI"
```

也可以直接运行脚本：

```bash
python3 scripts/benchmarks/run_personal_desktop_benchmark.py \
  --openclaw-executable apps/macos/.build/debug/OpenStaffOpenClawCLI
```

常用参数：

- `--case-id <id>`: 只跑单条或少量 case。
- `--case-limit <n>`: 只跑前 `n` 条 case，用于 smoke test。
- `--benchmark-root <path>`: 将产物输出到临时目录。
- `--skip-openclaw`: 只做 skill materialization + preflight，不跑执行。

## 通过标准

一次 benchmark run 通过，需要同时满足：

1. catalog 中所有 case 都能找到对应的 `raw-events / task-chunks / knowledge` 源工件。
2. 每条 case 都能生成 skill bundle 与 `source-record.json`。
3. 每条 case 的 `skillPreflightStatus` 与 `executionStatus` 都匹配 `catalog.json` 中冻结的 `expected` 基线。
4. `manifest.json` 中 `passedCases == totalCases`，当前基线要求为 `22 / 22`。

## 设计说明

- benchmark 使用 committed 教学数据，而不是运行时临时数据；这样版本升级后仍然可以重复回归。
- 对 `needs_teacher_confirmation` 的 case，runner 会注入老师确认，以验证 skill/runtime 链路本身，而不是把“是否自动执行”混入回归噪音。
- 对当前确实缺失 locator 的老数据，benchmark 保留 `failed -> blocked` 的预期结果。未来如果通过语义定位补全让这些 case 变成可执行，应同步更新 `catalog.json` 的 `expected` 字段，并重新生成基线。
