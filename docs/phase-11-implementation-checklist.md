# ClawStaff Phase 11 详细实现清单

> 目标：将 [phase-11-knowledge-reinforcement-roadmap.md](/Users/mac/Desktop/code/Personal/openstaff/docs/phase-11-knowledge-reinforcement-roadmap.md) 拆成可按顺序推进的执行清单。重点不是模型训练，而是偏好信号提炼、偏好记忆沉淀和策略装配。

## 执行顺序约束

- 先做老师可见状态与反馈入口，再做数据模型，再做提炼器，再做记忆层，再做装配层。
- 在 `PreferenceMemoryStore` 未完成前，不接入 assist / student 的真实行为决策。
- 在 `PreferencePromotionPolicy` 未完成前，不允许任何高风险偏好自动生效。
- 在 `Personal Preference Benchmark` 未建立前，不将偏好学习效果视为“已验证”。
- 在 learning 状态可见、暂停 / 排除未完成前，不默认开启持续学习。
- `student planner` 只允许在 assist / skill / repair / review 已稳定后，通过 feature flag 接入。

---

## 阶段 11.0：老师侧 UX 与隐私基线

### TODO 11.0.1 落地 `Learning Status Surface`
- [x] 提供菜单栏或悬浮学习状态
- [x] 显示当前模式、当前 app、learning `on / paused / excluded / sensitive-muted`
- [x] 显示最近一次成功落盘时间
- [x] 暴露一键暂停 / 恢复入口

**输出物**
- `apps/macos/Sources/OpenStaffApp/*`
- `core/learning/LearningSessionState.swift`
- `docs/ux/learning-status-surface-v0.md`

**验收标准**
- [x] 老师能在 `1` 次视线切换内知道系统是否正在学习
- [x] 暂停 / 恢复在 `1` 次点击内完成

### TODO 11.0.2 落地 `Quick Feedback Bar`
- [ ] 固定支持 `通过 / 驳回 / 修 locator / 重示教 / 太危险 / 顺序不对 / 风格不对`
- [ ] 每个 quick action 都写成标准化 `teacherReview` evidence
- [ ] 支持可选短备注，不要求长文本
- [ ] 为 quick actions 预留统一快捷键定义

**输出物**
- `core/contracts/TeacherQuickFeedbackContracts.swift`
- `apps/macos/Sources/OpenStaffApp/*`
- `docs/ux/teacher-quick-feedback-v0.md`

**验收标准**
- [ ] 抽样 `20` 次 review 中，至少 `16` 次可只靠 quick actions 完成
- [ ] 单次反馈中位耗时不高于 `8` 秒

### TODO 11.0.3 落地 `Privacy / Exclusion Panel`
- [ ] 支持 app 排除名单
- [ ] 支持窗口标题排除规则
- [ ] 支持 `15` 分钟临时暂停
- [ ] 支持敏感场景自动静默
- [ ] 第一版敏感场景至少覆盖密码、支付、隐私授权、医疗 / 金融

**输出物**
- `config/learning-privacy.example.yaml`
- `core/learning/SensitiveScenePolicy.swift`
- `docs/ux/learning-privacy-controls-v0.md`

**验收标准**
- [ ] 被排除 app / 窗口不会继续生成 learning 工件
- [ ] `capture-policy-violation-count = 0`

---

## 阶段 11.1：学习数据层

### TODO 11.1.1 新建 `core/learning/` 目录基线
- [ ] 新增 `core/learning/README.md`，说明该目录负责任务回合级学习对象、偏好提炼、偏好规则与治理。
- [ ] 约定 `schemas/`、`examples/`、`fixtures/`、`builders/` 子目录职责。
- [ ] 在 `docs/coding-conventions.md` 中补充 `learning` 相关命名规范。

**输出物**
- `core/learning/README.md`
- `core/learning/schemas/`
- `core/learning/examples/`

**验收标准**
- [ ] 新增 learning 相关文件有统一落点，不再散落在 `core/storage` / `core/orchestrator` 中。

### TODO 11.1.2 定义 `InteractionTurn` 契约
- [ ] 定义 `InteractionTurn`
- [ ] 定义 `InteractionTurnStepReference`
- [ ] 定义 `InteractionTurnExecutionLink`
- [ ] 定义 `InteractionTurnReviewLink`
- [ ] 为每条记录保留 `turnId`、`traceId`、`sessionId`、`taskId`、`stepId`
- [ ] 增加 `learningState`、`privacyTags` 字段，记录学习状态与排除上下文
- [ ] 增加 `observationRef` 或等价字段，能回指点击前后截图、窗口签名、AX / OCR sidecar
- [ ] 增加 `actionKind`，第一版固定区分 `nativeAction` / `guiAction`
- [ ] 对 `guiAction` 记录 `semanticTargetSetRef` 或等价 locator 候选引用
- [ ] 建立与 `KnowledgeItem`、skill、execution log、review report 的关联字段

**输出物**
- `core/contracts/InteractionTurnContracts.swift`
- `core/learning/interaction-turn-v0.md`
- `core/learning/schemas/interaction-turn.schema.json`

**验收标准**
- [ ] 任意主线步骤都可映射为一个 `InteractionTurn`
- [ ] `InteractionTurn` 可追溯回原始 capture / knowledge / skill / review 工件
- [ ] 抽样回看时，可恢复该步的窗口上下文和 locator 候选，而不只是文本摘要

### TODO 11.1.3 定义 `NextStateEvidence` 契约
- [ ] 定义 evidence source 枚举：
  - `teacherReview`
  - `executionRuntime`
  - `replayVerify`
  - `driftDetection`
  - `chatgptSuggestion`
  - `benchmarkResult`
- [ ] 定义 evidence payload 的统一摘要字段与原始引用字段
- [ ] 定义 evidence confidence / severity / timestamp
- [ ] 区分 `evaluative` 与 `directive` 的原始证据类型
- [ ] 为 GUI 执行失败保留标准化 failure bucket：
  - `locator_resolution_failed`
  - `action_kind_mismatch`
  - `risk_blocked`

**输出物**
- `core/contracts/NextStateEvidenceContracts.swift`
- `core/learning/next-state-evidence-v0.md`
- `core/learning/schemas/next-state-evidence.schema.json`

**验收标准**
- [ ] 至少 6 类反馈源可统一编码为 `NextStateEvidence`
- [ ] evidence 可保留原始路径引用，不需要复制原始大文件

### TODO 11.1.4 实现 `InteractionTurnBuilder`
- [ ] 从执行完成后的主链路生成 `InteractionTurn`
- [ ] 汇总 execution log、review report、repair request、benchmark linkage
- [ ] 记录 build diagnostics，标明哪些字段缺失
- [ ] 支持离线回填旧样本
- [ ] 优先复用现有 `raw-events`、窗口签名、`SemanticTarget`，补 sidecar 引用而不是复制原始大对象
- [ ] 首批回填至少覆盖 teaching / assist / student 三类历史任务

**输出物**
- `core/learning/InteractionTurnBuilder.swift`
- `scripts/learning/build_interaction_turns.py`
- `core/learning/examples/interaction-turns/*.json`

**验收标准**
- [ ] 对至少 20 条历史样本批量构建成功
- [ ] 缺失字段时不会崩溃，而是给出结构化 diagnostics

### TODO 11.1.5 主线 / 支线学习资格判断
- [ ] 定义 `TurnLearningEligibility`
- [ ] 支持 `eligible / ineligible / needs_review`
- [ ] 对 assist 预判、student 自主执行、repair、纯状态展示/说明类片段建立分类规则
- [ ] 输出排除原因

**输出物**
- `core/learning/TurnLearningEligibility.swift`
- `core/learning/turn-learning-eligibility-v0.md`

**验收标准**
- [ ] 纯展示、纯日志、无操作推进价值的记录片段不进入偏好学习
- [ ] 排除行为可解释，不是黑盒过滤

---

## 阶段 11.2：偏好信号提炼层

### TODO 11.2.1 定义 `PreferenceSignal` 契约
- [ ] 定义 `PreferenceSignalType`
  - `outcome`
  - `procedure`
  - `locator`
  - `style`
  - `risk`
  - `repair`
- [ ] 定义 `PreferenceSignalPolarity`
  - `reinforce`
  - `discourage`
  - `neutral`
- [ ] 定义 `PreferenceSignalScope`
  - `global`
  - `app`
  - `taskFamily`
  - `skillFamily`
  - `windowPattern`
- [ ] 约定 v0 默认生效只优先使用 `global / app / taskFamily`
- [ ] 定义 `promotionStatus`
  - `candidate`
  - `confirmed`
  - `rejected`
  - `superseded`
- [ ] 定义 `evaluativeDecision`
  - `pass`
  - `fail`
  - `neutral`

**输出物**
- `core/contracts/PreferenceSignalContracts.swift`
- `core/learning/preference-signal-v0.md`
- `core/learning/schemas/preference-signal.schema.json`

**验收标准**
- [ ] 可以覆盖 roadmap 中定义的偏好类型与作用域

### TODO 11.2.2 实现规则优先的信号提炼器
- [ ] 从 review action 提炼 outcome / repair signal
- [ ] 从 replay verify 提炼 locator signal
- [ ] 从 drift reason 提炼 repair / locator signal
- [ ] 从 benchmark result 提炼 outcome / risk signal
- [ ] 从 safety block 提炼 risk signal

**输出物**
- `core/learning/RuleBasedPreferenceSignalExtractor.swift`
- `core/learning/examples/preference-signals-rule-based/*.json`

**验收标准**
- [ ] 对无 LLM 场景也可提炼基础信号
- [ ] 至少 60% 历史样本可提炼出 1 条以上有效信号

### TODO 11.2.3 实现 LLM 辅助的结构化提炼器
- [ ] 用 ChatGPT 将老师审阅备注、修正备注或 repair note 转为结构化偏好 JSON
- [ ] 输入固定包含：上一步动作摘要、next-state 摘要、next-state role、老师备注
- [ ] 增加 schema 校验
- [ ] 采用 3-vote，多数一致才接受
- [ ] hint 只允许 1-3 句，且必须可执行
- [ ] 对低置信输出落入人工复核队列
- [ ] 严格记录来源与 prompt 版本

**输出物**
- `scripts/learning/extract_preference_signals.py`
- `scripts/learning/prompts/*.md`
- `scripts/learning/schemas/preference-extraction-output.schema.json`

**验收标准**
- [ ] 对文字反馈样本可稳定提炼出 procedure / style / risk signal
- [ ] 自由文本备注结构化成功率不低于 80%
- [ ] 非法 JSON 输出可被捕获并降级

### TODO 11.2.4 合并规则与 LLM 提炼结果
- [ ] 同一 turn 的多来源信号去重
- [ ] 合并相同 scope + type + polarity 的候选
- [ ] 为冲突信号附加冲突标签
- [ ] 记录合并置信度

**输出物**
- `core/learning/PreferenceSignalMerger.swift`

**验收标准**
- [ ] 同一 turn 最终信号集合可解释、无明显重复

### TODO 11.2.5 生成 directive hint
- [ ] 从 procedure / locator / repair / style signal 生成一句或几句可执行 hint
- [ ] hint 必须指向行为，不写空泛评价
- [ ] hint 只服务 assist / skill mapper / repair planner / review suggestion
- [ ] hint 需要区分适用范围

**输出物**
- `core/learning/DirectiveHintBuilder.swift`
- `core/learning/examples/directive-hints/*.json`

**验收标准**
- [ ] 每条 directive 类 signal 可生成至少 1 条可操作 hint

---

## 阶段 11.3：偏好记忆层

### TODO 11.3.1 定义 `PreferenceRule` 与 `PreferenceProfile` 契约
- [ ] 定义 `PreferenceRule`
- [ ] 定义 `PreferenceRuleEvidence`
- [ ] 定义 `PreferenceProfile`
- [ ] 定义 `PreferenceProfileSnapshot`

**输出物**
- `core/contracts/PreferenceRuleContracts.swift`
- `core/contracts/PreferenceProfileContracts.swift`
- `core/learning/preference-rule-v0.md`
- `core/learning/preference-profile-v0.md`

**验收标准**
- [ ] 规则和用户当前偏好快照有清晰区分

### TODO 11.3.2 实现 `PreferenceMemoryStore`
- [ ] 存储 candidate signals
- [ ] 存储 promoted rules
- [ ] 存储 superseded / revoked 规则
- [ ] 存储 profile snapshot
- [ ] 支持按 app / task family / skill family 查询

**输出物**
- `core/storage/PreferenceMemoryStore.swift`
- `data/preferences/signals/`
- `data/preferences/rules/`
- `data/preferences/profiles/`

**验收标准**
- [ ] 规则查询无需遍历全部 review 工件
- [ ] 数据结构支持审计与回滚

### TODO 11.3.3 实现规则晋升器
- [ ] 将单次信号保持为 candidate
- [ ] 将重复出现信号晋升为 stable rule
- [ ] 支持阈值：
  - `low risk`: `>=3` 次命中、跨 `>=2` 个 session、平均置信度 `>=0.75`
  - `medium risk`: `>=4` 次命中、跨 `>=3` 个 session、最近无显式驳回
  - `high risk`: 必须 `teacherConfirmed`
- [ ] 高风险规则必须 `teacherConfirmed`

**输出物**
- `core/learning/PreferenceRulePromoter.swift`
- `config/preference-promotion.example.yaml`

**验收标准**
- [ ] 单次偶发反馈不会直接成为长期规则
- [ ] 高风险规则无人工确认不能晋升

### TODO 11.3.4 实现冲突解决器
- [ ] 相同 scope 冲突规则排序
- [ ] 更具体 scope 优先于更宽 scope
- [ ] 最近显式确认优先
- [ ] 输出冲突解释信息

**输出物**
- `core/learning/PreferenceConflictResolver.swift`

**验收标准**
- [ ] 冲突结果可解释为“为何 A 覆盖 B”

### TODO 11.3.5 构建 `PreferenceProfile`
- [ ] 按模块聚合：
  - assist
  - skill generation
  - repair
  - review
  - planner
- [ ] 生成 profile snapshot
- [ ] 记录 snapshot 使用了哪些 rule ids

**输出物**
- `core/learning/PreferenceProfileBuilder.swift`
- `core/learning/examples/preference-profiles/*.json`

**验收标准**
- [ ] GUI 或 CLI 可查看当前生效偏好快照

---

## 阶段 11.4：策略装配层

### TODO 11.4.1 Assist 偏好重排
- [ ] 在 `AssistKnowledgeRetriever` 结果之上增加偏好打分
- [ ] 对 step preference、app preference、risk preference 加权
- [ ] 输出“应用了哪些规则”的解释文本

**输出物**
- `core/orchestrator/PreferenceAwareAssistPredictor.swift`
- `core/contracts/AssistPreferenceContracts.swift`

**验收标准**
- [ ] 同样历史知识下，推荐结果会因个人偏好不同而不同

### TODO 11.4.2 Skill mapper 偏好装配
- [ ] 让 skill 生成过程接入：
  - `nativeAction` / `guiAction` 分流
  - locator preference
  - procedure preference
  - style / note preference
  - safety preference
- [ ] `nativeAction` 优先映射到 `Shortcuts / AppleScript / CLI / app adapter`
- [ ] `guiAction` 固定按 `AX -> text anchor -> image anchor -> relative coordinate -> absolute coordinate` 生成 locator 候选
- [ ] 在 skill metadata 中记录所用偏好规则

**输出物**
- `scripts/skills/openclaw_skill_mapper.py`
- `scripts/skills/templates/*`

**验收标准**
- [ ] skill 产物可追溯本次生成引用了哪些偏好规则

### TODO 11.4.3 Repair planner 偏好装配
- [ ] 优先修 locator、先 replay、还是重新示教，支持偏好控制
- [ ] 输出 repair 建议时显示规则命中来源

**输出物**
- `core/repair/PreferenceAwareSkillRepairPlanner.swift`

**验收标准**
- [ ] 不同用户的 repair 建议策略可表现出差异

### TODO 11.4.4 Review 建议偏好装配
- [ ] 审阅台提供更贴近老师偏好的建议动作
- [ ] 支持“你通常更倾向于先修 locator”之类的解释

**输出物**
- `core/storage/ExecutionReviewStore.swift`
- `apps/macos/Sources/OpenStaffApp/*`

**验收标准**
- [ ] review 建议可解释，不只是静态模板

### TODO 11.4.5 Student planner 偏好装配（Feature Flag）
- [ ] 根据 `PreferenceProfile` 调整 planning prompt / planning constraints
- [ ] 区分保守与积极执行策略
- [ ] 失败后优先 repair 还是 re-teach 可由偏好控制
- [ ] 默认挂在 feature flag 后，不作为 Phase 11 默认行为

**输出物**
- `core/orchestrator/PreferenceAwareStudentPlanner.swift`
- `scripts/llm/prompts/student/*`

**验收标准**
- [ ] student 模式只有在 benchmark 无安全回归时才允许启用

### TODO 11.4.6 记录 `PolicyAssemblyDecision`
- [ ] 每次 assist / student / skill generation / repair 输出一条 assembly log
- [ ] 记录命中的 rule ids、被排除的规则、最终权重

**输出物**
- `core/contracts/PolicyAssemblyDecisionContracts.swift`
- `core/storage/PolicyAssemblyDecisionStore.swift`

**验收标准**
- [ ] 任意一次系统行为都可回答“这次为什么这样做”

---

## 阶段 11.5：偏好学习评测层

### TODO 11.5.1 设计 `Personal Preference Benchmark`
- [ ] 定义 case catalog
- [ ] 为每条 case 指定 expected preference-aware behavior
- [ ] 覆盖：
  - style
  - procedure
  - risk
  - repair
- [ ] 第一版固定 24 条 case，其中 12 条真实任务、12 条扰动样本

**输出物**
- `data/benchmarks/personal-preference/catalog.json`
- `docs/personal-preference-benchmark-spec.md`

**验收标准**
- [ ] 至少 24 条 case，覆盖 4 类偏好

### TODO 11.5.2 实现 benchmark runner
- [ ] 从 profile snapshot 驱动测试
- [ ] 校验 assist / student / repair / review 的偏好命中率
- [ ] 输出 manifest 与 case report

**输出物**
- `scripts/benchmarks/run_personal_preference_benchmark.py`
- `data/benchmarks/personal-preference/generated/`

**验收标准**
- [ ] 同一版本可重复运行并生成稳定汇总结果

### TODO 11.5.3 定义偏好学习指标
- [ ] `preference_match_rate`
- [ ] `assist_acceptance_rate`
- [ ] `teacher_override_rate`
- [ ] `repair_path_hit_rate`
- [ ] `unsafe_auto_execution_regression`
- [ ] `quick_feedback_completion_rate`
- [ ] `median_feedback_latency_seconds`
- [ ] `capture_policy_violation_count`
- [ ] 写入 v0 门槛：
  - `preference_match_rate >= 0.70`
  - `repair_path_hit_rate >= 0.60`
  - `unsafe_auto_execution_regression = 0`
  - `teacher_override_rate` 不得比基线恶化超过 `10%`
  - `quick_feedback_completion_rate >= 0.80`
  - `median_feedback_latency_seconds <= 8`
  - `capture_policy_violation_count = 0`

**输出物**
- `docs/metrics/preference-learning-metrics.md`
- `scripts/benchmarks/aggregate_preference_metrics.py`

**验收标准**
- [ ] 每次 benchmark 都能输出统一指标摘要

### TODO 11.5.4 接入发布门禁
- [ ] 将 preference benchmark 接入 `release-preflight`
- [ ] 对关键指标设最低阈值
- [ ] 对高风险 regression 直接 fail

**输出物**
- `scripts/release/run_regression.py`
- `Makefile`

**验收标准**
- [ ] 偏好学习退化可在发布前被拦截

---

## 阶段 11.6：治理与安全层

### TODO 11.6.1 定义偏好治理策略
- [ ] 哪些规则允许自动晋升
- [ ] 哪些规则必须人工确认
- [ ] 哪些规则有过期时间
- [ ] 哪些规则只能按 app / task 局部生效
- [ ] 固化 `low / medium / high / critical` 四级风险治理策略

**输出物**
- `config/preference-governance.yaml`
- `core/learning/PreferencePromotionPolicy.swift`

**验收标准**
- [ ] 治理规则可配置，不硬编码在多个模块

### TODO 11.6.2 实现偏好审计日志
- [ ] 记录规则创建、晋升、覆盖、撤销、回滚
- [ ] 为每条操作保留操作者与来源

**输出物**
- `core/storage/PreferenceAuditLogStore.swift`
- `data/preferences/audit/`

**验收标准**
- [ ] 任意规则都能看见完整生命周期

### TODO 11.6.3 实现偏好回滚
- [ ] 支持撤销单条规则
- [ ] 支持回滚到某个 profile snapshot
- [ ] 支持 dry-run 查看回滚影响

**输出物**
- `core/learning/PreferenceRollbackService.swift`
- `apps/macos/Sources/OpenStaffApp/*`

**验收标准**
- [ ] 回滚后策略装配结果可复现变化

### TODO 11.6.4 实现偏好漂移监控
- [ ] 检测长期不命中规则
- [ ] 检测 override 率升高
- [ ] 检测风格偏好变化
- [ ] 检测高风险规则与当前行为不一致
- [ ] 第一版至少覆盖：
  - `30` 天未命中
  - 最近 `10` 次相关任务里 override 超过 `50%`
  - 最近 `3` 次明确被老师驳回

**输出物**
- `core/learning/PreferenceDriftMonitor.swift`
- `core/learning/preference-drift-monitor-v0.md`

**验收标准**
- [ ] 系统能提醒“该规则可能过时或不再适用”

### TODO 11.6.5 实现 learning bundle 导出、校验与恢复
- [ ] 导出 turns / evidence / signals / rules / profiles / audit
- [ ] 生成 `manifest.json` 与 schema version
- [ ] 提供 payload 校验脚本
- [ ] 恢复前支持 dry-run 预览

**输出物**
- `scripts/learning/export_learning_bundle.py`
- `scripts/learning/verify_learning_bundle.py`
- `docs/learning-bundle-spec.md`

**验收标准**
- [ ] 同一 bundle 可完成导出、校验、恢复三步闭环
- [ ] 恢复后可重新构建 profile 并对齐 rule ids

### TODO 11.6.6 固化 hook / gateway 集成边界
- [ ] 定义事件：
  - `learning.turn.created`
  - `learning.signal.extracted`
  - `preference.rule.promoted`
  - `preference.profile.updated`
- [ ] 定义 gateway 方法：
  - `preferences.listRules`
  - `preferences.listAssemblyDecisions`
  - `preferences.exportBundle`
- [ ] 禁止外部插件直接依赖内部私有对象图

**输出物**
- `core/contracts/LearningIntegrationContracts.swift`
- `docs/integrations/learning-hooks-gateway-v0.md`

**验收标准**
- [ ] 外部插件或 worker 可只依赖公开边界消费学习结果

---

## 建议并行度

### 可先并行
- `LearningSessionState` 与 `SensitiveScenePolicy`
- `InteractionTurnContracts` 与 `NextStateEvidenceContracts`
- `PreferenceSignalContracts` 与 `RuleBasedPreferenceSignalExtractor`
- `PreferenceRuleContracts` 与 `PreferenceMemoryStore`

### 必须串行
- `Learning Status Surface` -> `TeacherQuickFeedbackContracts` -> `InteractionTurnBuilder`
- `PreferenceMemoryStore` -> `PreferenceRulePromoter` -> `PreferenceProfileBuilder`
- `PreferenceProfileBuilder` -> `PreferenceAwareAssistPredictor`
- `Personal Preference Benchmark` -> `release-preflight` 接入

---

## 阶段完成检查

- [ ] learning 状态、暂停 / 排除和 quick feedback 已落地
- [ ] `InteractionTurn` 已在真实主线数据上落盘
- [ ] `NextStateEvidence` 已覆盖主要反馈源
- [ ] `PreferenceSignalExtractor` 已能批量提炼真实样本
- [ ] `PreferenceMemoryStore` 已支持规则晋升、查询、撤销
- [ ] assist / skill / repair / review 至少 3 个模块接入偏好装配
- [ ] student planner 仍处于 feature flag 后
- [ ] `Personal Preference Benchmark` 已建立并可稳定运行
- [ ] 偏好治理、审计、回滚与漂移监控已接入
- [ ] learning bundle 与 hook / gateway 边界已接入
