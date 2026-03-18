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
- `RuleBasedPreferenceSignalExtractor`：规则优先的 v0 提炼器，从 teacher review、replay、drift、benchmark、safety block 中生成基础 signal。
- `DirectiveHintBuilder`：把已接受的 directive signal 扇出成 `assist / skill mapper / repair planner / review suggestion` 可直接消费的 `DirectiveHint`。
- `extract_preference_signals.py`：LLM 辅助的 v1 结构化提炼器，固定消费 `actionSummary / nextStateSummary / nextStateRole / teacherNote` 四段输入，输出 `accepted / needs_review` 报告。
- `TurnLearningEligibility`：主线 / 非主线分类器，负责在偏好提炼前做显式降噪并输出 `reasonCode`。
- `LearningSessionState`：老师侧可见的 learning on/paused/excluded/sensitive-muted 状态。
- `SensitiveScenePolicy`：隐私静默和排除规则。

## 文件落点

- `data/learning/turns/{date}/{sessionId}/{turnId}.json`
- `data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`
- `data/preferences/signals/{date}/{sessionId}/{turnId}.json`
- `data/preferences/extractions/{date}/{sessionId}/{turnId}--{evidenceId}.json`
- `data/preferences/needs-review/{date}/{sessionId}/{turnId}--{evidenceId}.json`
- 后续 `PreferenceRule`、`PreferenceProfile` 也统一挂在 `data/preferences` 下，不再散落到 `core/storage` 或 `core/orchestrator`。

## v0 约束

- `InteractionTurn` 先接受 `ObservationBundle` 的等价 sidecar：允许仅回链 raw event log、task chunk、窗口上下文和 locator 候选。
- `NextStateEvidence` 只保留摘要和原始引用，不复制 review report、execution log、benchmark review、drift report 的大段正文。
- `PreferenceSignal` 只回链 `evidenceIds`，不复制上游 evidence 正文；directive payload 缺失时允许只保留 evaluative 面。
- `DirectiveHint` 只扇出已被接受且带 directive payload 的 signal；`outcome` 不生成 directive hint。
- `RuleBasedPreferenceSignalExtractor` v0 默认只消费结构化 evidence；当 `taskFamily` 未显式提供时，先退化为 `mode.turnKind` 粗粒度族名。
- `extract_preference_signals.py` v1 默认先写提炼报告，不直接覆盖 `PreferenceSignal[]` 事实源；只有通过 `3-vote + schema + actionable hint + confidence floor` 的结果才进入 accepted bucket。
- 历史回填优先复用现有 `benchmark`、`student report`、`teacher feedback` 工件，缺失字段必须显式保留 diagnostics 或空数组，而不是 silently drop。
