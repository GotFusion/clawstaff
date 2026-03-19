# OpenStaff 项目方案与实现进展

## 1. 项目目标

OpenStaff 的定位是“老师-学生”式个人助理：
- 老师：真实用户。
- 学生：OpenStaff 软件。

学生通过观察老师在 macOS 上的操作行为进行学习，沉淀为结构化知识，再在不同模式下辅助或自主执行任务。

---

## 2. 三种核心模式

### 2.1 教学模式（Learning）
- 老师主导操作电脑。
- 学生被动观察并记录行为事件（点击、上下文、步骤顺序）。
- 自动完成分类、分析、总结，形成知识条目。

### 2.2 辅助模式（Assist）
- 老师继续主导操作。
- 学生基于历史知识预测下一步动作。
- 学生发起确认：“是否需要我执行下一步？”
- 老师同意后，学生执行动作并记录反馈。

### 2.3 学生模式（Autonomous）
- 学生根据学习到的知识自主执行任务。
- 执行后输出过程日志与结果摘要供老师审阅。

---

## 3. 最小可行能力（MVP）

优先实现顺序：
1. **操作采集**：记录屏幕点击与上下文信息。
2. **知识格式化存储**：将采集结果写入统一格式文件。
3. **知识解析脚本**：通过 ChatGPT 提示词把知识文件解析为结构化步骤。
4. **OpenClaw skill 转换**：将结构化步骤映射为 OpenClaw skills。
5. **执行闭环**：OpenClaw 消费 skills 并回传执行日志。

---

## 4. 技术架构草案

### 4.1 分层
- 应用层（GUI）：模式切换、确认交互、日志审阅。
- 核心层（Core）：采集、知识、编排、执行、存储。
- 脚本层（Scripts）：LLM 解析、skill 生成、批量工具。
- 集成层（Vendor）：对接 `vendors/openclaw`。

### 4.2 数据流
1. Capture 采集事件。
2. Knowledge 归档成知识条目。
3. Orchestrator 按模式调度。
4. Scripts/LLM 进行知识理解与结构化。
5. Scripts/Skills 产出 OpenClaw skills。
6. Executor 执行并记录日志。
7. Storage 持久化并供 GUI 展示。

---

## 5. 知识文件建议格式（草案）

建议采用 `JSONL` 便于流式追加与审计，单行一条事件或步骤，例如：

- `schemaVersion`：事件 schema 版本（如 `capture.raw.v0`）。
- `eventId`：事件唯一 ID。
- `sessionId`：学习会话 ID。
- `timestamp`：事件时间。
- `contextSnapshot.appName`：应用名。
- `contextSnapshot.windowTitle`：窗口标题。
- `action`：点击/输入/快捷键等动作。
- `target`：操作目标（v0 使用坐标）。
- `confidence`：标准化置信度（`NormalizedEvent`）。

详细字段定义见 `core/capture/event-model-v0.md` 与 `core/capture/schemas/*.schema.json`。

---

## 6. 与 ChatGPT / OpenClaw 协作方案

1. 将知识文件输入提示词模板。
2. 让 ChatGPT 解析为标准任务步骤（含前置条件、执行顺序、失败处理）。
3. 将解析结果转为 OpenClaw skill bundle（`SKILL.md` + `openstaff-skill.json provenance`）。
4. 在辅助/学生模式触发 OpenClaw 执行。
5. 回收日志并反馈到知识库，形成“学习-执行-再学习”闭环。

---

## 7. 风险与约束

- **隐私风险**：屏幕与输入采集需明确权限、脱敏策略与本地存储优先。
- **误操作风险**：辅助/学生模式必须保留确认与紧急停止机制。
- **知识漂移**：软件更新导致 UI 变化时，旧知识可能失效，需要版本化。
- **模型不确定性**：LLM 解析结果需校验、回退与人工审阅机制。

---

## 8. 当前实现进展（本次）

### 已完成
- 完成项目目录结构初始化。
- 为核心目录与子目录补充职责说明文档（README）。
- 在 `docs/` 建立本方案文档，记录目标、架构、MVP 与风险。
- 完成阶段 0 技术栈 ADR：`docs/adr/ADR-0000-tech-stack.md`。
- 完成编码规范文档：`docs/coding-conventions.md`。
- 新增 `core/contracts/` 共享契约目录与 `data/` 本地数据目录基线。
- 在 `apps/macos` 落地 SwiftUI 最小空应用，并提供统一启动命令 `make dev`。
- 完成阶段 1.1 事件模型定义：`RawEvent` / `ContextSnapshot` / `NormalizedEvent`。
- 新增事件 schema 文档、JSON Schema、样例 JSONL 与 `ADR-0001-event-schema.md`。
- 完成阶段 1.2 采集引擎最小实现：`OpenStaffCaptureCLI`（权限检查、全局点击监听、上下文抓取、本地队列）。
- 完成阶段 1.3 事件落盘与轮转：`RawEventFileSink`（JSONL 追加写盘、按日期+session 分片、按大小/时间轮转、异常中断恢复追加）。
- 新增存储策略 ADR：`docs/adr/ADR-0002-storage-strategy.md`。
- 完成阶段 2.1 任务切片器：`OpenStaffTaskSlicerCLI`（按空闲间隔 + 上下文切换切片，输出 `TaskChunk` 并生成稳定 `task_id`）。
- 完成阶段 2.2 知识条目格式定义：`KnowledgeItem` schema + `OpenStaffKnowledgeBuilderCLI`（`TaskChunk -> KnowledgeItem` 映射落盘）。
- 完成阶段 2.3 自动总结初版（无 LLM）：`KnowledgeSummaryGenerator`（规则摘要写入 `KnowledgeItem.summary`）。
- 完成阶段 3.1 提示词模板系统：新增系统/任务提示词模板、LLM 输出 schema、提示词渲染脚本与 JSON 严格校验脚本（`scripts/llm/*`）。
- 完成阶段 3.2 ChatGPT 调用适配层：新增 `chatgpt_adapter.py`（重试、超时、限流、请求摘要日志、错误报告），并提供离线 `text` provider 以支持无 API 场景验证。
- 完成阶段 3.3 OpenClaw skill 映射器：新增 `openclaw_skill_mapper.py` 与 `validate_openclaw_skill.py`，实现 `KnowledgeItem + LLM` 到 OpenClaw `SKILL.md` 的映射，并支持字段校验与 fallback；阶段 8.1 已将其升级为带 provenance 的 `openstaff.openclaw-skill.v1` 审计产物。
- 完成阶段 4.1 模式状态机：新增 `ModeStateMachine`、`OrchestratorContracts`、`OpenStaffOrchestratorCLI`，实现三模式合法切换校验、切换守卫与能力白名单，非法切换会拒绝并输出结构化日志。
- 完成阶段 4.2 辅助模式闭环：新增 `AssistModeLoop` + `AssistActionExecutor` + `AssistLoopLogWriter` + `OpenStaffAssistCLI`，实现“规则预测 -> 弹窗确认 -> 执行 -> 回写日志”最小闭环。
- 完成阶段 4.3 学生模式闭环：新增 `StudentModeLoop` + `StudentSkillExecutor` + `StudentLoopLogWriter` + `StudentReviewReportWriter` + `OpenStaffStudentCLI`，实现“目标输入 -> 自动规划 -> 技能执行 -> 结构化审阅报告”最小闭环。
- 完成阶段 5.1 主界面与模式切换：升级 `OpenStaffApp` 为 Dashboard，提供三模式切换组件（复用状态机守卫）、当前状态卡片、权限状态（辅助功能与数据目录可写性）及最近任务列表（从 `data/logs` + `data/knowledge` 汇总）。
- 完成阶段 5.2 学习记录与知识浏览：新增学习记录浏览区，支持会话列表、会话任务列表、任务详情与知识条目查看（含目标/摘要/约束/步骤）。
- 完成阶段 5.3 审阅与反馈：新增执行日志审阅区，支持日志详情查看与老师反馈入口（通过/驳回/修正），反馈落盘到 `data/feedback/{yyyy-mm-dd}/*.jsonl`。
- 完成阶段 6.1 安全控制：执行层新增高风险关键词+正则拦截规则，支持紧急停止状态拦截；GUI 新增紧急停止按钮与全局快捷键（`Cmd+Shift+.`）。
- 完成阶段 6.2 测试体系落地（补强）：在原有 schema/映射链路测试基础上，新增 `test_validate_openclaw_skill.py`、`test_task_slicer_cli.py`、`test_three_mode_cli_roundtrip.py`，把覆盖扩展到 `SKILL.md` 校验器、`OpenStaffTaskSlicerCLI` 切片策略，以及 `Orchestrator/Assist/Student` 三模式真实 CLI 闭环；统一入口仍为 `scripts/tests/run_all.py` 与 `make test*`。
- 完成阶段 6.3 发布前检查：补齐配置模板（`config/release.example.yaml`）与配置文档；新增 `scripts/release/run_regression.py`（发布回归与 JSON 报告）；新增 `make release-regression` / `make release-preflight` 一键入口。
- 完成阶段 7.1 Semantic Target 数据模型：新增 `SemanticTarget` 共享契约、capture/knowledge schema 与 ADR，并让 `KnowledgeItemBuilder` 为点击步骤自动写入 `coordinateFallback` 候选，同时保持旧 `capture.normalized.v0` / `knowledge.item.v0` 数据兼容解码。
- 完成阶段 7.2 采集上下文增强：CLI 与教学模式采集统一写出共享 `RawEvent`，补充窗口稳定签名、焦点元素可读属性、轻量截图锚点指纹和结构化降级错误码；高敏感键盘输入在安全文本场景下会自动脱敏。
- 完成阶段 7.3 语义定位解析与回放验证器：新增 `SemanticTargetResolver`、`ReplayVerifier` 与 `OpenStaffReplayVerifyCLI`，支持 `axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback` 的 dry-run 解析、离线 snapshot/实时前台窗口双输入，以及窗口不匹配、元素缺失、文本锚点变化、仅剩坐标回退等结构化结果输出。
- 完成阶段 8.1 OpenClaw companion boundary：新增 `docs/adr/ADR-0007-openclaw-companion-boundary.md`，明确 OpenStaff/OpenClaw 职责切分；`scripts/skills/openclaw_skill_mapper.py`、skill schema 与 validator 升级为 `openstaff.openclaw-skill.v1`，统一写出 `knowledge/sourceTrace/skillBuild/stepMappings` provenance，并在 `SKILL.md` 中保留关键审计摘要。
- 完成阶段 9.1 基于历史知识检索的下一步预测：新增 `AssistPredictionContracts`、`AssistKnowledgeRetriever`、`RetrievalBasedAssistPredictor`，辅助模式改为按 `app / window / goal / recent steps / 历史偏好` 检索相似知识并输出来源证据；`OpenStaffAssistCLI` 现支持知识目录输入与推荐来源展示。
- 完成阶段 9.2 Skill 漂移检测与修复建议：新增 `core/repair/SkillDriftDetector.swift`、`core/repair/SkillRepairPlanner.swift` 与 `ADR-0009`，把 replay dry-run 的失败原因提升为 `UI 文案变化 / 元素位置变化 / 窗口结构变化 / App 版本级变化` 等漂移类型，并在 GUI 技能详情里提供“检测漂移”“更新 skill / 更新 locator / 重新示教”的修复入口；`OpenStaffReplayVerifyCLI` 也支持 `--skill-dir` 输出结构化 drift report 与 repair plan。
- 完成阶段 9.3 审阅台增强：新增 `core/storage/ExecutionReviewStore.swift` 统一装配执行日志/老师反馈/学生审阅报告/skill/knowledge 关联关系；GUI 审阅区现可直接展示“老师原始步骤 / 当前 skill 步骤 / 本次实际执行结果”三栏对照，并把反馈动作升级为“通过 / 驳回 / 修复 locator / 重新示教”，后两者会同步落盘 repair request，形成失败审阅闭环。
- 完成阶段 8.2 OpenClaw Runner 适配层：新增 `core/contracts/OpenClawExecutionContracts.swift`、`core/executor/OpenClawRunner.swift` 与 `apps/macos/Sources/OpenStaffOpenClawCLI/*`，实现 OpenClaw CLI / gateway 子进程调用、stdout/stderr/exit code 捕获、`data/logs/{date}/{sessionId}-openclaw.log` 结构化日志回写，以及 `OpenClawExecutionReview` 结果产出；3 条 sample skill 已通过真实子进程链路联调。
- 完成阶段 8.3 Skill 预检与安全门：新增 `core/executor/SkillPreflightValidator.swift`、`scripts/validation/validate_skill_bundle.py` 与 `docs/adr/ADR-0008-skill-preflight-and-repair.md`，统一执行前 schema/locator/高风险/目标 App 白名单检查；GUI 技能列表可直接展示预检摘要与失败原因，学生模式自动执行仅允许 `preflight=passed` 的技能直跑，`needs_teacher_confirmation` 技能必须经老师审核通过后才能手动执行；`OpenStaffOpenClawCLI` 也已接入 `teacherConfirmed` 安全门。
- 完成阶段 10.1 Personal Desktop Benchmark：新增 `data/benchmarks/personal-desktop/` 基线 corpus、`docs/personal-benchmark-spec.md`、`scripts/benchmarks/run_personal_desktop_benchmark.py` 与 `tests/integration/test_personal_desktop_benchmark.py`，冻结 22 条真实个人桌面任务（4 类）并将其期望 `preflight/execution` 结果固化为可回归基线；同时增强 `openclaw_skill_mapper.py`，当旧版 `KnowledgeItem` 仅在 instruction 中保留坐标时，会自动回填 `coordinateFallback`，避免 benchmark 因缺失 provenance 坐标被误判。
- 完成阶段 10.2 验证脚本与发布门禁：新增 `scripts/validation/validate_raw_event_logs.py`、`scripts/validation/validate_knowledge_items.py`、`scripts/validation/run_replay_verify_check.py` 与 `scripts/validation/README.md`，补齐原始事件/知识条目/replay verify 的标准化校验入口；`scripts/release/run_regression.py` 现已将 `raw-events`、`knowledge`、LLM 样例、skill bundle preflight、replay verify、personal benchmark 与测试套件统一接入发布门禁；`Makefile` 额外提供 `validate-raw-events`、`validate-knowledge`、`validate-replay-sample`，并允许 `release-regression/release-preflight` 透传 `ARGS`。
- 完成阶段 10.3 安全策略二次升级：新增 `config/safety-rules.yaml` 与 `core/executor/SafetyPolicyEvaluator.swift`，将 `低置信 + 高风险 + 低复现度` 默认自动执行阻断、支付/系统设置/密码管理器/隐私权限弹窗识别，以及 `App / task / skill` 三层自动执行白名单统一收敛到同一套策略；`SkillPreflightValidator`、`OpenClawRunner` 与 `scripts/validation/validate_skill_bundle.py` 已共享该策略，`OpenStaffOpenClawCLI` 也支持通过 `--safety-rules` 注入自定义规则文件。
- 完成阶段 11.0.2 Quick Feedback Bar：新增 `TeacherQuickFeedbackContracts`、统一 7 个快评动作与 `Cmd+1...Cmd+7` 快捷键定义；首页与“状态工作台 -> 审阅与反馈”复用同一套 `Quick Feedback Bar`，所有快评均落盘为带标准化 `teacherReview` evidence 的 `teacher.feedback.v2` 记录，`修 locator` / `重示教` 继续联动 repair request。
- 完成阶段 11.0.3 Privacy / Exclusion Panel：新增 `Privacy / Exclusion Panel` 到状态工作台，支持 app 排除名单、窗口标题排除规则、`15` 分钟临时暂停与敏感场景自动静默；新增 `config/learning-privacy.example.yaml`、`core/learning/SensitiveScenePolicy.swift` 与 `docs/ux/learning-privacy-controls-v0.md`，并将排除 / 静默规则真正接入 learning capture 停启链路与回归测试。
- 完成阶段 11.1 `InteractionTurn` v0 基线：新增 `core/contracts/InteractionTurnContracts.swift`、`core/learning/InteractionTurnBuilder.swift`、`core/learning/schemas/interaction-turn.schema.json` 与 `core/learning/examples/interaction-turns/*.json`；新增 `scripts/learning/build_interaction_turns.py`，可把现有 benchmark + student review 样本批量回填到 `data/learning/turns/{date}/{sessionId}/{turnId}.json`。当前仓库已稳定写出 `129` 条 turn（teaching `65`、student `64`），assist 先以 example fixture 固化 schema，等待真实 assist log 样本入库后再补历史回填。
- 完成阶段 11.1 `NextStateEvidence` v0 基线：新增 `core/contracts/NextStateEvidenceContracts.swift`、`core/learning/NextStateEvidenceBuilder.swift`、`core/learning/schemas/next-state-evidence.schema.json` 与 `core/learning/examples/next-state-evidence/*.jsonl`；新增 `scripts/learning/build_next_state_evidence.py`，可从已回填的 `InteractionTurn` 工件继续批量写出 `data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`。当前脚本可稳定产出 `189` 条 evidence，并让 `129` 条 turn 至少关联 `1` 条 evidence。
- 完成阶段 11.2.1 `PreferenceSignal` v0 契约：新增 `core/contracts/PreferenceSignalContracts.swift`、`core/learning/preference-signal-v0.md`、`core/learning/schemas/preference-signal.schema.json` 与 `core/learning/examples/preference-signals/*.json`，明确 outcome / procedure / locator / style / risk / repair 六类信号、`global/app/taskFamily/skillFamily/windowPattern` 五层作用域，以及 `v0` 默认只优先激活 `global / app / taskFamily` 的策略；`OpenStaffAppTests` 也补上了 directive payload 与 scope 激活规则回归。
- 完成阶段 11.2.2 规则优先提炼器 v0：新增 `core/learning/RuleBasedPreferenceSignalExtractor.swift`，可从 `teacherReview / replayVerify / driftDetection / benchmarkResult / safety block` 直接提炼 `outcome / procedure / locator / style / risk / repair` 基础信号，并支持把同一 turn 的信号落盘到 `data/preferences/signals/{date}/{sessionId}/{turnId}.json`；同时补齐 `core/learning/examples/preference-signals-rule-based/*.json` 和 `OpenStaffAppTests` 回归，其中历史样本覆盖测试已验证前 `30` 条带结构化反馈的真实样本里至少有 `18` 条能提炼出 `1` 条以上有效 signal。
- 完成阶段 11.2.3 LLM 辅助 hint 提炼器 v1 基线：新增 `scripts/learning/extract_preference_signals.py`、`scripts/learning/prompts/preference-hint-extractor.md`、`scripts/learning/schemas/preference-extraction-output.schema.json` 与 `scripts/learning/README.md`，固定消费 `actionSummary / nextStateSummary / nextStateRole / teacherNote` 四段输入，并支持 `provider=openai`、离线 `heuristic/mock`、`3-vote` 多数接受、schema 校验、`1-3` 句可执行 hint 校验、低置信结果自动落到 `data/preferences/needs-review/`；同时新增 Python unit/integration 回归，覆盖合法输出、非法 JSON 降级、accepted 报告和 `needs_review` 路径。联机 `OpenAI` 成功率指标仍待真实 API 环境补跑。
- 完成阶段 11.3 偏好记忆层基线：新增 `core/contracts/PreferenceRuleContracts.swift`、`core/contracts/PreferenceProfileContracts.swift`、`core/storage/PreferenceMemoryStore.swift`、`core/learning/preference-rule-v0.md`、`core/learning/preference-profile-v0.md` 与 `docs/adr/ADR-0014-preference-memory-store.md`，把 `signals / rules / profiles / audit` 收敛到统一文件事实源；store 现支持按 `app / task family / skill family` 查询 active 或 inactive 规则、回链 source signal、写入 `latest` profile pointer，并通过 `OpenStaffAppTests` 覆盖规则存储、生命周期变更、审计和 profile snapshot 读取。
- 完成阶段 11.3.3 / 11.3.5 `PreferenceProfile` 形成链路：新增 `core/learning/PreferenceProfileBuilder.swift`、`core/learning/examples/preference-profiles/*.json` 与 `OpenStaffPreferenceProfileCLI`，可把 active rules 按 `assist / skill / repair / review / planner` 五段聚合成稳定快照、记录 `sourceRuleIds / previousProfileVersion`，并支持通过 CLI 查看、重建和持久化最新 profile snapshot。
- 完成阶段 11.4.1 Assist 偏好重排先落地：新增 `core/contracts/AssistPreferenceContracts.swift`、`core/orchestrator/PreferenceAwareAssistPredictor.swift` 与 `core/orchestrator/assist-preference-rerank-v1.md`，在不改 `AssistKnowledgeRetriever` 的前提下，对 retrieval 结果追加 `step / app / risk` 三类偏好权重；`OpenStaffAssistCLI` 与 GUI assist workflow 现会自动读取 `data/preferences` 最新 profile 并回退到原 retrieval 行为，输出中同步附带 `appliedRuleIds`、候选压低原因与结构化 `preferenceDecision`。
- 完成阶段 11.4.2 Skill mapper 偏好装配：`scripts/skills/openclaw_skill_mapper.py` 现支持读取最新 `PreferenceProfile` 或显式 profile 路径，对 skill 生成过程装配 `nativeAction / guiAction`、GUI locator 固定顺序、native route 优先级、style / note / risk 偏好，并把命中的规则摘要写入 `SKILL.md` metadata 与 `openstaff-skill.json` provenance；`IntegratedModeWorkflows` 调 mapper 时也会自动传入 `data/preferences`。
- 完成阶段 11.4.3 Repair planner 偏好装配：新增 `core/repair/PreferenceAwareSkillRepairPlanner.swift`，在现有 drift heuristic 之上按 `PreferenceProfile.repairPreferences` 调整 `updateSkillLocator / relocalize / reteachCurrentStep` 的优先级，并把 `appliedRuleIds`、动作级 `preferenceReason` 与结构化 `preferenceDecision` 一起写入 repair plan；GUI 技能详情页与 `OpenStaffReplayVerifyCLI --skill-dir` 现都会自动读取最新 `data/preferences` profile 生成可解释 repair 建议。
- 完成阶段 11.4.4 Review 建议偏好装配：`ExecutionReviewStore` 现会自动读取最新 `PreferenceProfile.reviewPreferences`，为审阅台生成带 `reviewSuggestions / reviewPreferenceDecision` 的偏好化建议结果；GUI “审阅与反馈” 面板会展示“推荐动作 / 推荐短备注 / 规则来源”，并能解释诸如“你通常更倾向于先修 locator”之类的个体偏好命中，同时保留固定 `Quick Feedback Bar` 7 个动作与原快捷键不变。
- 完成阶段 11.4.5 Student planner 偏好装配：新增 `core/contracts/PlanningPreferenceContracts.swift` 与 `core/orchestrator/PreferenceAwareStudentPlanner.swift`，可按 `PreferenceProfile.plannerPreferences` 调整 student 候选知识条目排序、区分 `conservative / assertive` 执行姿态，并把失败后的 `repair / re-teach` 偏好写入 `StudentExecutionPlan.preferenceDecision`；`OpenStaffStudentCLI` 与 GUI student workflow 仍默认回退 `rule-v0`，只有在显式 feature flag + benchmark-safe attestation 同时满足时才会启用。
- 完成阶段 11.4.6 `PolicyAssemblyDecision` 落盘：新增 `core/contracts/PolicyAssemblyDecisionContracts.swift`、`core/storage/PolicyAssemblyDecisionStore.swift` 与对应 CLI / GUI / Python skill mapper 接线；在 `OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG=1` 时，assist / student / skill generation / repair 会统一写入 `data/preferences/assembly/{date}/{module}/{sessionId}/{decisionId}.json`，记录 `appliedRuleIds / suppressedRuleIds / finalWeights / finalDecisionSummary`，用于回答“这次为什么这样做”。
- 完成阶段 11.5.1 偏好学习评测层 benchmark 基线：新增 `data/benchmarks/personal-preference/catalog.json`、`data/benchmarks/personal-preference/manifest.json`、`docs/personal-preference-benchmark-spec.md` 与 `scripts/benchmarks/run_personal_preference_benchmark.py`，固定 `24` 条 `style / procedure / risk / repair` case（`12` 条真实锚点 + `12` 条扰动样本），并通过新增 `OpenStaffExecutionReviewCLI` 把 review 建议链路也纳入 benchmark；当前基线 `personal-preference-v20260319` 已稳定跑通 `24 / 24`，可输出按模块与类别聚合的 `preferenceMatchRate` 汇总。
- 完成阶段 11.5.2 偏好学习指标与门槛固化：新增 `scripts/benchmarks/aggregate_preference_metrics.py`、`docs/metrics/preference-learning-metrics.md`、`data/benchmarks/personal-preference/metrics-v0.json` 与 `data/benchmarks/personal-preference/metrics-summary.json`，把 `assistAcceptanceRate / repairPathHitRate / teacherOverrideRate / unsafeAutoExecutionRegression / quickFeedbackCompletionRate / medianFeedbackLatencySeconds / capturePolicyViolationCount` 收敛为统一 v0 摘要；benchmark runner 现也会为每条 case 记录执行时延，并在每次 run 结束后自动生成指标摘要与 gate 结果。
- 完成阶段 11.5.3 偏好学习发布门禁接线：`scripts/release/run_regression.py` 现已把 `benchmark-personal-preference` 与 `benchmark-personal-preference-gates` 接到 `release-preflight`，并支持按 `metrics-v0.json` 对关键指标统一判定；同时新增 `make benchmark-preference-gates` / `make benchmark-preference-preflight`，让高风险回归（如 `unsafeAutoExecutionRegression > 0`、`capturePolicyViolationCount > 0`、`teacherOverrideRate` 超过允许恶化幅度）可在发布前直接拦截。
- 完成阶段 11.6.1 偏好治理策略固化：新增 `config/preference-governance.yaml` 与 `core/learning/PreferencePromotionPolicy.swift`，把 `low / medium / high / critical` 风险分级、signal type 局部 scope、过期窗口和 conflict priority 统一配置化；`PreferenceRulePromoter`、`PreferenceConflictResolver` 与 `PreferenceMemoryStore` 现都会默认吃这套治理策略，promoted rule 还会额外落 `governance` 元数据（`autoExecutionPolicy / expiresAfterDays / expiresAt / allowedScopeLevels`），为后续审计、回滚和漂移监控提供稳定事实源。
- 完成阶段 11.6.2 / 11.6.3 偏好审计与回滚闭环：新增 `core/storage/PreferenceAuditLogStore.swift` 与 `core/learning/PreferenceRollbackService.swift`，把规则创建、晋升、覆盖、撤销、回滚统一落到 `data/preferences/audit/{date}.jsonl`，并固定携带 `actor + source` 元数据；`OpenStaffPreferenceProfileCLI` 现支持 `--audit`、`--rollback-rule`、`--rollback-profile-version`、`--dry-run` 与 `--persist`，可直接预览或执行单条规则撤销、历史 snapshot 回滚，并在回滚后立即重建最新 `PreferenceProfileSnapshot`。新增 Swift / Python 回归已覆盖 dry-run、不同行为状态切换与 rollback audit summary。
- 完成阶段 11.6.3 / 11.6.4 偏好漂移监控：新增 `core/learning/PreferenceDriftMonitor.swift`、`core/learning/preference-drift-monitor-v0.md` 与 `docs/adr/ADR-0019-preference-drift-monitoring.md`，把 active rules、audit 与 `PolicyAssemblyDecisionStore` 的装配日志接成统一 drift report；第一版已覆盖 `30` 天未命中、最近 `10` 次相关装配 override 超过 `50%`、最近 `3` 次老师明确驳回，以及 style churn / high-risk mismatch 等 finding。`OpenStaffPreferenceProfileCLI` 现支持 `--drift-monitor` 与 `--drift-profile-version`，可直接输出结构化 drift findings；新增 Swift / Python 回归同时覆盖 usage-based/no-assembly 两类路径。
- 新增用户使用说明书 `docs/user-manual.md`，覆盖教学->辅助->学生三模式日常运行与发布回归流程。
- 完成菜单栏+前台部件 v4 的 Phase A（基础样式收敛）：字体/间距/节点透明色/截断规则统一 token 化，超长文案统一按场景截断。
- 完成菜单栏+前台部件 v4 的 Phase B（精简模式改造）：球体样式替换为透明方框，精简信息收敛到当前任务/下一步/轻提示，整块区域可点击切换详细模式。
- 完成菜单栏+前台部件 v4 的 Phase C（详细模式收敛）：时间轴去重背景嵌入、一级/二级透明节点调色、间距参数规范化，并加入紧急停止细红线状态提示。
- 完成菜单栏+前台部件 v4 的 Phase D（菜单栏原生化）：菜单改为系统原生样式，危险操作仅文字强调，模式切换在部件隐藏时可自动显示并联动生效。
- 完成菜单栏+前台部件 v4 的 Phase E（回归验收）：新增 `OpenStaffAppTests` 回归套件并完成空态/长文本/多任务/交互动作链路验证，且现有 unit/integration/e2e 与 `OpenStaffApp` 构建均通过。
- 完成阶段 11.3.2 默认晋升与冲突策略：新增 `PreferenceRulePromoter`、`PreferenceConflictResolver`、`config/preference-promotion.example.yaml` 与 `ADR-0015`，默认只对 `global / app / taskFamily` 自动晋升，固化 `low/medium/high/critical` 风险门槛，并把 `PreferenceMemoryStore` 的规则排序接到统一冲突优先级与结构化解释模型上。

### 下一步建议
1. API 可用后补充 `provider=openai` 联机验证（模型行为、限流参数、错误码映射）并补充 skill 端到端执行联调。
2. 在 `scripts/validation` 上继续扩展：对 `data/raw-events/**/*.jsonl`、`data/task-chunks/**/*.json`、`data/knowledge/**/*.json`、`data/skills/**/*.json` 做 schema 快速校验。
3. 补齐 preflight 失败后的 repair workflow，把 `repairVersion` 真正接进自动修复与老师复核闭环。

---

## 9. 架构合理性评审与执行清单

- 架构与目录合理性评审请见：`docs/architecture-review.md`。
- 详细编码 TODO 清单请见：`docs/implementation-todo-checklist.md`。
- 下一阶段技术路线图请见：`docs/next-phase-technical-roadmap.md`。
- 建议按 TODO 阶段顺序推进，每完成一个阶段回写本文件“当前实现进展”。
