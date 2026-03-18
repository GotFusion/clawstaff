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
- `TurnLearningEligibility`：主线 / 非主线分类器，负责在偏好提炼前做显式降噪并输出 `reasonCode`。
- `LearningSessionState`：老师侧可见的 learning on/paused/excluded/sensitive-muted 状态。
- `SensitiveScenePolicy`：隐私静默和排除规则。

## 文件落点

- `data/learning/turns/{date}/{sessionId}/{turnId}.json`
- `data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`
- 未来 `PreferenceSignal`、`PreferenceProfile` 也统一挂在 `data/learning` / `data/preferences` 下，不再散落到 `core/storage` 或 `core/orchestrator`。

## v0 约束

- `InteractionTurn` 先接受 `ObservationBundle` 的等价 sidecar：允许仅回链 raw event log、task chunk、窗口上下文和 locator 候选。
- `NextStateEvidence` 只保留摘要和原始引用，不复制 review report、execution log、benchmark review、drift report 的大段正文。
- 历史回填优先复用现有 `benchmark`、`student report`、`teacher feedback` 工件，缺失字段必须显式保留 diagnostics 或空数组，而不是 silently drop。
