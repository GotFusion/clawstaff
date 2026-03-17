# OpenStaff 相关前沿调研：个人知识模型、非训练个性化、GUI 学习与 RL、移动端

版本：v0.1  
更新时间：2026-03-17  
适用对象：OpenStaff / ClawStaff 项目规划

---

## 1. 结论先行

结合截至 **2026-03-17** 可见的学术论文、开源系统和工业产品，我对 OpenStaff 的核心判断是：

1. **不要把“为每个用户训练一个新模型”作为当前主线。**
   - 当前最稳妥、最符合行业趋势的路线是：`现成强模型 + 本地/私有知识层 + 结构化记忆 + 可审计偏好规则 + 少量异步再学习`。

2. **OpenStaff 的真正护城河不应是“端到端截图模型”，而应是“个人桌面知识与偏好控制面”。**
   - 也就是你现在已经在做的：示教、知识落盘、技能生成、执行审阅、漂移修复、安全门控。

3. **“学到的知识”不能只是一串点击坐标。**
   - 前沿系统都在往“观察包 + 过程记忆 + 偏好记忆 + 可回放证据”演进。
   - 你的 `ObservationRecord / ProcedureSpec / SkillArtifact / ExecutionReview` 分层方向是对的，下一步应继续升级成更明确的 `ObservationBundle + InteractionTurn + PreferenceMemory + RepairMemory`。

4. **强化学习对项目有价值，但更像“反馈回写机制”，而不是“现在就做在线训练平台”。**
   - 像 [OpenClaw-RL](https://arxiv.org/abs/2603.10165)、[UI-Mem](https://arxiv.org/abs/2602.05832)、[AgentFly](https://arxiv.org/abs/2508.16153) 这类工作最值得借鉴的是：
     - 如何把真实使用中的反馈变成学习信号；
     - 如何让 memory 改写策略，而不是立刻改写模型权重；
     - 如何异步学习而不阻塞在线执行。

5. **移动端应视为“第二战场”，先用 benchmark 和受控原型推进，不宜现在就把主工程重心切过去。**
   - 学术界移动代理进展很快，但稳定性、鲁棒性、跨应用长任务和异常弹窗处理依然远未成熟。

6. **隐私、删除、可见状态、投毒防护不是补充项，而是产品主干。**
   - Recall、Screenpipe、Limitless 这类系统已经证明：只要是“持续观察用户”的产品，信任成本永远高于炫技成本。

如果把这些判断压缩成一句话：

> OpenStaff 当前最应该做的是“把老师操作、老师反馈、执行结果、修复过程”沉淀成可检索、可回写、可审计的个人行为知识系统；而不是急着把项目升级成训练基础设施。

---

## 2. 这轮调研与 OpenStaff 当前路线的对应关系

项目当前文档已经明确了几条重要方向：

- `Capture -> Knowledge -> Skill -> Execute -> Review`
- 教学 / 辅助 / 学生三模式
- 语义定位、skill provenance、review、repair、benchmark、安全门
- Phase 11 计划把 review/repair 进一步回写为 `evaluative` / `directive` 信号

这些方向与 2025-2026 的前沿非常一致。差别主要不在“方向错了”，而在“还需要把外部趋势吸收得更体系化”：

1. **从点击事件升级为观察单元**
   - 当前行业趋势不是简单录坐标，而是保留截图、AX、OCR、窗口签名、目标候选、前后状态变化等证据。

2. **从历史知识升级为多层记忆**
   - 个人系统不再只做“文档 RAG”，而是开始区分：
     - 事实记忆
     - 情景记忆
     - 过程记忆
     - 偏好记忆
     - 身份/画像记忆

3. **从人工修复升级为反馈学习**
   - 当前前沿系统的共识是：用户确认、拒绝、编辑、接管、修复建议，都是天然学习信号。

4. **从单设备自动化升级为跨设备编排**
   - 但这一层目前还偏早，应该在桌面主链路稳定后再做。

---

## 3. 学术前沿：个人知识模型与长期记忆

### 3.1 从“聊天记忆”走向“结构化个人知识模型”

近两年的代表工作说明：如果系统要长期服务同一个人，单纯保留聊天历史远远不够，必须显式建模用户的长期偏好、上下文和可演化知识。

| 方向 | 代表工作 | 核心启示 | 对 OpenStaff 的意义 |
|---|---|---|---|
| 动态组织记忆 | [A-MEM: Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110) | 不把 memory 只当向量库，而是让系统主动组织、链接、更新记忆 | 适合把老师日常操作沉淀成可互联的知识网络，而不是互相孤立的 task 日志 |
| 情景记忆重建 | [E-mem](https://arxiv.org/abs/2601.21714) | 长期推理时，压缩后的 embeddings/graphs 会损失关键上下文，需要支持 episodic reconstruction | 说明 OpenStaff 原始观察证据不能过早丢弃，应保留可回放的 observation refs |
| 身份/画像显式建模 | [ID-RAG](https://arxiv.org/abs/2509.25299) | 用 identity graph 维持长期 persona coherence，降低 identity drift | 说明“老师偏好”需要独立成层，而不是混在所有历史步骤里 |
| 社区/图结构 personalization | [PersonaAgent with GraphRAG](https://arxiv.org/abs/2511.17467) | KG/GraphRAG 可以更好整合用户历史行为与相关模式 | 适合未来把任务、App、偏好、修复策略连成个人操作知识图 |

### 3.2 评测侧已经在逼迫系统显式管理长期记忆

| 评测/基准 | 代表工作 | 结论 | 对 OpenStaff 的意义 |
|---|---|---|---|
| 长期记忆能力 | [LongMemEval](https://arxiv.org/abs/2410.10813) | 商业助手和长上下文模型在持续交互记忆上仍有明显掉点 | 不能假设“把历史全塞给大模型”就能理解老师习惯 |
| personalization 基准 | [LaMP](https://arxiv.org/abs/2304.11406), [LaMP-QA](https://arxiv.org/abs/2506.00137) | 个性化上下文会显著提升表现，但前提是检索粒度和相关性足够好 | 你的个人知识库需要细粒度索引，而不是整 task 整块召回 |
| 动态偏好推断 | [CUPID](https://arxiv.org/abs/2508.01674), [PersonaLens](https://arxiv.org/abs/2506.09902) | 当前强模型仍然不擅长从多轮历史里稳定抽出“此刻真正相关的偏好” | 应把“偏好规则”结构化，而不是指望模型自己从日志里悟出来 |

### 3.3 对项目的直接结论

OpenStaff 应该尽快把个人知识层拆成至少四层：

1. **Observation Memory**
   - 当时看到了什么：截图、窗口、AX、OCR、URL、相对位置、语义候选。

2. **Procedure Memory**
   - 任务是怎么完成的：抽象步骤、前置条件、失败条件、替代路径。

3. **Preference Memory**
   - 老师偏好的做法是什么：确认阈值、常用 App、输出风格、顺序偏好、命名习惯、风险偏好。

4. **Identity / Profile Memory**
   - 稳定画像：角色、设备环境、常用软件、权限状态、安全限制、长期工作场景。

这四层里，**Preference Memory 最值得优先补**，因为它最直接决定辅助模式和学生模式是否像“这个老师的学生”。

---

## 4. 非训练个性化：借用现成 GPT + 个人知识库，而不是急着调权重

### 4.1 学术信号：训练外 personalization 已经成为主流可落地方向

| 方向 | 代表工作 | 核心方法 | 对 OpenStaff 的启发 |
|---|---|---|---|
| 基于用户编辑学习偏好 | [Aligning LLM Agents by Learning Latent Preference from User Edits](https://arxiv.org/abs/2404.15269) | 从用户 edit 中抽 latent preference，再在后续生成时检索使用 | 你的“老师修正文案/步骤/执行方式”是最宝贵的偏好数据 |
| 安全个性化且不训练 | [Personalized Safety / RAISE / PENGUIN](https://arxiv.org/abs/2505.18882) | 按任务需要选择性获取用户背景，不做整模型重训 | 说明个人代理不必事先知道用户全部信息，而应按需收集和应用 |
| 不调 LLM、只调 agent memory | [AgentFly](https://arxiv.org/abs/2508.16153) | 用 memory-based online RL 和 case selection policy 持续适配，不改底层 LLM 权重 | 这与 OpenStaff 的路线高度契合，适合作为中长期学习层参考 |
| 检索优化驱动 personalization | [Optimization Methods for Personalizing LLMs through Retrieval Augmentation](https://arxiv.org/abs/2404.05970) | 优化的是“给模型喂什么记忆”，而不是先训练模型 | 重点应放在 preference/experience retrieval 排序，而非先做 LoRA |

### 4.2 工业/开源信号：记忆层正在成为 GPT 之外的独立基础设施

| 系统 | 当前可见方向 | 对 OpenStaff 的价值 |
|---|---|---|
| [Letta](https://docs.letta.com/guides/core-concepts/memory/memory-blocks) | 把 memory 当成 agent 的一等对象，可读写、可共享、可按块管理；新版本还支持基于 markdown 文件的 MemFS | 说明未来 OpenStaff 的 preference/identity memory 完全可以文件化、可审计化 |
| [Mem0 / OpenMemory](https://docs.mem0.ai/) | 自称 memory layer，强调 self-improving memory、multimodal support、MCP 接入 | 说明“个人记忆层”已经开始脱离单一 agent，成为独立服务层 |
| [Screenpipe](https://docs.screenpi.pe/) | 本地优先，抓屏+OCR+可访问性树+SQLite+REST API+MCP+pipes 定时代理 | 与 OpenStaff 最接近的不是“替代”，而是“观察层与检索层做得很清楚” |
| [Limitless](https://www.limitless.ai/new) | 把个人对话记忆暴露为 API / MCP，可接 ChatGPT、Claude 等现成助手 | 这是很强的市场信号：行业正在把“已有强模型 + 个人记忆层”作为默认组合 |

### 4.3 对项目的直接结论

**OpenStaff 现阶段最佳路线不是“训练一个 OpenStaff 模型”，而是：**

`强模型（GPT/Claude/OpenAI-compatible）`
`+`
`本地 Observation / Preference / Procedure Memory`
`+`
`高质量检索与重排`
`+`
`结构化规则回写`
`+`
`少量异步 memory rewrite / replay learning`

这条路线的优点：

- 算力成本低；
- 可解释性高；
- 失败可修；
- 对单用户项目最友好；
- 容易和 OpenClaw skill 系统对接；
- 避免“为一个人训练模型却难以验证收益”的工程陷阱。

---

## 5. 从示教到执行：桌面 GUI Agent 与过程学习前沿

### 5.1 开源和论文最值得看的几条线

| 方向 | 代表工作 | 值得借鉴的部分 | 不建议照搬的部分 |
|---|---|---|---|
| 录制到回放 | [OpenAdapt](https://github.com/OpenAdaptAI/OpenAdapt) | 录制 screenshots + user input，支持 process visualization、synthetic replay、用户接管 | 当前实现更偏 Python 研究原型，不适合直接替代你的主工程 |
| 训练数据管线 | [OpenAdapter](https://github.com/OpenAdaptAI/OpenAdapter) | 明确提出“从用户截图和动作构建数据集并 fine-tune/action models” | 适合作为未来离线数据工坊参考，不适合作为当前主线 |
| Windows GUI agent | [UFO](https://arxiv.org/abs/2402.07939), [UFO2](https://arxiv.org/abs/2504.14603) | `GUI + API` 混合动作层、App 专家代理、深 OS 集成、隔离执行桌面（PiP） | Windows 偏强；但其“native action first”思想非常值得借鉴 |
| 多设备编排 | [UFO3](https://arxiv.org/abs/2511.11332), [microsoft/UFO](https://github.com/microsoft/UFO) | 把单设备 agent 升级为跨设备 orchestration fabric | 对 OpenStaff 来说偏后期，至少应在桌面单机稳后再做 |
| 真实桌面 benchmark | [OSWorld](https://arxiv.org/abs/2404.07972), [OSUniverse](https://arxiv.org/abs/2505.03570) | 用真实 OS / app / workflow 评估 agent，而不是纯静态数据集 | 可直接借鉴 benchmark 思路，而不是照搬 Ubuntu/Windows 场景 |
| 高性能 UI 训练 | [UI-Venus](https://arxiv.org/abs/2508.10833) | 强调 grounding reward、navigation reward、自演化轨迹修正 | 说明“视觉 grounding 很重要”，但你当前仍应以可修复 skill 为主 |

### 5.2 这一层对 OpenStaff 的关键影响

这批工作共同说明了三件事：

1. **单纯 screenshot-only agent 还不够稳。**
   - 真正能用的系统都在往 `GUI + API + OS metadata + memory + reflection` 组合走。

2. **native action 和 GUI action 必须分开建模。**
   - UFO2 的一个核心启示就是：能走应用原生 API / automation bridge 的，就不要退化成截图点击。

3. **用户接管能力比“多自动一点”更重要。**
   - OpenAdapt、移动端人机协作论文都在强调：不确定时把控制权平滑还给用户，并把纠正重新写回系统，是长期可用性的关键。

### 5.3 对项目的直接结论

OpenStaff 应继续强化下面这条动作分层：

1. `nativeAction`
   - Shortcuts / AppleScript / CLI / app-specific API / OpenClaw 工具调用

2. `guiSemanticAction`
   - AX / text anchor / image anchor / relative coordinate / absolute fallback

3. `unsafeRawReplay`
   - 只作兜底，不应成为主路径

也就是说，**你的项目不是在做“更聪明的鼠标录制器”，而是在做“个人桌面动作编译器”**。

---

## 6. 强化学习与反馈学习：应该吸收什么，不应该过早做什么

### 6.1 真正与你项目最相关的 RL / 学习闭环工作

| 工作 | 核心点 | 对 OpenStaff 的价值 |
|---|---|---|
| [OpenClaw-RL](https://arxiv.org/abs/2603.10165) | 把 next-state signal 拆为 `evaluative` 和 `directive`；异步服务、评审、训练并行 | 这是你现阶段最值得吸收的学习接口抽象 |
| [UI-Mem](https://arxiv.org/abs/2602.05832) | 在线 GUI RL 加入分层经验记忆，把 workflow、subtask skill、failure pattern 抽成模板 | 说明记忆可以先于权重训练发挥价值 |
| [AgentFly](https://arxiv.org/abs/2508.16153) | memory-based online RL，无需 fine-tune LLM | 很适合 OpenStaff 未来做“轻量持续学习后端” |
| [MAGNET](https://arxiv.org/abs/2601.19199) | 用稳定功能语义和程序意图抵抗 UI 漂移 | 与你现有的 semantic target / drift repair 思想高度一致 |

### 6.2 需要特别警惕的点

| 风险 | 代表工作 | 说明 |
|---|---|---|
| 偏好塌缩 | [Preference Collapse / PM-RLHF](https://arxiv.org/pdf/2405.16455) | 如果粗暴地把复杂偏好压成单一 reward，少数偏好会被抹平 |
| 记忆投毒 | [A-MemGuard](https://arxiv.org/abs/2510.02373), [MemoryGraft](https://arxiv.org/abs/2512.16962) | 一旦系统开始复用“过去成功经验”，恶意或错误经验会长期污染后续行为 |

### 6.3 对项目的直接结论

OpenStaff 在未来 1-2 个版本里，应该做的是 **“非训练强化”**，而不是“在线参数训练”：

1. 落地 `evaluative` / `directive` 双通路。
2. 把老师的 `通过 / 驳回 / 修 locator / 重新示教 / 编辑结果` 统一转成 learning trace。
3. 优先更新：
   - 检索排序
   - preference rules
   - prompt assembly
   - skill repair policy
   - planner heuristics
4. 暂不默认做：
   - 用户级 LoRA 训练
   - 在线 RLHF/RLAIF
   - 无门控的自动策略探索

我的判断是：

> 对 OpenStaff 而言，未来两步中“先做 memory rewrite，再考虑 model rewrite”几乎一定是正确顺序。

---

## 7. 移动端前沿：适合中期布局，不适合立刻抢主线

### 7.1 学术界的主要信号

| 方向 | 代表工作 | 关键信号 |
|---|---|---|
| Android benchmark | [AndroidWorld](https://arxiv.org/abs/2405.14573) | 移动端真实任务 benchmark 已成主流，但跨平台迁移并不容易 |
| 移动多代理 | [Mobile-Agent-v2](https://arxiv.org/abs/2406.01014) | 规划、决策、反思分离，对长任务导航帮助明显 |
| 人机协作移动代理 | [ReInAgent](https://arxiv.org/abs/2510.07988) | 面对信息不完整或冲突场景，human-in-the-loop 显著更稳 |
| 新一代移动基准 | [MobileWorld](https://arxiv.org/abs/2512.19432) | 新 benchmark 已加入用户交互与 MCP 调用，说明“纯 GUI 点击”不再够用 |
| 记忆能力评测 | [MemGUI-Bench](https://arxiv.org/abs/2602.06075) | 当前移动 GUI agent 的记忆能力仍很弱，跨 session 更差 |

### 7.2 对 OpenStaff 的建议

移动端不是不能做，而是要换个姿势做：

1. **先做研究支线，不做主线产品承诺。**
   - 可先建立 `AndroidWorld/MobileWorld` 风格的小型内部 benchmark。

2. **优先做“知识与偏好层复用”，而不是“移动控制层全量复刻”。**
   - 很多老师偏好、任务意图、审阅规则可跨设备共用；
   - 真正设备相关的是 action adapter 和 observation adapter。

3. **移动端更需要 human-in-the-loop。**
   - 手机上的权限弹窗、支付链路、隐私入口、通知打断比桌面更频繁。

4. **优先考虑 native intent / app action，而非截图点击。**
   - 这与桌面端的 `nativeAction first` 是同一原则。

---

## 8. 工业产品与开源生态：真正值得借鉴的产品信号

### 8.1 观察与记忆类产品

| 产品 | 当前可见特征 | 对 OpenStaff 的启发 |
|---|---|---|
| [Microsoft Recall / Click to Do](https://support.microsoft.com/en-us/windows/privacy-and-control-over-your-recall-experience-d404f672-7647-41e5-886c-a3c59680af15) | 本地保存与分析、可暂停、过滤 app/网站、删除与隐私控制；[Click to Do](https://support.microsoft.com/en-us/windows/click-to-do-in-recall-do-more-with-what-s-on-your-screen-967304a8-32d1-4812-a904-fad59b5e6abf) 在 snapshot 上做局部动作 | “可见状态 + 本地优先 + 可暂停/过滤/删除”必须是观察类产品的默认配置 |
| [Screenpipe](https://docs.screenpi.pe/architecture) | 事件驱动抓屏、AX 提取、OCR 回退、本地 SQLite、REST API、MCP、定时 pipes | 说明 observation layer 和 query layer 应该天然可被 agent 查询 |
| [Limitless](https://www.limitless.ai/new) | 个人记忆可通过 REST/MCP 供 ChatGPT/Claude 使用；移动与桌面协同；可导出/删除 | 强化了“记忆层独立于模型层”的产品形态 |
| [Rewind（现 Limitless 历史产品）](https://help.limitless.ai/en/articles/13048802-where-can-i-find-my-rewind-data) | 本地数据可定位，但官方明确“没有受支持 API” | 提醒我们不要把个人历史困在闭源产品黑盒里 |

### 8.2 自动化与 agent 系统

| 系统 | 当前可见特征 | 对 OpenStaff 的启发 |
|---|---|---|
| [OpenAdapt](https://github.com/OpenAdaptAI/OpenAdapt) | 从示范到回放、允许用户接管、强调录制与回放桥梁 | teaching 模式不该只是录制，还要考虑失败后的 takeover 与修复 |
| [microsoft/UFO](https://github.com/microsoft/UFO) | GUI + API 混合、Windows 深集成、已发展到多设备编排 | 说明 agent 系统会走向强边界、强编排、强插件化 |
| [Letta](https://docs.letta.com/letta-code/memory/) / [Mem0](https://docs.mem0.ai/) | 把记忆做成 agent 基础设施 | OpenStaff 可把个人知识层做成未来可被 OpenClaw 或 MCP 消费的稳定接口 |

### 8.3 工业侧汇总结论

产业界已经给出一个非常清晰的组合范式：

`本地或私有 capture`
`+`
`结构化记忆`
`+`
`MCP / API 接口`
`+`
`现成强模型`
`+`
`少量可控自动化`

这与 OpenStaff 的中期产品路线非常吻合。

---

## 9. 面向 OpenStaff 的路线建议

### 9.1 未来 3 个月：先把“个人行为知识层”立稳

优先级建议：

1. **把 ObservationBundle 正式化**
   - 每个可学习动作都带：
     - 前后 screenshot refs
     - app / window signature
     - AX refs
     - OCR / text anchor 摘要
     - URL / title（可得时）
     - relative point
     - semantic target candidates

2. **把 Preference Memory 单独建模**
   - 建议新增：
     - `PreferenceRule`
     - `PreferenceEvidence`
     - `PreferencePromotion`
     - `PreferenceConflict`

3. **把老师反馈统一成 learning trace**
   - 至少沉淀：
     - accept / reject
     - edit
     - repair locator
     - reteach
     - takeover
     - risk override

4. **把结果回写限定在“可解释层”**
   - 回写到：
     - prompt assembly
     - assist ranking
     - skill repair
     - planner heuristics
     - review policy

### 9.2 未来 3-6 个月：做“非训练强化”

建议落地：

1. `evaluative signal`
   - `pass / fail / neutral`

2. `directive signal`
   - 1-3 句、可执行、只描述怎么改

3. `experience templates`
   - 成功模板
   - 常见失败模板
   - 漂移修复模板
   - 高风险确认模板

4. `memory rewrite`
   - 老师反复确认后的规则自动晋升；
   - 单次异常不直接晋升；
   - 默认走投票或阈值机制。

### 9.3 未来 6-12 个月：再考虑更强学习层

到那时再评估是否值得尝试：

- 离线行为克隆或 reward modeling
- 仅训练 retrieval / reranker
- 仅训练 memory encoder
- 用户级轻量 LoRA
- 和 OpenClaw-RL 类似的异步学习后端

但前提必须是：

- benchmark 已稳定；
- drift repair 已成熟；
- safety gate 已统一；
- preference memory 已可解释；
- 日志和导出机制完善。

---

## 10. 不建议当前阶段做的事

1. **不建议把主线切成“全天候无感录屏 + 全自动学习”。**
   - 信任成本、合规成本、存储成本都太高。

2. **不建议直接做用户级模型微调主线。**
   - 难验证收益，难解释，难回滚。

3. **不建议依赖单一供应商云记忆。**
   - 工业产品路线变化快，闭源 memory 产品的 API 生命周期不稳定。

4. **不建议只保留压缩后的知识摘要。**
   - 后续 replay、repair、审计、再学习都需要原始证据链。

5. **不建议把移动端扩张放在桌面主链路之前。**
   - 当前桌面产品定位更清晰，也更能形成差异化资产。

---

## 11. 我对项目方向的最终建议

如果要给 OpenStaff 下一阶段定一句产品定位，我建议是：

> **OpenStaff 不是一个通用桌面代理，而是一个面向个人用户的“示教学习层 + 行为知识库 + 偏好回写层 + 审阅修复台”。**

进一步说，真正值得坚持的主线是：

1. **本地优先的观察层**
2. **可审计的个人知识层**
3. **可检索的偏好记忆层**
4. **可修复的 skill 生成与执行层**
5. **可回写的反馈学习层**

而不是：

1. 先做一个“什么都能自己操作”的 screenshot agent；
2. 再想办法解释它为什么错；
3. 最后再补安全和记忆。

从这轮调研看，**你的项目现在最有前景的方向不是“追通用 agent demo”，而是“做个人桌面行为知识的基础设施”**。这条路更稳，也更容易沉淀长期资产。

---

## 12. 参考资料（按主题分组）

### 12.1 个人知识模型 / 记忆

- [A-MEM: Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110)
- [E-mem: Multi-agent based Episodic Context Reconstruction for LLM Agent Memory](https://arxiv.org/abs/2601.21714)
- [ID-RAG: Identity Retrieval-Augmented Generation for Long-Horizon Persona Coherence in Generative Agents](https://arxiv.org/abs/2509.25299)
- [LongMemEval: Benchmarking Chat Assistants on Long-Term Interactive Memory](https://arxiv.org/abs/2410.10813)
- [LaMP: When Large Language Models Meet Personalization](https://arxiv.org/abs/2304.11406)
- [LaMP-QA: A Benchmark for Personalized Long-form Question Answering](https://arxiv.org/abs/2506.00137)
- [CUPID: Evaluating Personalized and Contextualized Alignment of LLMs from Interactions](https://arxiv.org/abs/2508.01674)
- [PersonaLens: A Benchmark for Personalization Evaluation in Conversational AI Assistants](https://arxiv.org/abs/2506.09902)

### 12.2 非训练 personalization / 记忆层

- [Aligning LLM Agents by Learning Latent Preference from User Edits](https://arxiv.org/abs/2404.15269)
- [Personalized Safety in LLMs: A Benchmark and A Planning-Based Agent Approach](https://arxiv.org/abs/2505.18882)
- [Optimization Methods for Personalizing Large Language Models through Retrieval Augmentation](https://arxiv.org/abs/2404.05970)
- [AgentFly: Fine-tuning LLM Agents without Fine-tuning LLMs](https://arxiv.org/abs/2508.16153)
- [Letta Memory Blocks](https://docs.letta.com/guides/core-concepts/memory/memory-blocks)
- [Letta MemFS / Memory](https://docs.letta.com/letta-code/memory/)
- [Mem0 Docs](https://docs.mem0.ai/)
- [Mem0 OpenMemory](https://mem0.ai/openmemory)

### 12.3 桌面 / GUI agent / 示教学习

- [OpenAdapt GitHub](https://github.com/OpenAdaptAI/OpenAdapt)
- [OpenAdapter GitHub](https://github.com/OpenAdaptAI/OpenAdapter)
- [UFO: A UI-Focused Agent for Windows OS Interaction](https://arxiv.org/abs/2402.07939)
- [UFO2: The Desktop AgentOS](https://arxiv.org/abs/2504.14603)
- [UFO3: Weaving the Digital Agent Galaxy](https://arxiv.org/abs/2511.11332)
- [microsoft/UFO GitHub](https://github.com/microsoft/UFO)
- [OSWorld](https://arxiv.org/abs/2404.07972)
- [OSUniverse](https://arxiv.org/abs/2505.03570)
- [UI-Venus Technical Report](https://arxiv.org/abs/2508.10833)

### 12.4 RL / 学习闭环 / 安全

- [OpenClaw-RL: Train Any Agent Simply by Talking](https://arxiv.org/abs/2603.10165)
- [UI-Mem: Self-Evolving Experience Memory for Online Reinforcement Learning in Mobile GUI Agents](https://arxiv.org/abs/2602.05832)
- [MAGNET: Towards Adaptive GUI Agents with Memory-Driven Knowledge Evolution](https://arxiv.org/abs/2601.19199)
- [A-MemGuard: A Proactive Defense Framework for LLM-Based Agent Memory](https://arxiv.org/abs/2510.02373)
- [MemoryGraft: Persistent Compromise of LLM Agents via Poisoned Experience Retrieval](https://arxiv.org/abs/2512.16962)
- [On the Algorithmic Bias of Aligning Large Language Models with RLHF](https://arxiv.org/pdf/2405.16455)

### 12.5 移动端

- [AndroidWorld](https://arxiv.org/abs/2405.14573)
- [google-research/android_world GitHub](https://github.com/google-research/android_world)
- [Mobile-Agent-v2](https://arxiv.org/abs/2406.01014)
- [ReInAgent](https://arxiv.org/abs/2510.07988)
- [MobileWorld](https://arxiv.org/abs/2512.19432)
- [MemGUI-Bench](https://arxiv.org/abs/2602.06075)

### 12.6 工业产品

- [Microsoft Recall 隐私与控制](https://support.microsoft.com/en-us/windows/privacy-and-control-over-your-recall-experience-d404f672-7647-41e5-886c-a3c59680af15)
- [Microsoft Click to Do](https://support.microsoft.com/en-us/windows/click-to-do-in-recall-do-more-with-what-s-on-your-screen-967304a8-32d1-4812-a904-fad59b5e6abf)
- [Screenpipe Docs](https://docs.screenpi.pe/)
- [Screenpipe Architecture](https://docs.screenpi.pe/architecture)
- [Limitless](https://www.limitless.ai/new)
- [Limitless Help Center](https://help.limitless.ai/)
- [Rewind 数据位置说明](https://help.limitless.ai/en/articles/13048802-where-can-i-find-my-rewind-data)
