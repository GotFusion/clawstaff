# ClawStaff 下一阶段技术计划（Phase 11）

版本：v0.11.0-roadmap  
更新时间：2026-03-15

## 1. 路线定位

ClawStaff 下一阶段的目标，不是把项目转成一个传统意义上的 RL 训练系统，而是把它升级为：

- OpenClaw 的 **personal behavior preference layer**（个人行为偏好层）
- OpenClaw 的 **knowledge reinforcement engine**（知识强化引擎）
- OpenClaw 的 **review-driven adaptation cockpit**（审阅驱动的适配中控台）

即：

1. OpenClaw 继续负责执行内核、工具调用、渠道与 runtime。
2. ClawStaff 继续负责示教、知识构建、技能生成、执行前校验、执行后审阅。
3. 新阶段新增一层：将老师通过操控系统、审阅执行结果、与 ChatGPT 交互时产生的反馈，沉淀为持续可复用的偏好知识与策略修正。

这里的“学习”不是：

- 不断训练模型权重
- 不断消耗 GPU 跑在线 RL
- 把产品主链路转成训练基础设施

这里的“学习”是：

- 持续积累个人偏好
- 持续改进 skill、prompt、planner、assist 推荐与审阅规则
- 通过知识更新、策略装配、检索重排、规则提炼，达到类似强化学习的长期优化效果

---

## 2. 来自 OpenClaw-RL 的核心启示

OpenClaw-RL 最重要的启发，不是“要做 RL”，而是：

- 每次动作之后的 `next-state signal` 都是学习信号。
- 学习信号分为两类：
  - `evaluative`：上一步好不好。
  - `directive`：上一步应该怎么改。
- 服务、执行、判断、改进应异步解耦，而不是塞进同一个同步链路。

ClawStaff 下一阶段将保留这个抽象，但把“训练”替换为“知识强化”：

- `evaluative signal`
  - 用于更新置信度、偏好权重、skill 排序、自动执行阈值、benchmark 基线。
- `directive signal`
  - 用于更新步骤偏好、prompt 约束、修复策略、planner 决策模板、审阅建议。

所以我们要继承的是：

- `next-state` 视角
- 主线 / 支线交互分类
- evaluative + directive 双通路
- 非阻塞记录
- 学习闭环异步化

而不是直接继承：

- GPU 训练基础设施
- SGLang / Megatron / slime 训练栈
- 在线权重更新机制

---

## 3. 当前基线与新阶段缺口

结合当前实现，ClawStaff 已具备：

- `Capture -> Knowledge -> Skill -> Execute -> Review` 主链路。
- `SemanticTarget`、`ReplayVerifier`、`SkillDriftDetector`。
- `OpenClawRunner` 真执行链路。
- 审阅台三栏对照与 repair action。
- `AssistKnowledgeRetriever`。
- `Personal Desktop Benchmark`。
- skill preflight 与统一 safety policy。

但要成为“个人行为偏好持续学习系统”，还缺 5 个关键层：

1. **Turn 级学习数据层缺失**
   - 现有数据是分散的 capture / knowledge / execution / review 工件，尚未统一成一次行为闭环的 turn graph。
2. **`next-state` 抽象缺失**
   - 还没有统一表达“某一步执行后，系统、环境、老师、ChatGPT 分别反馈了什么”。
3. **偏好信号提炼层缺失**
   - 还没有把“通过 / 驳回 / 修 locator / 重示教 / 文字说明”转成结构化偏好信号。
4. **偏好记忆与策略装配层缺失**
   - 还没有一层独立的 memory/profile/policy builder，把知识真正影响到 planner、assist、skill 生成与 review。
5. **偏好学习专用评测缺失**
   - 当前 benchmark 更偏向执行稳定性，还没有衡量“个人偏好是否被学会且保持稳定”。

---

## 4. 下一阶段总目标

Phase 11 的总目标不是“让模型变得更强”，而是完成以下 4 件事：

1. 把一次桌面任务从“执行记录”升级为“可学习的交互回合”。
2. 把老师与 ChatGPT 的反馈从“说明文字”升级为“结构化偏好信号”。
3. 把偏好信号沉淀成可持续生效的知识与策略装配层。
4. 在不做 GPU 训练的前提下，让 assist、student、skill repair、review 逐轮变得更符合个人习惯。

成功标志是：

- 同一个人持续使用后，ClawStaff 会越来越懂：
  - 他在什么场景下偏好哪种步骤顺序。
  - 他如何定义“好结果”“可接受结果”“必须人工确认”。
  - 他常用哪些表达风格、约束词、修复方式和风险阈值。
- 这些偏好会体现在：
  - assist 推荐更准
  - student 模式规划更像本人
  - skill 生成与修复更稳定
  - 审阅建议更贴近老师标准
  - 自动执行更谨慎且更符合个人边界

---

## 5. 设计原则

### 5.1 知识强化优先于模型训练

- 优先更新知识、规则、模板、检索、排序、阈值和装配逻辑。
- 不将“调模型权重”作为本阶段核心目标。
- 一切改进都应可审计、可回滚、可解释。

### 5.2 偏好是结构化资产，不是聊天副产物

- 老师的反馈必须被结构化保存。
- ChatGPT 的建议必须被标注来源与置信度。
- 每条偏好都需要 provenance、版本和适用范围。

### 5.3 主线学习，支线降噪

- 仅主线任务步骤参与偏好学习。
- 辅助解释、背景整理、过渡性对话、无关闲聊不直接进入偏好更新。

### 5.4 先更新装配层，再更新执行层

- 先让 planner / prompt / skill 生成 / assist 推荐变得更像老师。
- 后让自动执行策略逐步放宽或收敛。
- 永远不绕过 preflight、replay verify 和 safety gate。

### 5.5 低风险累积，高风险确认

- 低风险、高频偏好可以自动累积。
- 高风险动作相关偏好必须经过老师明确确认才能晋升为生效规则。

### 5.6 冲突偏好必须显式管理

- 不同任务、不同 App、不同窗口环境下，偏好可能冲突。
- 冲突不可静默覆盖，必须保留作用域与优先级。

---

## 6. 核心架构升级

### 6.1 新增闭环抽象

当前：

`Capture -> Knowledge -> Skill -> Execute -> Review`

Phase 11 之后：

`Observe -> Plan -> Execute -> Next-State -> Review -> Preference Extract -> Policy Assemble -> Verify -> Reuse`

其中新增的关键层有：

1. `NextState Layer`
   - 汇总执行后的环境反馈、老师反馈、ChatGPT 反馈、repair action、benchmark 结果。
2. `Preference Extraction Layer`
   - 从 next-state 中提炼 evaluative / directive / risk / style / repair 信号。
3. `Preference Memory Layer`
   - 将信号沉淀为长期生效的偏好记忆。
4. `Policy Assembly Layer`
   - 在 assist、student、skill 生成、review 中装配这些偏好。
5. `Preference Verification Layer`
   - 通过 benchmark 和 replay 验证偏好是否真的改善结果。

### 6.2 新增核心对象

建议新增以下数据对象：

1. `InteractionTurn`
   - 一次可学习的主线动作单元。
   - 连接 capture、knowledge、skill、execution、review。

2. `NextStateEvidence`
   - 动作之后出现的反馈证据。
   - 来源可以是：
     - 老师明确反馈
     - OpenClaw 执行结果
     - 系统环境变化
     - ReplayVerifier / DriftDetector 输出
     - ChatGPT 修正建议
     - benchmark 判定

3. `PreferenceSignal`
   - 从 evidence 中提炼出的结构化偏好信号。
   - 基本类型：
     - `evaluative`
     - `directive`
     - `risk`
     - `style`
     - `repair`

4. `PreferenceRule`
   - 已晋升为长期记忆的偏好规则。
   - 包含作用域：
     - user
     - app
     - task family
     - skill family
     - risk level

5. `PreferenceProfile`
   - 用户当前偏好快照。
   - 由多条 `PreferenceRule` 聚合生成。

6. `PolicyAssemblyDecision`
   - 某次 assist / student / skill 生成时，实际应用了哪些偏好规则。
   - 用于可解释性与回滚。

### 6.3 偏好信号分类

建议把偏好信号至少分为 6 类：

1. `Outcome Preference`
   - 结果是否满意。
   - 例：老师通过、老师驳回、benchmark 成功、执行失败。

2. `Procedure Preference`
   - 步骤顺序或方法偏好。
   - 例：先检查文件再编辑、先 dry-run 再执行。

3. `Locator Preference`
   - UI 定位方式偏好。
   - 例：优先 AX，再文本锚点，尽量不要坐标回退。

4. `Style Preference`
   - 输出表达风格偏好。
   - 例：简洁、自然、少 AI 腔、更口语化。

5. `Risk Preference`
   - 风险容忍与确认阈值。
   - 例：Terminal 写文件可自动，系统设置必须确认。

6. `Repair Preference`
   - 失败后修复路径偏好。
   - 例：优先修 locator，而不是立即重示教。

---

## 7. 分阶段技术路线

### 阶段 11.1：学习数据层（Week 1）

#### 目标

把当前分散的数据工件统一为 turn 级学习记录，为后续偏好提炼做地基。

#### TODO 11.1.1 定义 `InteractionTurn` 契约

- 串联以下内容：
  - source observation
  - mapped procedure step
  - skill step
  - execution result
  - review result
  - repair action
  - benchmark case linkage
- 为每个 turn 增加稳定 `turnId`、`traceId`、`parentSessionId`。

**输出物**
- `core/contracts/InteractionTurnContracts.swift`
- `core/learning/interaction-turn-v0.md`
- `core/learning/schemas/interaction-turn.schema.json`
- `docs/adr/ADR-0010-interaction-turn-model.md`

**验收标准**
- [ ] 任意一次主线执行都能落成一个完整 `InteractionTurn` 记录。
- [ ] 能从 `InteractionTurn` 追溯到 capture、knowledge、skill、review 原工件。

#### TODO 11.1.2 定义 `NextStateEvidence` 契约

- 统一表达执行后的反馈证据：
  - 老师反馈
  - OpenClaw stdout/stderr/exit code
  - ReplayVerifier 结果
  - DriftDetector 结果
  - ChatGPT 修正建议
  - benchmark 结果

**输出物**
- `core/contracts/NextStateEvidenceContracts.swift`
- `core/learning/next-state-evidence-v0.md`
- `core/learning/schemas/next-state-evidence.schema.json`

**验收标准**
- [ ] 至少 5 类反馈源可以映射成统一的 `NextStateEvidence`。
- [ ] evidence 保留来源、时间、置信度与原始摘要。

#### TODO 11.1.3 主线 / 支线交互分类器

- 定义哪些 turn 会参与偏好学习：
  - 主线任务推进
  - 主线 skill 执行
  - 主线 repair
- 哪些不参与：
  - 闲聊
  - 背景解释
  - 纯日志展示
  - 辅助性说明

**输出物**
- `core/learning/TurnLearningEligibility.swift`
- `docs/adr/ADR-0011-mainline-vs-side-turns.md`

**验收标准**
- [ ] 训练无关 turn 不会自动进入偏好更新流程。

---

### 阶段 11.2：偏好信号提炼层（Week 2 ~ Week 3）

#### 目标

将老师、环境和 ChatGPT 的反馈，转成结构化偏好信号，而不是停留在 review 文本层。

#### TODO 11.2.1 定义 `PreferenceSignal` 模型

- 字段包括：
  - signal type
  - polarity
  - confidence
  - scope
  - extracted rationale
  - evidence links
  - promotion status

**输出物**
- `core/contracts/PreferenceSignalContracts.swift`
- `core/learning/preference-signal-v0.md`
- `core/learning/schemas/preference-signal.schema.json`

**验收标准**
- [ ] evaluative / directive / risk / style / repair 五类以上信号均可表达。

#### TODO 11.2.2 实现 `PreferenceSignalExtractor`

- 从以下输入提炼信号：
  - review action
  - replay verify
  - drift reason
  - benchmark result
  - teacher note
  - ChatGPT correction note
- 先采用规则 + 模板 + LLM 结构化抽取混合方式。

**输出物**
- `core/learning/PreferenceSignalExtractor.swift`
- `scripts/learning/extract_preference_signals.py`
- `core/learning/examples/preference-signals/*.json`

**验收标准**
- [ ] 对 30 条真实 review 样本，能产出结构化信号并支持人工复核。
- [ ] 可区分“结果不满意”和“方法不满意”。

#### TODO 11.2.3 Directive Hint 生成器

- 把偏好提炼进一步落成简洁可执行 hint：
  - “先检查窗口标题再点击”
  - “Terminal 修改文件前先读取现有内容”
  - “默认用简洁自然口吻，不要过度结构化”

**输出物**
- `core/learning/DirectiveHintBuilder.swift`
- `core/learning/directive-hint-template-v0.md`

**验收标准**
- [ ] 每条 directive signal 至少能生成 1 条可读、可执行 hint。

---

### 阶段 11.3：偏好记忆层（Week 4）

#### 目标

把一次次信号沉淀为长期记忆，而不是每次都只依赖最近 review。

#### TODO 11.3.1 实现 `PreferenceMemoryStore`

- 存储：
  - `PreferenceSignal`
  - `PreferenceRule`
  - `PreferenceProfile`
  - rule provenance
  - rule superseded relation

**输出物**
- `core/storage/PreferenceMemoryStore.swift`
- `data/preferences/`
- `docs/adr/ADR-0012-preference-memory-store.md`

**验收标准**
- [ ] 所有规则都可追溯到原始证据。
- [ ] 规则支持版本化与撤销。

#### TODO 11.3.2 规则晋升与冲突解决

- 信号并不直接变规则，需要晋升机制：
  - 单次低置信反馈 -> 候选规则
  - 多次重复出现 -> 稳定规则
  - 高风险规则 -> 强制人工确认
- 冲突解决维度：
  - scope 更具体优先
  - 最近确认优先
  - 老师显式确认优先

**输出物**
- `core/learning/PreferenceRulePromoter.swift`
- `core/learning/PreferenceConflictResolver.swift`

**验收标准**
- [ ] 同一任务族下规则冲突可结构化解释。
- [ ] 不会因单次异常反馈覆盖长期稳定偏好。

#### TODO 11.3.3 形成 `PreferenceProfile`

- 聚合出用户当前偏好画像：
  - step preference
  - output style
  - safety threshold
  - repair strategy
  - app-specific habits

**输出物**
- `core/learning/PreferenceProfileBuilder.swift`
- `data/preferences/profile.json`

**验收标准**
- [ ] 系统可生成当前有效偏好快照供 GUI 展示与人工审查。

---

### 阶段 11.4：策略装配层（Week 5 ~ Week 6）

#### 目标

让偏好记忆真正影响 assist、student、skill 和 review，而不是停留在存储层。

#### TODO 11.4.1 Assist 偏好装配

- 在 `AssistKnowledgeRetriever` 之上增加偏好重排：
  - 同样历史知识下，优先更符合老师当前偏好的步骤。

**输出物**
- `core/orchestrator/PreferenceAwareAssistPredictor.swift`
- `core/orchestrator/preference-aware-assist-v0.md`

**验收标准**
- [ ] assist 推荐可解释“为什么这次选择了历史 A 而不是历史 B”。

#### TODO 11.4.2 Student Planner 偏好装配

- 根据 `PreferenceProfile` 调整：
  - 规划风格
  - 执行顺序
  - 默认谨慎程度
  - 失败后的 repair 路径

**输出物**
- `core/orchestrator/PreferenceAwareStudentPlanner.swift`
- `core/contracts/PlanningPreferenceContracts.swift`

**验收标准**
- [ ] 学生模式能体现出 app/task-specific 的行为差异。

#### TODO 11.4.3 Skill 生成与 repair 偏好装配

- skill mapper、repair planner 接入 preference：
  - locator 选择顺序
  - 提示词约束
  - 默认 repair 方案
  - 风险动作确认要求

**输出物**
- `scripts/skills/openclaw_skill_mapper.py`
- `core/repair/PreferenceAwareSkillRepairPlanner.swift`
- `scripts/skills/templates/*`

**验收标准**
- [ ] skill 生成结果可体现用户偏好而不破坏 schema 与 safety gate。

#### TODO 11.4.4 Review 偏好装配

- 审阅台根据老师偏好提供更贴近的审阅建议：
  - 更偏向修 locator
  - 更偏向重新示教
  - 更偏向保守阻断

**输出物**
- `core/storage/ExecutionReviewStore.swift`
- `apps/macos/Sources/OpenStaffApp/*`

**验收标准**
- [ ] review 建议不再统一模板化，而是体现个人审阅标准。

---

### 阶段 11.5：偏好学习评测层（Week 7）

#### 目标

建立专门衡量“是否越来越懂这个人”的 benchmark，而不仅是执行是否成功。

#### TODO 11.5.1 新增 `Personal Preference Benchmark`

- 建议覆盖 4 类：
  - 结果风格偏好
  - 步骤顺序偏好
  - 风险阈值偏好
  - repair 路径偏好

**输出物**
- `data/benchmarks/personal-preference/`
- `docs/personal-preference-benchmark-spec.md`
- `scripts/benchmarks/run_personal_preference_benchmark.py`

**验收标准**
- [ ] 至少 20 条 case，可衡量偏好学习前后差异。

#### TODO 11.5.2 定义偏好学习指标

- 建议指标：
  - `preference-match-rate`
  - `assist-acceptance-rate`
  - `repair-path-hit-rate`
  - `teacher-override-rate`
  - `unsafe-auto-execution-regression`

**输出物**
- `docs/metrics/preference-learning-metrics.md`
- `scripts/benchmarks/aggregate_preference_metrics.py`

**验收标准**
- [ ] 指标可稳定比较不同版本的偏好学习效果。

---

### 阶段 11.6：安全与治理层（Week 8）

#### 目标

确保“持续学习”不会变成“持续积累错误偏好”。

#### TODO 11.6.1 偏好变更门禁

- 对以下规则强制人工确认：
  - 高风险自动执行
  - 系统设置相关动作
  - 隐私相关 app
  - 删除 / 覆盖 / 提交等 irreversible 操作

**输出物**
- `core/learning/PreferencePromotionPolicy.swift`
- `config/preference-governance.yaml`

**验收标准**
- [ ] 高风险偏好不会因单次反馈自动生效。

#### TODO 11.6.2 偏好回滚与审计

- 支持查看：
  - 哪条规则何时生效
  - 来自哪次执行 / 哪条反馈
  - 被哪条新规则覆盖
- 支持一键撤销。

**输出物**
- `apps/macos/Sources/OpenStaffApp/*`
- `core/storage/PreferenceAuditLogStore.swift`

**验收标准**
- [ ] 任意已生效规则都能回滚。

#### TODO 11.6.3 偏好漂移监控

- 识别以下问题：
  - 老师风格变化
  - 某类规则长期不再命中
  - 某条规则引发更多 override

**输出物**
- `core/learning/PreferenceDriftMonitor.swift`
- `docs/adr/ADR-0013-preference-drift-monitoring.md`

**验收标准**
- [ ] 系统能提醒“这条偏好可能已过时”。

---

## 8. 本阶段明确不做的事情

为保持路线清晰，本阶段暂不优先：

- 在线 GPU 训练或实时权重更新。
- 引入 Megatron / slime / Ray 等训练基础设施。
- 在真实桌面环境中做无门控的强化学习探索。
- 用模型自更新替代现有 safety gate、preflight、replay verify。
- 将 ClawStaff 变成通用云端训练平台。

后续如要进入参数级适配，应作为下一阶段单独立项，且只考虑：

- 小规模 LoRA
- 离线验证
- 可回滚适配层
- 不影响主执行链路的异步部署

---

## 9. 八周里程碑视图

### Week 1

- 完成 `InteractionTurn` 与 `NextStateEvidence` 契约。
- 明确主线 / 支线学习范围。

### Week 2

- 完成 `PreferenceSignal` schema。
- 打通 review / replay / repair -> signal 抽取。

### Week 3

- 落地 directive hint 生成器。
- 形成第一版偏好抽取样本集。

### Week 4

- 完成 `PreferenceMemoryStore`。
- 完成规则晋升与冲突解决。

### Week 5

- assist 接入偏好重排。
- student planner 接入偏好装配。

### Week 6

- skill mapper / repair planner / review 建议接入偏好装配。

### Week 7

- 建立 `Personal Preference Benchmark`。
- 定义并跑通偏好学习指标。

### Week 8

- 完成偏好治理、回滚、漂移监控。
- 将 preference benchmark 接入 release preflight。

---

## 10. 阶段完成标志（Definition of Done）

当满足以下条件时，可认为 Phase 11 第一阶段完成：

1. 任意一次主线任务都能落成 `InteractionTurn + NextStateEvidence + PreferenceSignal` 闭环。
2. 系统能从 review / repair / benchmark 中自动提取结构化偏好信号。
3. 偏好信号可沉淀为长期 `PreferenceRule`，并形成 `PreferenceProfile`。
4. assist、student、skill repair、review 至少有 3 个模块已接入偏好装配。
5. 系统可解释“这次推荐 / 规划 / 修复为什么这么做”。
6. `Personal Preference Benchmark` 能稳定运行并比较版本差异。
7. 高风险偏好变更有门禁、审计与回滚机制。

---

## 11. 一句话结论

ClawStaff 下一阶段最重要的升级，不是“训练一个更强的模型”，而是把自己做成：

**一个能从老师真实操控、执行结果、审阅动作和 ChatGPT 交互中，持续沉淀个人偏好、持续重组知识与策略、并长期变得越来越像这个老师的知识强化系统。**
