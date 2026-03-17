# OpenStaff 深入调研：基于反馈的轻量持续学习层与零训练方案

版本：v0.1  
更新时间：2026-03-17  
适用对象：OpenStaff / ClawStaff 下一阶段学习层规划

---

## 1. 先回答核心问题

### 1.1 能不能做“零训练模型”的持续学习？

**能，而且这已经不是边缘路线。**

但这里的“零训练”要分清三层：

| 层级 | 定义 | 是否属于“零训练” |
|---|---|---|
| A. 严格零训练 | 不更新底模权重，也不训练新的奖励器/侧模；只更新外部 memory、prompt、规则、技能库、检索结果 | **是，最严格意义上的零训练** |
| B. 冻结底模 + 轻量侧模 | 不训练主 LLM，但会训练小型 case selector、reranker、reward/guidance policy | **部分是**；不属于“完全零训练”，但仍然不是传统大模型训练 |
| C. 传统训练式持续学习 | 继续做 SFT、DPO、RL、LoRA、reward model 或在线 policy 更新 | **不是零训练** |

如果把这个问题落到 OpenStaff：

- **短中期最推荐的是 A 层方案。**
- **当 A 层收益吃满后，可以考虑少量 B 层。**
- **C 层应放到更后面，只作为上限增强手段。**

### 1.2 “零训练”不等于“不学习”

这是最关键的概念。

对个人助理来说，“学习”完全可以不发生在模型参数里，而发生在：

1. **长期记忆更新**
2. **偏好规则晋升**
3. **经验案例库扩充**
4. **技能选择/排序变化**
5. **提示词与 planner policy 重写**
6. **解码时约束或偏好引导**

也就是说：

> 零训练方案本质上是“把学习从权重空间搬到外部状态空间”。

这恰好非常适合 OpenStaff，因为 OpenStaff 本来就有：

- capture 证据链
- procedure / skill / review 分层
- repair / drift / benchmark / safety

这些都更适合被做成**可审计外部学习层**，而不是一上来就变成不可解释的参数更新。

---

## 2. 这类轻量持续学习层，学术界现在主要在做什么

截至 **2026-03-17**，相关工作大致收敛为 5 类。

### 2.1 语言反馈反思型：不改权重，改“下一次怎么做”

这类工作把反馈写成文字反思、经验卡片或抽象规则，在下一轮任务中检索使用。

| 工作 | 时间 | 核心思想 | 是否更新权重 |
|---|---|---|---|
| [Reflexion](https://arxiv.org/abs/2303.11366) | 2023-03-20 | 把环境反馈转成 verbal reflection，存入 episodic memory，下次用语言反思改善行为 | 否 |
| [Self-Refine](https://arxiv.org/abs/2303.17651) | 2023-03-30 | 同一模型先生成，再自评，再迭代修正，不需要额外训练 | 否 |
| [CLIN](https://arxiv.org/abs/2310.10134) | 2023-10-16 | 用持续更新的 textual memory，尤其是 causal abstractions，而不是一般提示语 | 否 |
| [ExpeL](https://arxiv.org/abs/2308.10144) | 2023-08-20 | 从多次任务经验中提炼自然语言知识，推理时召回使用 | 否 |
| [Voyager](https://arxiv.org/abs/2305.16291) | 2023-05-25 | 累积可执行 skill library，靠技能库和迭代 prompting 做 lifelong learning | 否 |
| [MPO](https://arxiv.org/abs/2503.02682) | 2025-03-04 | 从执行反馈中持续优化 meta plans，而不是重训 agent | 否 |

这条线对 OpenStaff 的意义非常大，因为它与“老师反馈 -> 学生改下次行为”的产品形态天然同构。

最值得吸收的共同点是：

1. 反馈不一定要压成一个 reward 分数；
2. 语言反馈往往比标量 reward 信息密度更高；
3. 最有效的学习结果通常不是“新权重”，而是：
   - 一条 lesson
   - 一段反思
   - 一个 skill
   - 一条 planner rule
   - 一个 failure pattern

### 2.2 偏好抽取型：从用户编辑中学，而不是人工标数据训练

这类工作非常适合你的项目，因为老师的“修正”“接管”“改步骤”“改输出”本身就是偏好样本。

| 工作 | 时间 | 核心思想 | 是否更新权重 |
|---|---|---|---|
| [Aligning LLM Agents by Learning Latent Preference from User Edits](https://arxiv.org/abs/2404.15269) | 2024-04-23 | 用用户 edit 历史推断 latent preference，再检索相关偏好描述用于后续生成 | 否 |
| [LaMP](https://arxiv.org/abs/2304.11406) | 2023-04-22 | personalization 的关键不是“换模型”，而是把个人上下文正确取回并正确使用 | 否 |
| [LaMP-QA](https://arxiv.org/abs/2506.00137) | 2025-06-01 | 长答案 personalization 更依赖高质量 user-specific retrieval | 否 |
| [CUPID](https://arxiv.org/abs/2508.01674) | 2025-08-04 | 强模型并不会自动稳定理解个体偏好，需要显式 personalization evaluation | 否 |
| [PersonaLens](https://arxiv.org/abs/2506.09902) | 2025-06-11 | personalization 需要独立测，不应默认把基础模型泛化能力当成用户理解能力 | 否 |

这类工作的结论很适合直接翻译成 OpenStaff 设计原则：

1. **老师 edit 是头号高价值反馈。**
2. **偏好不要只存原始日志，要抽成可读规则。**
3. **偏好要按场景检索，而不是全量塞 prompt。**
4. **偏好应允许老师查看、修改、撤销。**

### 2.3 记忆层驱动型：学习发生在 memory rewrite，而不是模型 rewrite

这条线是最近两年最值得产品团队关注的方向。

| 工作 / 框架 | 时间 | 核心思想 | 是否更新权重 |
|---|---|---|---|
| [LangMem](https://langchain-ai.github.io/langmem/) | 2025 docs | 将 memory 分成 semantic / episodic / procedural，并支持 hot path 与 background memory formation | 否 |
| [Letta Memory / MemFS](https://docs.letta.com/letta-code/memory) | 2025 docs | 用可编辑 memory blocks / git-backed MemFS，让 agent 自己维护长期记忆 | 否 |
| [Mem0 / OpenMemory](https://docs.mem0.ai/) | 2025 docs | 提供 add / search / update / delete / rerank 的记忆层，把持续学习做成基础设施 | 否 |
| [A-MEM](https://arxiv.org/abs/2502.12110) | 2025-02-18 | 不只存 memory，还主动组织 memory 结构和关系 | 否 |
| [E-mem](https://arxiv.org/abs/2601.21714) | 2026-01-29 | 支持 episodic context reconstruction，避免压缩记忆丢失关键上下文 | 否 |
| [MAGNET](https://arxiv.org/abs/2601.19199) | 2026-01-27 | 用双层 memory 抵抗 GUI 变化，把稳定语义和程序意图沉淀下来 | 论文摘要未强调权重更新，主轴是 memory evolution |

这条线几乎直接就是 OpenStaff 的下一阶段答案：

- 教学模式产生 observation / episode；
- 辅助模式产生 accept / reject / edit；
- 学生模式产生 success / failure / repair；
- 后台 job 把它们重写成 memory / rule / skill patch；
- 下次执行时检索这些内容，而不是重新训练底模。

### 2.4 解码时对齐型：不改模型，只在生成当下施加偏好

这类方法的思想是：用户偏好可以在 inference / decoding 阶段加进去，不必先训练一个个性化模型。

| 工作 | 时间 | 核心思想 | 是否更新底模 |
|---|---|---|---|
| [DeAL](https://arxiv.org/abs/2402.06147) | 2024-02-05 | 把 alignment 视为 decoding-time search，可用自定义 reward/constraint 指导生成 | 否 |
| [PAD](https://arxiv.org/abs/2410.04070) | 2024-10-05 | Personalized Alignment at Decoding-time；在推理期按偏好引导输出，无需额外个性化训练 | 否 |
| [PITA](https://arxiv.org/abs/2507.20067) | 2025-07-26 | inference-time alignment，直接融入 preference feedback，不依赖预训练 reward model | 否，但会学习小 guidance policy |

这类方法对 OpenStaff 的启发主要不在“写论文式 token-level 搜索”，而在产品层：

1. 某些偏好并不需要变成长期规则；
2. 可以只在当前任务/当前会话/当前风险等级下施加；
3. 很适合做：
   - 辅助模式确认话术
   - 学生模式审阅摘要风格
   - 高风险动作解释模板
   - 老师偏好的步骤呈现顺序

### 2.5 真正训练型：作为上限参考，但不应现在就主线投入

| 工作 | 时间 | 核心思想 | 是否训练 |
|---|---|---|---|
| [OpenClaw-RL](https://arxiv.org/abs/2603.10165) | 2026-03-10 | 把 next-state signals 统一为 evaluative + directive，异步在线 RL | 是 |
| [UI-Mem](https://arxiv.org/abs/2602.05832) | 2026-02-05 | 在 GUI online RL 中加入 hierarchical experience memory 和 self-evolving loop | 是 |
| [RiCL](https://arxiv.org/abs/2505.09925) | 2025-05-15 | 从 noisy human feedback 做 reinforced interactive continual learning | 是 |
| [SELF](https://arxiv.org/abs/2310.00533) | 2023-10-01 | 先用语言反馈自改数据，再 fine-tune 自己 | 是 |

这些工作很重要，但它们更多是在回答：

> 如果你愿意建设训练基础设施，持续学习还能再往前推多远？

而你当前更需要回答的是：

> 如果先不建设训练基础设施，能不能先把 70% 到 85% 的产品价值做出来？

这两个问题不要混在一起。

---

## 3. 理论上，语言反馈为什么值得优先于纯 reward

如果只看最近理论工作，一个非常重要的信号来自 [Provably Learning from Language Feedback](https://arxiv.org/abs/2506.10341)。

这篇工作给出的关键结论是：

- 学习问题可以正式建模为 `Learning from Language Feedback (LLF)`；
- 在某些条件下，**rich language feedback 可能比 scalar reward 学得快很多**；
- 论文甚至给出“可以比 reward 学习指数级更快”的情形。

对 OpenStaff 来说，这个理论很重要，因为你的项目天然就拥有大量语言型或结构化反馈：

- “这一步可以，但你应该先切到 Safari 再点”
- “不要用坐标，优先找按钮标题”
- “这个任务可以自动执行，但涉及支付必须确认”
- “我改的是输出顺序，不是任务目标”

这些信息如果只压成：

- `pass`
- `fail`
- `reward = -1`

信息损失会非常大。

所以 OpenStaff 的轻量学习层，应该明确坚持：

1. **保留 evaluative signal**
2. **更要保留 directive signal**
3. **directive 应比 reward 更优先做结构化提炼**

---

## 4. 对 OpenStaff 最有用的“零训练持续学习”方案，到底长什么样

### 4.1 推荐的总体答案

我对项目的建议非常明确：

> **OpenStaff 的下一阶段学习层，应该默认按“零训练 memory-first”方案实现。**

也就是：

`强模型推理`
`+`
`learning trace`
`+`
`preference / episode / repair memory`
`+`
`prompt & planner rewrite`
`+`
`skill / policy retrieval`
`+`
`少量异步验证`

而不是：

`强模型推理`
`+`
`大量反馈`
`+`
`立即在线训练`

### 4.2 这层学习，应该更新哪些对象

建议把 OpenStaff 的“学习结果”限定为 6 类外部对象：

1. **PreferenceRule**
   - 例如：
   - “涉及系统设置或支付必须确认”
   - “搜索任务优先用 Safari，不优先 Chrome”
   - “给老师的总结先写结论，再写日志”

2. **EpisodeCard**
   - 记录一次成功或失败的情景化经验：
   - 场景
   - 步骤摘要
   - 关键判断
   - 成败原因
   - 是否适合复用

3. **RepairLesson**
   - 专门沉淀 repair 经验：
   - 哪类 locator 容易漂移
   - 哪类 app 更新后文本锚点更稳
   - 哪类失败应该要求 re-teach

4. **PlannerPatch**
   - 对 plan / meta-plan 的补丁：
   - 哪类任务顺序更稳
   - 哪类子任务应该拆开
   - 哪类步骤需要先检查前置条件

5. **PromptPatch**
   - 对 assist / review / student 模块的提示词规则补丁。

6. **SkillSelectionHeuristic**
   - 哪类历史 skill 更该优先召回；
   - 哪类低置信 skill 需要降权。

这些对象都可以在**不更新底模权重**的前提下持续学习。

### 4.3 推荐的数据闭环

建议闭环收敛为下面 7 步：

1. **记录 feedback trace**
   - 来源：
     - 通过 / 驳回
     - edit
     - repair locator
     - reteach
     - takeover
     - override risk gate

2. **提炼 evaluative / directive**
   - `evaluative`: `pass / fail / neutral`
   - `directive`: 1-3 句可执行纠偏建议

3. **归因**
   - 这次问题来自：
     - 观察不足
     - skill 选择不对
     - 定位漂移
     - planner 顺序不佳
     - 输出风格不符合偏好
     - 安全阈值不对

4. **转写为 memory candidate**
   - `PreferenceRuleCandidate`
   - `EpisodeCardCandidate`
   - `RepairLessonCandidate`
   - `PromptPatchCandidate`

5. **异步验证**
   - 通过：
     - 多次复现
     - 近邻任务支持
     - benchmark shadow eval
     - 投票一致性

6. **晋升 / 降级 / 隔离**
   - `promoted`
   - `needs_review`
   - `quarantined`

7. **在下一次任务中检索生效**
   - 仅对相关任务、相关 app、相关风险等级生效。

---

## 5. 具体到论文层面，哪些是“真正适合 OpenStaff 抄作业”的

### 5.1 第一优先级：真正值得直接借鉴

#### 1. [Reflexion](https://arxiv.org/abs/2303.11366)

最值得借鉴的点：

- 反馈可以是文字也可以是标量；
- 反思文字本身就是学习载体；
- 不需要更新模型权重。

翻译到 OpenStaff：

- 老师的自然语言批注不要只存原文；
- 应提炼成下一次可召回的 reflection / lesson。

#### 2. [CLIN](https://arxiv.org/abs/2310.10134)

最值得借鉴的点：

- 不要存泛泛而谈的 hints；
- 应存更稳定的 causal abstractions。

翻译到 OpenStaff：

- 不应只存“这次点错了”；
- 应存“在此类 Finder 窗口里，先检查 sidebar 焦点，否则 coordinate fallback 容易失真”。

#### 3. [ExpeL](https://arxiv.org/abs/2308.10144)

最值得借鉴的点：

- 从多次经验中抽取可迁移 insight；
- 推理时像查案例库一样用它们。

翻译到 OpenStaff：

- 对跨 app 但同类任务，应尽量抽象出 transferable lesson，而不是只保留一次事件回放。

#### 4. [Aligning LLM Agents by Learning Latent Preference from User Edits](https://arxiv.org/abs/2404.15269)

最值得借鉴的点：

- 用户 edit 是最自然、最低额外成本的反馈源；
- 偏好最好写成可读描述，便于用户看和改。

翻译到 OpenStaff：

- 老师在 review 里改过的 summary、步骤顺序、确认话术，都应变成 preference evidence。

#### 5. [MPO](https://arxiv.org/abs/2503.02682)

最值得借鉴的点：

- 用 meta plan 优化，而不是每次只修一个局部动作。

翻译到 OpenStaff：

- 除了修 locator，也要能修“这类任务整体的步骤顺序”。

### 5.2 第二优先级：作为中期增强非常强

#### 6. [AgentFly](https://arxiv.org/abs/2508.16153)

它不是严格零训练，因为论文允许训练 case-selection policy，但它的方向非常值得关注：

- 不改底层 LLM；
- 用 memory-based online RL；
- 通过 memory reading / rewriting 持续适配。

对 OpenStaff 的意义：

- 当规则和简单检索不够时，可以只训练一个小型选择器，而不是训练整个模型。

#### 7. [DeAL](https://arxiv.org/abs/2402.06147), [PAD](https://arxiv.org/abs/2410.04070), [PITA](https://arxiv.org/abs/2507.20067)

这组工作的共同启发是：

- 偏好并不一定需要“写死”进模型；
- 也可以在生成当下按用户偏好进行引导。

对 OpenStaff 的意义：

- 很适合做：
  - review 摘要风格控制
  - 风险说明风格控制
  - assist 提示话术 personalization

### 5.3 第三优先级：作为长期上限参考

#### 8. [OpenClaw-RL](https://arxiv.org/abs/2603.10165)

它最有价值的部分不是“赶紧上线 RL”，而是：

- `next-state signal`
- `evaluative + directive`
- 异步学习闭环

#### 9. [UI-Mem](https://arxiv.org/abs/2602.05832)

它最有价值的部分是：

- workflow / subtask / failure pattern 的层级经验记忆；
- self-evolving memory loop。

这更像是你在把零训练 memory-first 路线跑通之后，再往 RL 过渡时的参考。

---

## 6. 工业与工程实践里，有哪些已经能直接借鉴

### 6.1 [LangMem](https://langchain-ai.github.io/langmem/concepts/conceptual_guide/)

它给 OpenStaff 的最大启发不是“某个 SDK 很方便”，而是下面这三个结构非常对：

1. **memory 类型分层**
   - semantic
   - episodic
   - procedural

2. **热路径与后台路径分离**
   - hot path：关键记忆立即写入；
   - background：后台反思、总结、归并，不阻塞实时交互。

3. **prompt 也可被持续优化**
   - procedural memory 本质上就是系统行为规则；
   - 可以根据 trajectory 和 feedback 重写。

这和 OpenStaff 的 Phase 11 几乎天然一致。

### 6.2 [Letta MemFS](https://docs.letta.com/letta-code/memory)

Letta 的启发主要有三条：

1. **记忆本身应可编辑、可分层、可版本化**
2. **agent 可以自编辑 memory，但需要结构化边界**
3. **sleep-time / reflection 适合放后台**

尤其是它把记忆做成 **git-backed context repository** 这一点，非常适合你的项目思路：

- preference rules
- repair lessons
- planner patches
- project-specific behavior

都可以做成可读文件，而不是藏在数据库黑箱里。

### 6.3 [Mem0 / OpenMemory](https://docs.mem0.ai/)

Mem0 代表的是另一种很产品化的工程路线：

- `add`
- `search`
- `update`
- `delete`
- `rerank`

这个模式本身已经很接近个人记忆系统的最小工作面。

对 OpenStaff 的启发是：

- learning layer 不一定先是“大而全的智能体框架”；
- 也可以先是一个**支持增删改查与重排的 memory service**。

---

## 7. 对 OpenStaff 的最推荐路线：先做“零训练持续学习层”

### 7.1 为什么它比训练路线更适合你现在

原因很现实：

1. **你当前最强的资产是结构化证据链，不是训练基础设施。**
2. **单用户桌面助理最需要的是可解释和可回滚。**
3. **老师的反馈量可能很多，但并不足以稳定支撑在线训练。**
4. **UI 漂移、skill 失效、风险门控，本质更像知识和策略问题，而不是纯参数问题。**

### 7.2 我建议的落地顺序

#### 阶段 A：严格零训练

只做：

- learning trace
- preference evidence
- episode / repair lesson 提炼
- prompt / planner / skill retrieval 重写
- rule promotion / quarantine

不做：

- LoRA
- RLHF
- reward model
- online RL

#### 阶段 B：冻结底模 + 小侧模

当 A 阶段跑顺后，再考虑：

- case reranker
- skill selector
- preference scorer
- small guidance policy

这一步仍然不碰主 LLM 权重。

#### 阶段 C：训练式闭环

只有在下面条件同时满足时再考虑：

- benchmark 稳定
- repair workflow 稳定
- feedback 足够多且高质量
- shadow eval 能证明外部 learning 已接近瓶颈

### 7.3 这一方案能覆盖多少价值

我的判断是：

- 如果目标是“让学生越来越像老师，且更稳、更懂偏好、更会避坑”，
- 那么 **零训练 + memory-first** 很可能能覆盖 **70% 到 85%** 的产品价值。

训练路线真正显著有优势的场景主要是：

1. 跨大量新任务的泛化；
2. 长链条、强探索型任务；
3. 需要把细粒度动作策略内化进模型时。

而这三点都不是你当前最迫切的短期目标。

---

## 8. 风险与边界：零训练方案也不是没有坑

### 8.1 记忆投毒与错误固化

近期两篇工作给了很强的警示：

- [A-MemGuard](https://arxiv.org/abs/2510.02373)
- [MemoryGraft](https://arxiv.org/abs/2512.16962)

结论很清楚：

- 一旦 agent 开始从 past experiences 学习，
- 错误经验和恶意经验都会变成长期污染源。

所以 OpenStaff 必须有：

1. memory quarantine
2. promotion thresholds
3. provenance
4. rollback
5. shadow evaluation

### 8.2 反思过多、收益过低

Reflexion / Self-Refine / OPRO 一类方法还有一个常见问题：

- 反思太多，调用太多，成本上升；
- 但真正提升有限，甚至会 overfit 到局部表达。

因此要避免：

- 每轮都深反思；
- 每条反馈都改 prompt；
- 每次小错都晋升为长期规则。

### 8.3 自动 prompt 优化的收益并不总是稳定

[OPRO](https://arxiv.org/abs/2309.03409) 说明自动 prompt 优化是可行的；
但 [Revisiting OPRO](https://arxiv.org/pdf/2405.10276) 也说明：

- 小模型自优化并不总有效；
- 成本可能高于收益。

这意味着对 OpenStaff 来说：

- prompt optimization 应放在后台；
- 先 shadow eval，再决定是否晋升；
- 不要把它当默认热路径能力。

---

## 9. 最终判断

如果把这次调研压缩成一句明确建议：

> **OpenStaff 完全可以先构建一个“不训练底模”的反馈式轻量持续学习层，而且这条路线在学术和工程上都已经站得住。**

更具体地说：

1. **严格零训练方案是成立的。**
   - Reflexion、CLIN、ExpeL、Voyager、PRELUDE/CIPHER、LangMem、Letta 都在说明：
   - 通过 memory、反思、规则、技能库、prompt patch，就可以形成真正的持续学习。

2. **对你的项目，这条路线比传统训练更合理。**
   - 因为你现在最需要的是：
   - 可解释
   - 可审计
   - 可修复
   - 可回滚
   - 可本地化

3. **未来不是不能训练，但顺序应该是：**
   - `memory rewrite`
   - `policy rewrite`
   - `small side-model learning`
   - `base-model learning`

如果要给下一阶段起一个最贴切的名字，我会叫它：

> **Memory-First Feedback Learning Layer**

这比“在线 RL 层”更准确，也更适合 OpenStaff 当前阶段。

---

## 10. 参考资料

### 10.1 零训练 / 非传统训练主线

- [Reflexion: Language Agents with Verbal Reinforcement Learning](https://arxiv.org/abs/2303.11366)
- [Self-Refine: Iterative Refinement with Self-Feedback](https://arxiv.org/abs/2303.17651)
- [Voyager: An Open-Ended Embodied Agent with Large Language Models](https://arxiv.org/abs/2305.16291)
- [ExpeL: LLM Agents Are Experiential Learners](https://arxiv.org/abs/2308.10144)
- [CLIN: A Continually Learning Language Agent for Rapid Task Adaptation and Generalization](https://arxiv.org/abs/2310.10134)
- [Aligning LLM Agents by Learning Latent Preference from User Edits](https://arxiv.org/abs/2404.15269)
- [MPO: Boosting LLM Agents with Meta Plan Optimization](https://arxiv.org/abs/2503.02682)
- [DeAL: Decoding-time Alignment for Large Language Models](https://arxiv.org/abs/2402.06147)
- [PAD: Personalized Alignment of LLMs at Decoding-Time](https://arxiv.org/abs/2410.04070)
- [PITA: Preference-Guided Inference-Time Alignment for LLM Post-Training](https://arxiv.org/abs/2507.20067)

### 10.2 记忆与 personalization

- [A-MEM: Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110)
- [E-mem: Multi-agent based Episodic Context Reconstruction for LLM Agent Memory](https://arxiv.org/abs/2601.21714)
- [MAGNET: Towards Adaptive GUI Agents with Memory-Driven Knowledge Evolution](https://arxiv.org/abs/2601.19199)
- [LaMP: When Large Language Models Meet Personalization](https://arxiv.org/abs/2304.11406)
- [LaMP-QA: A Benchmark for Personalized Long-form Question Answering](https://arxiv.org/abs/2506.00137)
- [CUPID: Evaluating Personalized and Contextualized Alignment of LLMs from Interactions](https://arxiv.org/abs/2508.01674)
- [PersonaLens: A Benchmark for Personalization Evaluation in Conversational AI Assistants](https://arxiv.org/abs/2506.09902)

### 10.3 理论、安全与训练型上限

- [Provably Learning from Language Feedback](https://arxiv.org/abs/2506.10341)
- [OpenClaw-RL: Train Any Agent Simply by Talking](https://arxiv.org/abs/2603.10165)
- [UI-Mem: Self-Evolving Experience Memory for Online Reinforcement Learning in Mobile GUI Agents](https://arxiv.org/abs/2602.05832)
- [RiCL: Reinforced Interactive Continual Learning via Real-time Noisy Human Feedback](https://arxiv.org/abs/2505.09925)
- [A-MemGuard: A Proactive Defense Framework for LLM-Based Agent Memory](https://arxiv.org/abs/2510.02373)
- [MemoryGraft: Persistent Compromise of LLM Agents via Poisoned Experience Retrieval](https://arxiv.org/abs/2512.16962)
- [On the Algorithmic Bias of Aligning Large Language Models with RLHF: Preference Collapse and Matching Regularization](https://arxiv.org/pdf/2405.16455)

### 10.4 工程框架与产品资料

- [LangMem Documentation](https://langchain-ai.github.io/langmem/)
- [LangMem Core Concepts](https://langchain-ai.github.io/langmem/concepts/conceptual_guide/)
- [Letta Memory / MemFS](https://docs.letta.com/letta-code/memory)
- [Mem0 Docs](https://docs.mem0.ai/)
- [Mem0 OpenMemory Quickstart](https://docs.mem0.ai/openmemory/quickstart)
