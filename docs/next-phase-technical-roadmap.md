# OpenStaff 下一版路线图（市场与研究对齐版）

版本：v0.12.0-roadmap  
更新时间：2026-03-26  
状态：本文件替代旧版 `v0.7.0-roadmap`

## 1. 路线判断

结合近一周对 OpenClaw、类似产品和相关研究的补充调研，OpenStaff 下一版不应继续沿着“通用桌面 Agent 功能堆叠”推进，而应收敛成一条更清晰的主线：

1. 把老师的真实电脑操作沉淀成可追溯、可修复、可迁移的个人知识资产。
2. 把 OpenClaw 作为执行内核与 gateway，而不是承担学习层。
3. 把个性化优先做成“零训练或近零训练”的记忆、检索、策略装配能力，而不是立即投入模型权重训练。
4. 把隐私、暂停、排除、保留周期、审计和恢复能力视为产品基线，而不是补充项。

这条路线来自 3 组外部信号：

- OpenClaw 最近的正式能力重心在 `gateway / nodes / plugins / skills / operations`，说明它更像执行平台和控制面，而不是老师示教学习层。
- Recall、Screenpipe、Limitless、OpenAdapt 这些相邻产品说明，市场真正重视的是本地优先、可见状态、可查询历史、可导出与快速修复，而不是“更像全能操作系统”。
- PersonalAlign、PAHF、TierMem、RF-Mem、MemGUI-Bench、GUIGuard 等研究说明，当前最有工程价值的路线是显式记忆、provenance、推理时自适应检索、结构化反馈回写和隐私治理，而不是先做训练基础设施。

---

## 2. 下一版产品定位

### 2.1 OpenStaff 应明确承担的角色

OpenStaff 下一版应明确定位为：

- OpenClaw 的 `teaching layer`
- OpenClaw 的 `personal desktop memory layer`
- OpenClaw 的 `skill foundry`
- OpenClaw 的 `review and repair cockpit`

一句话概括：

> OpenStaff 负责观察老师、沉淀个人知识、生成更稳的桌面技能、把执行反馈回写成个性化策略；OpenClaw 负责技能运行、节点连接、工具调用、远程与调度。

### 2.2 下一版不主动扩张的方向

以下方向不应作为下一版主线：

- 自研训练器、在线强化学习或权重微调基础设施
- 全天候无边界全桌面录屏
- 云端为中心的个人记忆托管
- 大而全的跨设备同步优先级
- 继续扩展大量 UI/偏好功能而不先完成主链路真机验收

---

## 3. 市场与研究对齐后的设计原则

### 3.1 本地优先，文件为事实源

- 原始事件、Observation sidecar、KnowledgeItem、SkillArtifact、ExecutionReview、PreferenceRule 都以本地文件为事实源。
- SQLite、FTS、embedding、cache 仅作为索引和加速层，不作为唯一事实源。
- 任意关键学习结果都应支持导出、校验、恢复。

### 3.2 学习层与执行层强边界

- OpenStaff 不直接膨胀成执行平台。
- OpenClaw 不直接吞并老师示教、偏好记忆和审阅修复逻辑。
- 跨边界只暴露稳定工件与 gateway/request-response 合同。

### 3.3 零训练个性化优先

- 第一优先是通过 `memory + retrieval + policy assembly + teacher quick feedback` 获得个性化。
- 只有在 memory-only 路线稳定、评测清晰后，才允许探索训练型 personalization。

### 3.4 先做可复现，再做更智能

- 先保证一次教学得到的知识可以稳定 replay、repair、review。
- 再保证 assist 能利用个人历史做更像老师的下一步推荐。
- 最后才扩大 autonomous student 的自动放权范围。

### 3.5 隐私和暂停必须可见

- 用户必须在一眼内知道系统是否在学习。
- 任意时刻必须能暂停、排除 app/窗口、查看保留策略并删除学习工件。
- 敏感场景应默认降级或静默，而不是依赖后验补救。

### 3.6 原始事实与摘要必须双层共存

- 原始观察包负责“当时发生了什么”。
- 摘要、规则、skill 和偏好只负责“系统如何理解与复用”。
- 任意自动总结、规则晋升和 repair 建议都应能回链到原始证据。

---

## 4. 下一版 North Star

下一版的目标不是“多做几个模式功能”，而是把下面这条链路做成稳定资产：

`Teacher Observation -> Observation Bundle -> Interaction Turn -> Knowledge Item -> Skill Artifact -> Replay Verify -> OpenClaw Execute -> Review -> Preference Assembly`

### 4.1 North Star 指标

下一版对外只追 5 个核心指标：

1. `real_task_capture_coverage`
   - 真实教学任务中，关键步骤可落成 Observation Bundle 的比例。
2. `replay_resolution_success_rate`
   - 真实历史步骤 dry-run 解析成功率。
3. `first_pass_skill_execution_rate`
   - skill 在首次执行时无需人工修 locator 的成功率。
4. `teacher_feedback_efficiency`
   - 快评完成率与中位反馈耗时。
5. `unsafe_auto_execution_regression`
   - 自动执行导致的安全回归数量，目标持续保持为 `0`。

### 4.2 发布门槛

下一版在发布前至少满足：

- `make test-swift`
- `make test`
- `make release-preflight`
- 真实 3 类 app 的语义抓取验收
- 真实 10 条历史步骤 replay 验收
- 真实 3 条 skill 的 OpenClaw 执行联调
- 真实 20 条 review 的 quick feedback 验收

---

## 5. 里程碑总览

建议下一版按 `M1 -> M5` 顺序推进，`M6` 仅作为可选研究支线。

| 里程碑 | 核心目标 | 预计时长 | 是否发布阻塞 |
|---|---|---:|---|
| M1 | 主干收口与单一事实源对齐 | 1 周 | 是 |
| M2 | Observation Bundle 与 Trace Graph | 1-2 周 | 是 |
| M3 | Skill Foundry、Replay、Repair 真机闭环 | 1-2 周 | 是 |
| M4 | 零训练个性化 v1 | 1-2 周 | 是 |
| M5 | Gateway / 查询边界 / 数据治理 | 1 周 | 是 |
| M6 | 训练型 personalization 研究支线 | 研究项 | 否 |

---

## 6. 里程碑明细

### M1：主干收口与单一事实源对齐

#### 目标

停止“边扩边漂移”，先把当前仓库变成一个可稳定推进的基线。

#### 为什么现在必须先做

- 当前文档存在旧版 roadmap 与最新实现进展不完全同步的问题。
- 当前主干仍有测试回归与未收口改动，继续扩功能只会放大不确定性。
- 市场与研究都在强调“可信资产”和“稳定控制边界”，不是“先把功能全堆出来”。

#### TODO

- [x] 修复当前 Swift 测试回归，恢复 `make test-swift` 全绿。
  - 2026-03-26 已在 `main` 上验证 `make test-swift` 通过，当前为 `110` 个 Swift 测试全绿。
- [x] 统一 `docs/project-plan-and-progress.md`、本路线图、`implementation-todo-checklist.md` 的下一步叙事。
- [x] 统一主链路日志 ID 规范：`traceId / sessionId / taskId / stepId / turnId`。
  - 2026-03-26 已在 `docs/coding-conventions.md` 固化字段语义、最小字段和透传规则。
  - 2026-03-26 已把 `student / assist / openclaw` 的结构化日志 writer 收口到共享 JSONL append writer，并同步补齐 `stepId` / `turnId` 透传位。
- [ ] 明确哪些 Phase 11 能力已进入主线，哪些仍为 feature flag 或研究能力。
- [ ] 补齐关键决策 ADR 缺口，并把旧文档中的过时表述下线。
- [ ] 把当前发布前检查清单与真实门槛保持一致。

#### 输出物

- `docs/project-plan-and-progress.md`
- `docs/implementation-todo-checklist.md`
- `docs/adr/*`
- 统一日志/ID 规范补充说明

#### 退出标准

- [x] `make test-swift` 通过
- [x] `make test` 通过
- [ ] `make release-preflight` 通过
- [ ] 三份主文档对当前阶段描述一致

---

### M2：Observation Bundle 与 Trace Graph

#### 目标

把“点击坐标 + 文本摘要”升级成能长期支撑学习、repair、审计与导出的个人观察资产。

#### 对齐的外部信号

- Recall、Screenpipe、OpenAdapt 都说明：观察层如果只保留单一坐标或简单日志，很快会失去长期价值。
- TierMem、MemGUI-Bench 指出：记忆必须保留 provenance，并允许从摘要回溯原始事实。

#### TODO

- [ ] 为每个可学习动作补齐 `ObservationBundle` 或等价 sidecar：
  - screenshot refs
  - window signature
  - AX snapshot refs
  - OCR/text anchor summary
  - relative point + absolute point
  - browser URL/title（若可得）
  - semantic target candidates refs
- [ ] 明确 `ObservationBundle` 与 `InteractionTurn` 的职责分层。
- [ ] 让 teaching / assist / student 三类主线行为都能稳定回链 Observation 证据。
- [ ] 完成 Finder / Safari / Terminal 三类 app 的真实语义抓取验收。
- [ ] 为数据层加入 retention、cleanup 和 selective delete 策略。
- [ ] 为学习状态面板补上“保留周期 / 最近清理 / 当前排除规则”可见说明。

#### 输出物

- `core/learning/` 下 Observation/Trace 相关契约与文档
- `apps/macos/Sources/OpenStaffCaptureCLI/*`
- `apps/macos/Sources/OpenStaffApp/ModeObservationCapture.swift`
- `docs/ux/*`
- 数据治理文档与清理脚本

#### 退出标准

- [ ] 真实 20 条教学主线步骤都具备 Observation refs
- [ ] Finder / Safari / Terminal 三类 app 可稳定抓到语义属性
- [ ] 被排除场景不会继续写入学习工件
- [ ] 数据可按 session / task 精确导出与删除

---

### M3：Skill Foundry、Replay、Repair 真机闭环

#### 目标

把 OpenStaff 从“能产出 skill”推进到“能稳定产出、验证、修复并交给 OpenClaw 执行”。

#### 对齐的外部信号

- OpenClaw 最近的动向说明执行层需要稳定工件和清晰 provenance，而不是在运行时猜。
- OpenAdapt 和录制式自动化产品表明，真正决定可用性的不是录到，而是失败后能不能快速修。

#### TODO

- [ ] 正式把动作拆成 `nativeAction` 与 `guiAction` 两类。
- [ ] `guiAction` 强制输出多候选 locator：
  - `AX`
  - `role/title/text anchor`
  - `image anchor`
  - `relative coordinate`
  - `absolute coordinate`
- [ ] `nativeAction` 优先接入 `CLI / AppleScript / app-specific API / Shortcuts` 路由。
- [ ] skill metadata 补齐：
  - source trace
  - observation refs
  - action kind
  - applied preference rules
  - repair version
- [ ] 对真实 10 条历史步骤做 replay dry-run，形成结构化通过率报告。
- [ ] 对真实 3 条个人任务跑通 OpenClaw 执行、失败回收、repair 建议和老师复核。
- [ ] 完成 GUI 无终端的一次教学 -> 辅助 -> 学生模式演示。

#### 输出物

- `scripts/skills/openclaw_skill_mapper.py`
- `core/executor/*`
- `core/repair/*`
- `apps/macos/Sources/OpenStaffOpenClawCLI/*`
- GUI 的 skill / repair / review 面板增强

#### 退出标准

- [ ] 真实 10 条历史步骤 replay 成功率达到可人工接受水平
- [ ] 真实 3 条个人 skill 能通过 OpenClaw 执行联调
- [ ] 失败原因均有结构化分类，不再出现大面积“纯文本失败”
- [ ] 一次完整三模式演示不依赖终端手工拼接

---

### M4：零训练个性化 v1

#### 目标

在不修改模型权重的前提下，让 OpenStaff 在 assist、skill 生成、repair 和 review 上开始表现出“更像这个老师”的行为。

#### 对齐的外部信号

- PersonalAlign、PAHF 说明个性化 GUI agent 的关键在长期个人记录、澄清、反馈回写和层次记忆。
- RF-Mem、Structured Distillation 说明推理时检索和多层记忆整理，是当前最现实的低成本路线。

#### TODO

- [ ] 让 assist predictor 从“相似知识检索”升级为“个人习惯优先的自适应检索”。
- [ ] 将 quick feedback、review note、repair note 稳定回写为 `PreferenceSignal`。
- [ ] 补齐真实 assist 历史 turn 回填，而不只依赖 teaching / student 样本。
- [ ] 把 `PreferenceProfile` 的装配严格限制在 inference-time policy assembly，不直接写死进 skill。
- [ ] 为 `assist / skill / repair / review` 四个模块分别建立 benchmark case。
- [ ] 用 `PolicyAssemblyDecision` 和 drift monitor 回答“这次为什么这么做”与“最近为什么不再这么做”。
- [ ] 完成 20 条真实 review 的 quick feedback 验收，并补自由文本备注成功率统计。

#### 输出物

- `core/learning/*`
- `core/storage/PreferenceMemoryStore.swift`
- `core/orchestrator/PreferenceAwareAssistPredictor.swift`
- `core/repair/PreferenceAwareSkillRepairPlanner.swift`
- `OpenStaffExecutionReviewCLI`
- benchmark case 与 gate 脚本

#### 退出标准

- [ ] 抽样 20 次 review 中至少 16 次可只靠 quick actions 完成
- [ ] 单次反馈中位耗时不高于 8 秒
- [ ] 自由文本备注结构化成功率达到阶段目标
- [ ] `unsafeAutoExecutionRegression = 0`
- [ ] 偏好命中与覆盖率可用 benchmark 稳定回归

---

### M5：Gateway / 查询边界 / 数据治理

#### 目标

把 OpenStaff 的学习资产真正做成可被 OpenClaw、外部 worker、未来插件和迁移工具消费的稳定边界。

#### 对齐的外部信号

- OpenClaw 当前明显在做平台化边界清理。
- Screenpipe、Limitless 都在强调 API / MCP / exportable memory。
- 市场现实表明，能否迁移和恢复个人资产，直接影响产品生命周期。

#### TODO

- [ ] 固化公开查询能力：
  - `turns.search`
  - `turns.get`
  - `observations.get`
  - `preferences.listRules`
  - `preferences.listAssemblyDecisions`
  - `learningBundles.export`
- [ ] 明确外部只依赖 contracts，不依赖桌面 App 内部对象图。
- [ ] 扩充 learning bundle，确保 observation refs、skill provenance、review links 一并可导出恢复。
- [ ] 完成恢复后完整 rebuild 验证：
  - preference profile rebuild
  - replay verify
  - benchmark spot check
- [ ] 补齐 retention / cleanup / data deletion 的审计日志。
- [ ] 文档化 OpenClaw companion 接口和最小集成样例。

#### 输出物

- `core/storage/LearningGateway.swift`
- `docs/integrations/*`
- `docs/learning-bundle-spec.md`
- 导出 / 校验 / 恢复脚本
- 对外集成文档

#### 退出标准

- [ ] 外部消费者可只依赖公开 contracts 完成查询与导出
- [ ] bundle 可导出、校验、恢复，并重建 profile 与关键索引
- [ ] 数据删除、暂停、排除和恢复均有审计轨迹

---

### M6：训练型 personalization 研究支线（可选）

#### 目标

只在 `M1-M5` 稳定后，才探索训练型 personalization 是否值得投入。

#### 原则

- 仅使用脱敏、可离线复现、可撤销的数据集。
- 不影响主线产品节奏。
- 必须与 `memory-only` 基线做对照，而不是“先上训练再说”。

#### TODO

- [ ] 建立 memory-only personalization 基线报告。
- [ ] 选取训练型路线候选，如 RFT 或 preference policy fine-tuning。
- [ ] 在离线 benchmark 上对比：
  - 执行成功率
  - token/cost
  - 误操作率
  - 可解释性
  - 回滚成本
- [ ] 形成 go / no-go 决策 ADR。

#### 退出标准

- [ ] 训练路线在至少一个关键指标上显著优于 memory-only
- [ ] 同时不破坏隐私、审计和回滚边界

---

## 7. 下一版的明确取舍

### 7.1 优先做

- 主链路稳定
- 真机采集与 replay 验收
- 技能修复闭环
- 零训练个性化
- 隐私 / 保留 / 导出 / 恢复
- 对外查询边界

### 7.2 暂缓做

- 长时全天候桌面录屏默认开启
- 多设备云同步优先级
- 大规模训练基础设施
- 无门控自动探索式 student 执行
- 复杂视觉识别与重量级 OCR 作为默认依赖

---

## 8. 版本验收清单

下一版完成的定义不是“文档写完”，而是：

- [ ] 老师一次真实教学任务可以沉淀为完整 trace
- [ ] 该 trace 可以稳定生成带 provenance 的 skill
- [ ] 该 skill 可以被 replay 验证并交给 OpenClaw 执行
- [ ] 执行后的 review 与 quick feedback 可以回写为个性化策略
- [ ] 这些策略在 assist / skill / repair / review 四处可解释生效
- [ ] 学习工件可暂停、排除、导出、恢复、删除并被审计

---

## 9. 对齐来源（供后续持续跟踪）

### OpenClaw

- GitHub Releases: <https://github.com/openclaw/openclaw/releases>
- Docs Hubs: <https://docs.openclaw.ai/start/hubs>
- Gateway Security: <https://docs.openclaw.ai/gateway/security>

### 类似产品

- Microsoft Recall overview: <https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/recall/>
- Microsoft Manage Recall: <https://learn.microsoft.com/en-us/windows/client-management/manage-recall>
- Screenpipe changelog: <https://screenpi.pe/changelog>
- Screenpipe MCP server: <https://docs.screenpi.pe/mcp-server>
- Limitless home: <https://www.limitless.ai/>
- Limitless Developers: <https://www.limitless.ai/developers>
- OpenAdapt: <https://github.com/OpenAdaptAI/OpenAdapt>

### 研究参考

- PersonalAlign: <https://arxiv.org/abs/2601.09636>
- Learning Personalized Agents from Human Feedback: <https://arxiv.org/abs/2602.16173>
- TierMem: <https://arxiv.org/abs/2602.17913>
- RF-Mem: <https://arxiv.org/abs/2603.09250>
- Structured Distillation for Personalized Agent Memory: <https://arxiv.org/abs/2603.13017>
- MemGUI-Bench: <https://arxiv.org/abs/2602.06075>
- GUIGuard: <https://arxiv.org/abs/2601.18842>
- A Survey of Personalization: From RAG to Agent: <https://arxiv.org/abs/2504.10147>
