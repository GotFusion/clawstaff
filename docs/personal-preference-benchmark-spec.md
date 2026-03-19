# Personal Preference Benchmark 规范

## 目标

`Personal Preference Benchmark` 用来冻结“系统是否更像老师偏好”的回归基线。第一版聚焦四类偏好链路：

1. `style`：表达与交互风格是否贴近老师习惯。
2. `procedure`：步骤顺序与常用操作路径是否命中老师偏好。
3. `risk`：风险拦截、保守执行与审阅建议是否符合老师安全边界。
4. `repair`：当 skill 漂移或执行失败时，修复路径是否符合老师偏好。

benchmark 不是在测“能不能执行”这一件事，而是在测 assist / student / repair / review 四个模块是否因为 `PreferenceProfile` 的存在，做出了老师更偏好的决策。

## 当前基线

- benchmark id: `personal-preference-v20260319`
- profile 总数: `12`
- case 总数: `24`
- case 构成:
  - `style`: `6`
  - `procedure`: `6`
  - `risk`: `6`
  - `repair`: `6`
- 样本来源:
  - `12` 条真实历史任务锚点
  - `12` 条基于真实任务改写的扰动样本
- 模块覆盖:
  - `assist`: `8`
  - `student`: `6`
  - `review`: `6`
  - `repair`: `4`
- 当前基线结果:
  - `manifest.json` 冻结结果为 `24 / 24` 通过
  - `preferenceMatchRate = 1.0`
  - 四类偏好、四个模块的命中率当前均为 `1.0`
  - `metrics-summary.json` 会额外冻结 `assistAcceptanceRate / repairPathHitRate / teacherOverrideRate / quickFeedbackCompletionRate / medianFeedbackLatencySeconds / capturePolicyViolationCount` 的 v0 汇总

## 目录结构

- `data/benchmarks/personal-preference/catalog.json`
  - 固定 case catalog、profile 定义、expected preference-aware behavior。
- `data/benchmarks/personal-preference/manifest.json`
  - 最近一次完整 benchmark run 的汇总基线。
- `data/benchmarks/personal-preference/metrics-v0.json`
  - v0 baseline、Quick Feedback 动作集合、允许 source root 与门槛配置。
- `data/benchmarks/personal-preference/metrics-summary.json`
  - 最近一次 benchmark run 的 v0 指标摘要与 gate 结果。
- `<benchmark-root>/generated/<caseId>/source-record.json`
  - case 的源锚点、catalog 哈希与可追溯信息。
- `<benchmark-root>/generated/<caseId>/profile-snapshot.json`
  - benchmark 物化出的 `PreferenceProfileSnapshot`。
- `<benchmark-root>/generated/<caseId>/module-result.json`
  - assist / student / repair / review 模块的结构化输出。
- `<benchmark-root>/generated/<caseId>/review-result.json`
  - benchmark 对比 expected 与 actual 的判定结果。
- `<benchmark-root>/generated/<caseId>/case-report.json`
  - 单 case 汇总，供 manifest 聚合。

默认 `benchmark-root` 为 `data/benchmarks/personal-preference/`。如果只是做 smoke test，建议显式传入临时目录，避免把 `generated/` 产物留在仓库工作区中。

runner 在写出 `manifest.json` 后，会继续自动生成 `<benchmark-root>/metrics-summary.json`。

## Case 组成

每条 preference benchmark case 固定包含以下元素：

- `profileId`
  - 指向 catalog 内置 profile 规格，由 runner 物化成 `PreferenceProfileSnapshot`。
- `module`
  - 指定本 case 测 assist / student / review / repair 中哪一条偏好装配链路。
- `preferenceCategory`
  - `style / procedure / risk / repair` 之一。
- `sourceType`
  - `real` 或 `perturbation`。
- `fixture`
  - 紧凑 DSL，而不是完整 CLI 工件。runner 会把它物化成知识条目、review scenario、skill bundle 或 replay snapshot。
- `expected`
  - 当前版本冻结的 preference-aware 输出摘要。
- `sourceAnchors`
  - 指向 committed 历史知识样本，runner 会生成 `source-record.json` 并记录 SHA-256，保证每条 case 都能追溯到真实教学来源。

其中：

- `real` case 直接依附真实历史知识锚点，确保 benchmark 不脱离老师的真实使用习惯。
- `perturbation` case 复用同类真实任务语义，但替换文案、顺序、窗口标题或失败形态，防止系统只“记住样本字面量”。

## 运行方式

优先使用 Make 入口：

```bash
make benchmark-preference
make benchmark-preference-preflight
```

也可以显式指定输出目录：

```bash
make benchmark-preference ARGS="--benchmark-root /tmp/openstaff-preference-benchmark"
```

或者直接运行脚本：

```bash
python3 scripts/benchmarks/run_personal_preference_benchmark.py \
  --benchmark-root /tmp/openstaff-preference-benchmark
```

只重算指标摘要时，可直接运行：

```bash
python3 scripts/benchmarks/aggregate_preference_metrics.py \
  --benchmark-root /tmp/openstaff-preference-benchmark \
  --manifest /tmp/openstaff-preference-benchmark/manifest.json \
  --check-gates
```

`release-preflight` 已默认接入这套 benchmark，并会在 benchmark 产出后追加一次 `--check-gates` 校验；因此偏好退化、风险回归或 capture policy 违规现在都能在发布前被直接拦截。

runner 会按需自动构建所需 Swift CLI：

- `OpenStaffAssistCLI`
- `OpenStaffStudentCLI`
- `OpenStaffReplayVerifyCLI`
- `OpenStaffExecutionReviewCLI`

常用参数：

- `--case-id <id>`：只跑指定 case，可重复传入。
- `--case-limit <n>`：只跑前 `n` 条 case，用于 smoke test。
- `--assist-executable <path>`：复用已编译 assist 可执行文件。
- `--student-executable <path>`：复用已编译 student 可执行文件。
- `--replay-verify-executable <path>`：复用已编译 repair 可执行文件。
- `--review-executable <path>`：复用已编译 review 可执行文件。
- `--report <path>`：显式指定 manifest 输出路径。

## 通过标准

一次 benchmark run 通过，需要同时满足：

1. catalog 至少固定 `24` 条 case，且四类偏好各 `6` 条。
2. `real` 与 `perturbation` 样本各 `12` 条。
3. assist / student / review / repair 四个模块都至少命中一组 case。
4. 每条 case 都能生成 `source-record.json`、`profile-snapshot.json`、`module-result.json`、`review-result.json` 与 `case-report.json`。
5. 每条 case 的 `actual` 输出都与 `catalog.json` 中冻结的 `expected` 基线一致。
6. `manifest.json` 中 `passedCases == totalCases`，当前基线要求为 `24 / 24`。

## 设计说明

- benchmark 同时使用 committed 历史锚点与规范化扰动样本，避免偏好评测退化成“记忆真实 case 文本”。
- `source-record.json` 会把每条 case 回链到真实知识样本与 catalog 哈希，便于后续审计“为什么这条偏好测试要这么期待”。
- review 链路单独引入 `OpenStaffExecutionReviewCLI`，避免为了 benchmark 人工拼接 GUI 状态，也让 `ExecutionReviewStore` 的偏好建议逻辑具备可回归入口。
- `aggregate_preference_metrics.py` 会把 benchmark case 进一步聚合为 v0 指标摘要；其中 `teacherOverrideRate`、`assistAcceptanceRate` 等均明确标记为 benchmark proxy，避免和线上真实老师行为遥测混淆。
