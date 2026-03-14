# ClawStaff Phase 11 ADR 列表

> 目标：为 [phase-11-knowledge-reinforcement-roadmap.md](/Users/wangzhenwu/Desktop/code/Personal/OpenStaff/docs/phase-11-knowledge-reinforcement-roadmap.md) 提供需要立项的架构决策清单。这里不是完整 ADR 正文，而是建议的 ADR backlog、编号、核心决策问题与推荐顺序。

## 建议原则

- 优先写“决定数据边界”的 ADR，再写“决定策略行为”的 ADR。
- 先锁定可追溯性和治理边界，再放开偏好自动化。
- ADR 只记录长期稳定决策，不替代实现 TODO。

---

## 推荐优先级

### 第一批：必须先定
- `ADR-0010-interaction-turn-model.md`
- `ADR-0011-mainline-vs-side-turns.md`
- `ADR-0012-next-state-evidence-model.md`
- `ADR-0013-preference-signal-taxonomy.md`

### 第二批：在开始做偏好记忆前锁定
- `ADR-0014-preference-memory-store.md`
- `ADR-0015-preference-rule-promotion-and-governance.md`
- `ADR-0016-policy-assembly-order.md`

### 第三批：在产品接入前锁定
- `ADR-0017-chatgpt-sourced-preference-provenance.md`
- `ADR-0018-personal-preference-benchmark.md`
- `ADR-0019-preference-drift-monitoring.md`

---

## ADR 清单

## ADR-0010：Interaction Turn Model

**建议文件**
- `docs/adr/ADR-0010-interaction-turn-model.md`

**要回答的问题**
- ClawStaff 中一次“可学习回合”到底如何定义？
- `InteractionTurn` 是围绕 UI step、skill step，还是 review 单元组织？
- 一个 turn 是否允许关联多个 evidence、多个 repair action？

**需要比较的方案**
- 方案 A：以 capture step 为中心
- 方案 B：以 skill step 为中心
- 方案 C：以 execute-review 单元为中心

**建议方向**
- 采用“主线行为回合”模型：
  - 允许一个 turn 关联 capture、skill、execution、review 多类链接
  - 保持与具体 UI 事件和 skill artifact 解耦

**不提前定会出的问题**
- 后续 evidence、signal、rule 都没有稳定主键依附

---

## ADR-0011：Mainline vs Side Turns

**建议文件**
- `docs/adr/ADR-0011-mainline-vs-side-turns.md`

**要回答的问题**
- 哪些交互属于偏好学习主线？
- assist 提示、闲聊、背景解释、审阅注释是否计入学习？
- repair 行为是否单独视为主线？

**需要比较的方案**
- 方案 A：所有交互都学习
- 方案 B：仅执行类交互学习
- 方案 C：主线任务推进 + 修复行为学习，其余降噪

**建议方向**
- 采用方案 C

**不提前定会出的问题**
- 会把大量噪声反馈混入偏好记忆

---

## ADR-0012：Next-State Evidence Model

**建议文件**
- `docs/adr/ADR-0012-next-state-evidence-model.md`

**要回答的问题**
- 什么算 `next-state`？
- 老师反馈、系统状态、OpenClaw 执行结果、ChatGPT 建议、benchmark 判定是否统一进入一个 evidence 模型？
- 原始大文本是内嵌还是只保留引用？

**需要比较的方案**
- 方案 A：每种 evidence 单独定义，不做统一抽象
- 方案 B：统一 evidence envelope + source-specific payload

**建议方向**
- 采用方案 B

**不提前定会出的问题**
- 无法形成统一 signal extractor

---

## ADR-0013：Preference Signal Taxonomy

**建议文件**
- `docs/adr/ADR-0013-preference-signal-taxonomy.md`

**要回答的问题**
- 偏好信号最低分类粒度是什么？
- 结果偏好、步骤偏好、风格偏好、风险偏好、repair 偏好如何区分？
- polarity 和 scope 的最小集合是什么？

**需要比较的方案**
- 方案 A：只分 positive / negative
- 方案 B：按行为领域细分，并保留 polarity + scope

**建议方向**
- 采用方案 B

**不提前定会出的问题**
- 后续规则晋升、装配与 benchmark 指标无法稳定设计

---

## ADR-0014：Preference Memory Store

**建议文件**
- `docs/adr/ADR-0014-preference-memory-store.md`

**要回答的问题**
- 偏好记忆存在哪里？
- 规则与信号是否分库存储？
- 用文件存储、轻量数据库，还是混合方案？

**需要比较的方案**
- 方案 A：沿用现有 JSON/JSONL 文件树
- 方案 B：引入 SQLite 作索引与状态层
- 方案 C：文件为事实源，SQLite 为查询索引

**建议方向**
- 倾向方案 C

**理由**
- 文件层利于审计和 Git 管理
- 索引层利于查询、冲突解决与 GUI 展示

---

## ADR-0015：Preference Rule Promotion and Governance

**建议文件**
- `docs/adr/ADR-0015-preference-rule-promotion-and-governance.md`

**要回答的问题**
- 多少个 signal 才能晋升为 rule？
- 高风险规则何时必须人工确认？
- rule 的撤销、覆盖、过期如何管理？

**需要比较的方案**
- 方案 A：立即生效
- 方案 B：阈值晋升 + 风险分级 + 人工确认

**建议方向**
- 采用方案 B

**不提前定会出的问题**
- 系统会快速积累错误偏好并放大

---

## ADR-0016：Policy Assembly Order

**建议文件**
- `docs/adr/ADR-0016-policy-assembly-order.md`

**要回答的问题**
- 偏好规则在 assist、student、skill generation、review、safety 中的应用顺序如何定义？
- 冲突时是 safety 优先还是 user preference 优先？
- app 级偏好和 global 偏好谁先应用？

**需要比较的方案**
- 方案 A：各模块各自决定装配顺序
- 方案 B：统一 assembly pipeline

**建议方向**
- 采用方案 B，且顺序建议为：
  - safety baseline
  - task/app scoped preference
  - global preference
  - runtime context downgrade

**不提前定会出的问题**
- 各模块行为不一致，解释链断裂

---

## ADR-0017：ChatGPT-Sourced Preference Provenance

**建议文件**
- `docs/adr/ADR-0017-chatgpt-sourced-preference-provenance.md`

**要回答的问题**
- ChatGPT 给出的建议是“证据”还是“候选解释”？
- 是否允许它直接生成生效规则？
- 如何记录 prompt、model、response 与人工确认状态？

**需要比较的方案**
- 方案 A：ChatGPT 输出直接入规则
- 方案 B：ChatGPT 输出只作为 candidate evidence，必须经过 extractor + governance

**建议方向**
- 采用方案 B

**不提前定会出的问题**
- 外部模型建议会绕过本地治理，污染偏好记忆

---

## ADR-0018：Personal Preference Benchmark

**建议文件**
- `docs/adr/ADR-0018-personal-preference-benchmark.md`

**要回答的问题**
- 如何衡量“系统越来越懂这个人”？
- benchmark 的 case 是基于 committed 数据、模拟数据，还是混合？
- 哪些指标作为发布门禁？

**需要比较的方案**
- 方案 A：只测执行成功率
- 方案 B：执行成功率 + 偏好命中率双轨

**建议方向**
- 采用方案 B

**不提前定会出的问题**
- 偏好学习没有客观验证，只剩主观感受

---

## ADR-0019：Preference Drift Monitoring

**建议文件**
- `docs/adr/ADR-0019-preference-drift-monitoring.md`

**要回答的问题**
- 如何识别老师偏好变了？
- 什么条件下应标记规则“过时”“弱化”“待复核”？
- 漂移监控触发后，是自动降权还是只提醒？

**需要比较的方案**
- 方案 A：无漂移监控，规则永久有效
- 方案 B：基于命中率、override rate、时间衰减的监控

**建议方向**
- 采用方案 B

**不提前定会出的问题**
- 系统会长期保留过时偏好，导致“越学越错”

---

## 建议补充 ADR

如果 Phase 11 中后段开始涉及更多系统复杂度，建议追加：

- `ADR-0020-preference-audit-and-rollback.md`
- `ADR-0021-preference-aware-safety-priority.md`
- `ADR-0022-policy-assembly-observability.md`

这些 ADR 可以在第一批偏好装配完成后再写，不必阻塞 Phase 11 前半段。

---

## 推荐落地顺序

1. 先写 `ADR-0010` 到 `ADR-0013`
2. 再写 `ADR-0014` 到 `ADR-0016`
3. 当 ChatGPT 偏好提炼和 benchmark 真正开始落地时，再写 `ADR-0017` 到 `ADR-0019`

---

## 一句话结论

Phase 11 的 ADR 核心不是“要不要学”，而是先回答清楚：

**什么是一次可学习回合、什么是有效 next-state、什么偏好可以进入长期记忆、以及这些偏好如何在不破坏安全边界的前提下真正影响系统行为。**
