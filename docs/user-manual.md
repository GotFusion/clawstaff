# OpenStaff 用户使用说明书

版本：v0.6.9
更新时间：2026-03-28

## 1. 产品简介

OpenStaff 是“老师-学生”式个人助理：
- 老师：你（用户）。
- 学生：OpenStaff 软件。

软件通过记录并学习你的桌面操作，沉淀为知识条目，然后在三种模式中协助你：
- 教学模式：观察并学习。
- 辅助模式：预测下一步并经确认后执行。
- 学生模式：根据知识自主执行并输出审阅报告。

## 2. 运行前准备

### 2.1 系统要求
- macOS（建议 14+）。
- Swift toolchain / Xcode Command Line Tools。
- Python 3.10+（用于脚本与测试）。

### 2.2 仓库准备
在项目根目录执行：

```bash
make build
```

### 2.3 环境变量
复制环境变量模板：

```bash
cp .env.example .env.local
```

按需填写：
- `OPENAI_API_KEY`：使用在线 OpenAI provider 时必填。
- `OPENCLAW_CLI_PATH`：OpenClaw 可执行文件路径；阶段 8.2 的 `OpenClawRunner` / `OpenStaffOpenClawCLI` 会优先使用它，未设置时回退到本地 gateway。
- `OPENSTAFF_ENABLE_PREFERENCE_AWARE_STUDENT_PLANNER`：当值为 `1/true/yes/on` 时，请求启用 student planner 偏好装配。
- `OPENSTAFF_STUDENT_PLANNER_BENCHMARK_SAFE`：当值为 `1/true/yes/on` 时，表示已完成人工 benchmark-safe attestation；需与上一项同时设置，App 内 student workflow 才会真正切到偏好装配 planner。
- `OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG`：当值为 `1/true/yes/on` 时，把 assist / student / skill generation / repair 的偏好装配决策写入 `data/preferences/assembly/**`，默认关闭。

### 2.4 配置文件
- 默认配置：`config/default.yaml`
- 开发覆盖：`config/dev.yaml`
- 发布模板：`config/release.example.yaml`

## 3. 三种模式使用方法

### 3.1 教学模式（Learning）
目标：采集你的操作并形成知识。

推荐方式（已集成到 OpenStaff App）：
- 打开 OpenStaff 控制台。
- 选择“教学模式”并点击“开始”。
- 点击“停止”后会自动执行：事件切片 + 知识条目生成（不再需要手动跑 `slice/knowledge`）。
- 教学模式停止后的内置切片策略默认按“整段会话”生成单任务（从开始到停止），跨应用跳转/空闲不再强制切分；干扰步骤交由 LLM 在后处理阶段筛选。
- 在“状态工作台 -> 教学后处理（LLM / Skill）”选择转换方式：
  - `自动 API`：程序自动调用 ChatGPT API 并生成 OpenClaw Skill。
  - `手动粘贴`：程序生成提示词预览，用户手动复制到 ChatGPT，再把返回结果粘贴回程序执行。

兼容调试命令（仅排障/回归使用）：

```bash
make capture ARGS="--max-events 20"
make slice ARGS="--session-id session-20260309-a1 --date 2026-03-09"
make knowledge ARGS="--task-chunk data/task-chunks/2026-03-09/task-session-20260309-a1-001.json"
```

### 3.2 辅助模式（Assist）
目标：学生预测下一步，经你确认后执行。

推荐方式（已集成到 OpenStaff App）：
- 选择“辅助模式”并点击“开始”。
- App 会直接在模式内执行“预测 -> 确认（默认集成确认）-> 执行 -> 写日志”。

兼容调试命令：
```bash
make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"
```

### 3.3 学生模式（Student）
目标：学生根据目标自主执行并生成审阅报告。

推荐方式（已集成到 OpenStaff App）：
- 选择“学生模式”并点击“开始”。
- App 会直接执行“规划 -> 执行 -> 审阅报告写入”。
- 默认仍使用 `rule-v0` planner；若要在 App 内启用偏好装配 student planner，需要同时设置：
  - `OPENSTAFF_ENABLE_PREFERENCE_AWARE_STUDENT_PLANNER=1`
  - `OPENSTAFF_STUDENT_PLANNER_BENCHMARK_SAFE=1`
- 在“状态工作台 -> 审阅与反馈”选中对应执行日志后，可直接看到：
  - 老师原始步骤
  - 当前 skill 步骤
  - 本次实际执行结果
- 若执行失败，可直接点击 `修复 locator` 或 `重新示教`，系统会同时保存老师反馈与 skill repair request。

兼容调试命令：
```bash
make student ARGS="--goal 在 Safari 中复现点击流程 --knowledge core/knowledge/examples/knowledge-item.sample.json"

# 仅在 benchmark-safe attestation 后启用偏好装配 planner
make student ARGS="--goal 在 Safari 中复现点击流程 --knowledge core/knowledge/examples/knowledge-item.sample.json --enable-preference-aware-planner --student-planner-benchmark-safe --preferences-root data/preferences"
```

### 3.4 审阅台闭环（Review Desk）
适用场景：学生模式 skill 执行失败、OpenClaw 运行失败、老师需要快速判定是否接受结果。

推荐方式（已集成到 OpenStaff App）：
1. 打开“状态工作台 -> 审阅与反馈”。  
2. 在左侧执行日志列表中选中目标日志。  
3. 在右侧查看“三栏对照”：老师原始步骤 / 当前 skill 步骤 / 本次实际执行结果。  
4. 根据判断点击：
   - `通过`
   - `驳回`
   - `修 locator`
   - `重示教`
   - `太危险`
   - `顺序不对`
   - `风格不对`
5. 如有需要，在短备注框补一句失败原因、线索或示教意图，不需要写长段说明。  

说明：
- `修 locator` / `重示教` 会同时写入 `data/feedback/{yyyy-mm-dd}/*.jsonl` 与 `data/skills/repairs/{yyyy-mm-dd}/skill-repair.jsonl`。
- 所有快评动作都会在反馈记录中落一条标准化 `teacherReview` evidence，并带上统一快捷键定义（`Cmd+1` 到 `Cmd+7`）。
- 若日志未成功关联到 skill，`修 locator` / `重示教` 会自动禁用。
- 若本地已存在 `data/preferences` 最新 profile，审阅台会额外显示“偏好化审阅建议”，给出推荐动作、推荐短备注与规则来源，但不会自动替老师提交反馈。

## 4. LLM 与 Skill 工作流

### 4.0 App 内置双路径（推荐）
在“状态工作台 -> 教学后处理（LLM / Skill）”可切换：
- `自动 API`：教学停止后自动执行 `LLM 解析 -> Skill 映射`。
- `手动粘贴`：教学停止后自动生成提示词，支持复制/粘贴闭环执行。

### 4.0.1 手动粘贴流程（无 API 场景）
1. 先完成一次教学模式并点击停止。  
2. 在“教学后处理”选择 `手动粘贴`。  
3. 点击“复制提示词与数据”，粘贴到 ChatGPT 对话框。  
4. 等 ChatGPT 返回 JSON 后，复制返回内容。  
5. 粘贴到 App 的“LLM 结果输入”文本框，点击“执行手动结果”。  
6. App 会生成 OpenClaw Skill，并显示输出目录路径。  

### 4.1 提示词渲染与校验
```bash
make llm-prompts
make llm-validate
```

### 4.2 调用适配层
```bash
make llm-call
make llm-retry
```

### 4.3 Skill 生成与校验
```bash
make skills-sample
make skills-validate-sample
python3 scripts/validation/validate_skill_bundle.py \
  --skill-dir scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001
```

说明：
- `validate_openclaw_skill.py` 负责 bundle/frontmatter/schema 一致性校验。
- `validate_skill_bundle.py` 负责执行前预检：locator 可解析性、高风险动作、低置信步骤、低复现度、敏感窗口识别、目标 App 白名单。
- 目标 App 白名单默认从 skill 自身声明的 app 集合推导：顶层 context、completionCriteria，以及步骤里显式声明的 bundle / semantic target app。
- 统一安全策略位于 `config/safety-rules.yaml`；如需做项目级放行，请优先在其中配置 `App / task / skill` 白名单，而不是直接改代码。
- App 技能列表会直接展示预检状态；`需老师确认` 的技能不会进入学生模式自动执行。

### 4.4 通过 OpenClaw Runner 执行已生成 skill
```bash
make openclaw ARGS="--skill-dir scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001 --teacher-confirmed --json-result"
```

说明：
- 该入口会通过 `OpenClawRunner` 拉起 OpenClaw CLI / gateway 子进程。
- `SEM-501` 起 OpenClaw gateway 已固定为 semantic-only，外部调用不再需要也不能通过开关恢复坐标执行；历史 `--semantic-only` 仅保留兼容解析，不影响实际行为。
- 若 skill 命中 `requiresTeacherConfirmation` / 高风险 / 低置信安全门，必须显式传入 `--teacher-confirmed`。
- 如需临时验证另一套风控规则，可额外传入 `--safety-rules /abs/path/to/safety-rules.yaml`。
- 执行日志会写入 `data/logs/{yyyy-mm-dd}/{sessionId}-openclaw.log`。
- 若执行失败，会返回结构化 `errorCode/stdout/stderr/exitCode/preflight` 结果，便于审阅与排障。

### 4.5 Learning Bundle 导出、校验与恢复
适用场景：
- 迁移 `turn / evidence / signal / rule / profile / audit`
- 交付给外部 worker 做离线分析
- 在新工作区恢复学习事实源并重新构建 profile

导出：

```bash
make learning-bundle-export ARGS="--learning-root data/learning --preferences-root data/preferences --output /tmp/openstaff-learning-bundle --session-id session-001 --json"
```

校验：

```bash
make learning-bundle-verify ARGS="--bundle /tmp/openstaff-learning-bundle --json"
```

恢复前预览：

```bash
make learning-bundle-restore ARGS="--bundle /tmp/openstaff-learning-bundle --restore-workspace-root /tmp/openstaff-restored --json"
```

执行恢复：

```bash
make learning-bundle-restore ARGS="--bundle /tmp/openstaff-learning-bundle --restore-workspace-root /tmp/openstaff-restored --apply --json"
```

说明：
- `make learning-bundle-restore` 默认只做 dry-run 预览，不会直接写盘。
- 若目标路径已有同名文件，默认会报 `conflict`；只有显式加 `--overwrite` 才允许覆盖。
- 恢复完成后，可继续执行：

```bash
make preference-profile ARGS="--preferences-root /tmp/openstaff-restored/data/preferences --rebuild --json"
```

### 4.6 语义动作审核工作流（Teacher Confirmation）
当 `semantic action` 命中低置信或高风险策略时，`OpenStaffReplayVerifyCLI` 会在真正执行前进入审核门。

示例：

```bash
make replay-verify ARGS="--semantic-action-db data/semantic-actions/semantic-actions.sqlite --action-id semantic-action-turn-001 --snapshot core/executor/examples/replay-environment.sample.json --dry-run --json"
```

若需要老师放行：

```bash
make replay-verify ARGS="--semantic-action-db data/semantic-actions/semantic-actions.sqlite --action-id semantic-action-turn-001 --snapshot core/executor/examples/replay-environment.sample.json --teacher-confirmed --teacher-confirmation-root data/semantic-actions/teacher-confirmations --json"
```

如需临时调整审核阈值与策略：

```bash
make replay-verify ARGS="--semantic-action-db data/semantic-actions/semantic-actions.sqlite --action-id semantic-action-turn-001 --snapshot core/executor/examples/replay-environment.sample.json --teacher-confirmation-policy config/semantic-teacher-confirmation.example.json --json"
```

说明：
- 默认会对 `manual_review_required`、低于阈值的 selector、`switch_app`、`drag`、批量 `type` 触发审核。
- 未传 `--teacher-confirmed` 时，会返回 `SEM302-TEACHER-CONFIRMATION-REQUIRED`，并在输出里展示候选 selector、上下文要求和断言摘要。
- 审核结果会写进 `action_execution_logs.result_json.teacherConfirmation`。
- 若配置了 `--teacher-confirmation-root`，还会额外落 JSON artifact 到 `teacher-confirmations/{date}/{sessionId}/`，便于后续学习链路引用。
- 如需把执行日志归到特定环境，可额外传 `--environment dev|staging|prod`；该字段会直接写进 `action_execution_logs.result_json.environment`，供观测看板聚合。

### 4.7 语义执行观测看板（SEM-303）
当 `semantic_actions` 已有执行日志后，可直接生成迁移期质量看板。

单环境默认库：

```bash
make semantic-observability-dashboard
```

如果需要按阈值直接 fail：

```bash
make semantic-observability-gates
```

多环境聚合示例：

```bash
python3 scripts/observability/build_semantic_action_dashboard.py \
  --source dev=/tmp/openstaff-dev/semantic-actions.sqlite \
  --source staging=/tmp/openstaff-staging/semantic-actions.sqlite \
  --source prod=/tmp/openstaff-prod/semantic-actions.sqlite \
  --check-gates
```

说明：
- 默认产物会写到 `data/reports/semantic-action-observability/metrics-summary.json` 与 `data/reports/semantic-action-observability/dashboard.md`。
- 看板会按 `dev / staging / prod` 展示 `selectorHitRate / fallbackLayerDistribution / interceptRate / replaySuccessRate / manualConfirmationRate`。
- 只要出现 `SEM202-CONTEXT-MISMATCH`、`SEM203-ASSERTION-FAILED` 或 `SEM201-COORDINATE-FALLBACK-DISALLOWED`，摘要就会自动生成“误触发风险”告警。
- 若当前只有 dry-run 日志，`replaySuccessRate` 会退回用全量样本计算，并在摘要里标明 `mode=all_runs`。

### 4.8 语义动作端到端基准（SEM-401）
当需要验证语义执行链路是否仍覆盖核心高风险场景时，可直接运行冻结的端到端 benchmark corpus。

推荐入口：

```bash
make benchmark-semantic-e2e
```

也可以输出到临时目录做 smoke test：

```bash
python3 scripts/benchmarks/run_semantic_action_e2e_benchmark.py \
  --benchmark-root /tmp/openstaff-semantic-action-e2e \
  --report /tmp/openstaff-semantic-action-e2e/manifest.json
```

说明：
- 当前 corpus 固定 `8` 条 case，覆盖 `switch_app / focus_window / type / shortcut / drag(window_move) / drag(list_reorder) / multi_display / browser_url`。
- runner 会自动物化 `semantic_actions` SQLite，并驱动 `OpenStaffReplayVerifyCLI` 对 committed snapshot 做 dry-run 回归，不依赖实时桌面环境。
- 每条 case 都会产出 `source-record.json`、`case-report.json` 与 `attempts/attempt-XX/{semantic-actions.sqlite,cli-report.json,execution-log.json,attempt-report.json}`，便于复现失败原因。
- 如需降低环境抖动，可传 `--max-retries <n>` 启用固定次数 flake 重跑；如需只跑部分 case，可配合 `--case-id` 或 `--case-limit`。
- 如需做 `SEM-402` 压力回归，可传 `--repeat-count 3`，或直接执行 `make benchmark-semantic-e2e-preflight`，它会在 benchmark 结束后继续跑 `metrics-v0.json` gate。
- 默认环境标签为 `benchmark`，会直接写入 `action_execution_logs.result_json.environment`，方便后续观测与聚合。

## 5. 发布前检查

### 5.1 执行发布回归
```bash
make release-regression
```

### 5.2 一键执行发布预检
```bash
make release-preflight
```

说明：
- 该入口会依次执行：`SEM-003` 坐标执行静态守门、原始事件校验、知识条目校验、LLM 样例校验、skill 映射、`validate_openclaw_skill.py`、`validate_skill_bundle.py`、replay verify sample、personal desktop benchmark、semantic action e2e benchmark、semantic action e2e metrics gate、personal preference benchmark、preference metrics gate。
- `data/raw-events` 采用 compat 模式校验，当前会把历史键盘事件缺失 `keyboard.isSensitiveInput` 记为告警而非失败。
- `data/knowledge` 会对缺失 `target` 的历史知识条目输出告警，提醒 replay/自动执行能力可能退化。
- `validate_skill_bundle.py` 默认允许 `needs_teacher_confirmation` 通过，以便发布前看到安全门提示；若要做“必须可自动执行”的 CI 门禁，可加 `--require-auto-runnable`。
- 如需单独跑 `SEM-003` 门禁，可执行 `make validate-semantic-guard`；测试 fixture 可通过 `ARGS="--allow-dir tests/fixtures"` 添加白名单目录。
- `preference metrics gate` 会按 `data/benchmarks/personal-preference/metrics-v0.json` 中冻结的 v0 阈值直接 fail；其中 `unsafeAutoExecutionRegression > 0`、`capturePolicyViolationCount > 0` 等高风险回归会在发布前被拦截。
- 可通过 `ARGS` 透传预编译 CLI 路径，例如：

```bash
make release-preflight ARGS="--openclaw-executable apps/macos/.build/debug/OpenStaffOpenClawCLI --replay-verify-executable apps/macos/.build/debug/OpenStaffReplayVerifyCLI --assist-executable apps/macos/.build/debug/OpenStaffAssistCLI --student-executable apps/macos/.build/debug/OpenStaffStudentCLI --review-executable apps/macos/.build/debug/OpenStaffExecutionReviewCLI"
```

如需单独复现偏好门禁，可运行：

```bash
make benchmark-preference-preflight
```

如需单独复现 `SEM-401` 语义动作回归，可运行：

```bash
make benchmark-semantic-e2e
```

如需单独复现 `SEM-402` 性能与鲁棒性门禁，可运行：

```bash
make benchmark-semantic-e2e-preflight
```

### 5.3 Semantic-Only 切流检查（SEM-501）
推荐在 staging 与 prod 切流时按以下顺序执行：

1. 跑 `make release-preflight`，确认基础门禁、语义 benchmark 与 gate 全绿。
2. 对目标环境的 `semantic_actions` SQLite 跑一次 `make semantic-observability-gates`，或用多环境聚合命令同时检查 `staging / prod`。
3. 对高风险 skill 抽样执行 `make openclaw ARGS="--skill-dir ... --teacher-confirmed --json-result"`，确认不会再出现坐标执行成功路径。
4. 切流后连续观察 `7` 天核心指标；若出现异常，只允许回滚版本或收紧人工确认策略，不允许恢复坐标执行。

详细步骤见 `docs/semantic-only-cutover-runbook.md`。

## 6. 常见问题

### 6.1 提示权限不足
- 采集功能依赖 macOS 辅助功能权限。
- 请在系统设置中授权后重试。

### 6.2 Swift 构建失败
- 检查 `xcode-select -p` 指向有效开发工具链。
- 保证当前用户对项目目录和缓存目录有写权限。

### 6.3 回归步骤失败
- 先运行 `make build` 确保必需 CLI 已编译。
- 查看回归输出目录内的错误日志定位失败原因。

## 7. 进阶建议

1. 使用真实采集会话替换样例知识条目，观察模型效果变化。  
2. 在 `config/release.example.yaml` 中细化 `safety.blockedActionKeywords`。  
3. 将 `make release-preflight` 接入 CI，作为发布门禁。  
