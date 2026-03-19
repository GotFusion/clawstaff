# core/learning/

学习层负责把“老师当时做了什么”和“系统后来学到了什么”拆成可审计、可回填、可治理的工件。

## 目录职责

- 根目录：学习层的共享 builder、规则和治理实现。
- `schemas/`：学习工件的 JSON Schema，供脚本、回填和回归校验复用。
- `examples/`：最小、可读、可直接对照 schema 的样例。
- `fixtures/`：较大的测试输入或历史回填夹具，优先只放被脚本/测试直接消费的固定样本。
- `builders/`：当某一类学习对象出现多个专用 builder/helper 时，再在此聚合；当前 Phase 11 v0 先保留约定，主入口仍放在根目录。

## 当前对象

- `InteractionTurn`：一次可学习的主线动作单元，连接 capture、knowledge、skill、execution、review。
- `NextStateEvidence`：动作之后出现的统一反馈证据，连接 teacher review、runtime、benchmark、replay、drift 与 LLM suggestion。
- `PreferenceSignal`：从 `NextStateEvidence` 提炼出的结构化偏好信号，显式拆开 evaluative 与 directive 纠偏信息。
- `PreferenceRule`：由重复 signal 晋升出的长期偏好规则，带回链 evidence 和生命周期状态。
- `PreferenceProfile`：当前可生效的偏好快照，按 assist / skill / repair / review / planner 分段聚合。
- `PreferenceProfileBuilder`：把 active `PreferenceRule` 聚合成 `PreferenceProfileSnapshot`，并复用统一冲突排序形成稳定模块顺序。
- `PreferenceRulePromoter`：把默认作用域白名单、风险分级阈值与 teacherConfirmed 门槛固化成可运行的规则晋升器。
- `PreferencePromotionPolicy`：统一承载风险分级、局部 scope、规则过期窗口、自动执行限制与 conflict priority，并作为 promoter / resolver 的共享事实源。
- `PreferenceConflictResolver`：为同组规则提供统一排序和“为何 A 覆盖 B”的结构化解释。
- `PreferenceRollbackService`：把“撤销单条规则”和“回滚到历史 profile snapshot”统一收口成 `preview -> apply` 两阶段，并在 apply 后重建最新 profile。
- `RuleBasedPreferenceSignalExtractor`：规则优先的 v0 提炼器，从 teacher review、replay、drift、benchmark、safety block 中生成基础 signal。
- `PreferenceMemoryStore`：负责把 signals / rules / profiles / audit 落到 `data/preferences`，并维护最小查询索引。
- `DirectiveHintBuilder`：把已接受的 directive signal 扇出成 `assist / skill mapper / repair planner / review suggestion` 可直接消费的 `DirectiveHint`。
- `extract_preference_signals.py`：LLM 辅助的 v1 结构化提炼器，固定消费 `actionSummary / nextStateSummary / nextStateRole / teacherNote` 四段输入，输出 `accepted / needs_review` 报告。
- `TurnLearningEligibility`：主线 / 非主线分类器，负责在偏好提炼前做显式降噪并输出 `reasonCode`。
- `LearningSessionState`：老师侧可见的 learning on/paused/excluded/sensitive-muted 状态。
- `SensitiveScenePolicy`：隐私静默和排除规则。

## 文件落点

- `data/learning/turns/{date}/{sessionId}/{turnId}.json`
- `data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`
- `data/preferences/signals/{date}/{sessionId}/{turnId}.json`
- `data/preferences/rules/{ruleId}.json`
- `data/preferences/profiles/{profileVersion}.json`
- `data/preferences/audit/{date}.jsonl`
- `OpenStaffPreferenceProfileCLI --audit / --rollback-*`：偏好审计与回滚的第一版管理入口。
- `data/preferences/extractions/{date}/{sessionId}/{turnId}--{evidenceId}.json`
- `data/preferences/needs-review/{date}/{sessionId}/{turnId}--{evidenceId}.json`
- `PreferenceRule`、`PreferenceProfile` 与 audit 统一挂在 `data/preferences` 下，不再散落到 `core/orchestrator`。

## v0 约束

- `InteractionTurn` 先接受 `ObservationBundle` 的等价 sidecar：允许仅回链 raw event log、task chunk、窗口上下文和 locator 候选。
- `NextStateEvidence` 只保留摘要和原始引用，不复制 review report、execution log、benchmark review、drift report 的大段正文。
- `PreferenceSignal` 只回链 `evidenceIds`，不复制上游 evidence 正文；directive payload 缺失时允许只保留 evaluative 面。
- `DirectiveHint` 只扇出已被接受且带 directive payload 的 signal；`outcome` 不生成 directive hint。
- `RuleBasedPreferenceSignalExtractor` v0 默认只消费结构化 evidence；当 `taskFamily` 未显式提供时，先退化为 `mode.turnKind` 粗粒度族名。
- `PreferenceRulePromoter` v0 默认只自动晋升 `global / app / taskFamily` 三层作用域；`skillFamily / windowPattern` 先保留为 candidate。
- `PreferencePromotionPolicy` v0 默认把 `style / risk` 视作可长期保留的规则，而 `outcome / procedure / locator / repair` 会附带局部 scope 与过期窗口；其中 `medium` 风险虽允许晋升，但默认不放开自动执行。
- `PreferenceProfileBuilder` v0 默认使用：`outcome -> review`、`procedure -> assist/skill/review/planner`、`locator -> skill/repair/review`、`style -> assist/skill/review`、`risk -> assist/skill/review/planner`、`repair -> repair/review/planner`。
- `extract_preference_signals.py` v1 默认先写提炼报告，不直接覆盖 `PreferenceSignal[]` 事实源；只有通过 `3-vote + schema + actionable hint + confidence floor` 的结果才进入 accepted bucket。
- 历史回填优先复用现有 `benchmark`、`student report`、`teacher feedback` 工件，缺失字段必须显式保留 diagnostics 或空数组，而不是 silently drop。
