# OpenStaff 市场调研：OpenClaw 动向、类似软件进展与零训练个性化研究

版本：v0.1  
更新时间：2026-03-26  
适用对象：OpenStaff / ClawStaff 下一阶段产品与技术规划

---

## 1. 结论先行

结合截至 **2026-03-26** 可见的 OpenClaw 官方动向、类似软件进展和 2025-2026 的相关研究，我对 OpenStaff 的核心判断是：

1. **OpenClaw 正在更明确地成为“执行平台与控制面”，而不是老师示教学习层。**
   - 它最近的产品重心明显落在 `gateway / nodes / plugins / skills / operations / platforms` 上。
   - 这意味着 OpenStaff 继续承担 `teaching layer + personal memory layer + review cockpit` 是正确方向。

2. **“观察老师电脑”的产品，市场基线已经不是“能录到”，而是“可见、可停、可排除、可删除、可导出”。**
   - Recall、Screenpipe、Limitless 这一类产品都在证明：隐私、状态可见性和资产可迁移性，比“更智能”更决定用户是否信任系统。

3. **零训练或近零训练个性化，是当前最值得投入的工程主线。**
   - 最新研究的高价值共识不是“赶紧训练一个新模型”，而是：
     - 原始事实保留
     - provenance
     - 推理时检索
     - 结构化偏好回写
     - 可撤销与可审计的策略装配

4. **个人桌面 Agent 的真正差异化，正在从“截图点点点”转向“个人知识资产和偏好控制面”。**
   - 也就是：
     - 观察包
     - 过程记忆
     - 偏好记忆
     - skill provenance
     - replay / repair
     - review / audit

5. **学术界已经把 Personalized GUI Agent 视为正式问题，但当前通行答案仍然偏 memory-first，而不是 training-first。**
   - 这与 OpenStaff 当前做 `capture -> knowledge -> skill -> review -> preference` 的主线高度一致。

6. **OpenStaff 下一版最应该做的不是扩更多模式能力，而是把“个人观察资产 -> skill 工坊 -> 零训练个性化 -> 外部查询边界”做扎实。**

如果压缩成一句话：

> OpenStaff 应该把“老师真实操作 + 老师反馈 + 执行结果 + 修复过程”做成可检索、可回放、可恢复、可回写的个人桌面知识系统；而不是急着把项目升级成训练基础设施。

---

## 2. OpenClaw 最新动向

### 2.1 直接可见的官方事实

截至 **2026-03-26**，我查到的 OpenClaw 公开动向主要来自官方 GitHub Releases、Docs Hubs 和安全文档：

- 最新稳定版为 **`2026.3.24`**，发布时间是 **2026-03-25**。同日还有两个 beta 版。  
  来源：[OpenClaw Releases](https://github.com/openclaw/openclaw/releases)
- 官方文档入口已经明确按 `gateway`、`operations`、`nodes`、`skills`、`plugins`、`platforms` 做产品边界拆分。  
  来源：[OpenClaw Docs Hubs](https://docs.openclaw.ai/start/hubs)
- 官方安全文档明确把 OpenClaw 定义为 **trusted-operator model**，并强调它不是多租户隔离沙箱。  
  来源：[Gateway Security](https://docs.openclaw.ai/gateway/security)、[Security](https://github.com/openclaw/openclaw/security)

### 2.2 可以归纳出的产品方向

从最近 release 和官方文档结构，可以归纳出 5 个趋势：

1. **Gateway 正在成为统一控制面**
   - OpenClaw 不再只是一个聊天式 agent，而是在形成可编排的 runtime / gateway / operations 体系。

2. **Plugin 与 skill 生态边界在加强**
   - 最近 release 持续在做 plugin SDK、ClawHub/skills、platform integration 和容器支持。

3. **节点与设备能力正在正规化**
   - `nodes` 成为一等模块，macOS 更像可配对执行节点，而不是学习系统的全部宿主。

4. **平台广度高于“学习老师”深度**
   - 公开方向明显更偏连接器、运行面、平台整合，而不是 per-user desktop learning。

5. **安全压力在上升**
   - 官方已经非常明确地收口 trusted-operator 边界，说明执行层的风险治理正在前置化。

### 2.3 对 OpenStaff 的直接结论

OpenStaff 不应该试图把 OpenClaw 改造成“既学老师又执行任务”的单体系统，而应继续保持：

- OpenClaw：执行内核、gateway、skills、nodes、tool runtime
- OpenStaff：示教学习层、个人知识层、review/repair/workflow 控制面

这也是为什么 OpenStaff 的产品定位更适合继续收敛为：

- `teaching layer`
- `personal desktop memory layer`
- `skill foundry`
- `review and repair cockpit`

---

## 3. 类似软件的进展

### 3.1 Microsoft Recall / Click to Do

微软官方文档已经把 Recall 描述为 **GA release on Copilot+ PCs (2025-04-25)**，并把能力重点放在：

- 本地快照与本地语义处理
- 显式启用
- 状态可见
- app / 网站过滤
- retention 配置
- DLP 与敏感信息过滤

来源：

- [Recall overview](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/recall/)
- [Manage Recall](https://learn.microsoft.com/en-us/windows/client-management/manage-recall)

对 OpenStaff 的启发：

1. 观察用户电脑的产品，**隐私控制必须先于智能能力**。
2. 可见状态、一键暂停、过滤、保留周期和删除，是默认产品要求。
3. “先做本地优先，再谈更广连接”，是一条被大厂验证过的路径。

### 3.2 Screenpipe

Screenpipe 当前正在快速从“本地屏幕记忆工具”向“本地观察层 + API + MCP + pipes + automation”演进。最近公开可见的方向包括：

- OCR 和 canvas 类应用支持
- MCP server
- pipes / scheduled agents
- OpenAPI
- 本地数据库与本地查询接口
- 与大模型 provider 的组合使用

来源：

- [Screenpipe changelog](https://screenpi.pe/changelog)
- [Screenpipe MCP server](https://docs.screenpi.pe/mcp-server)
- [Screenpipe pipes](https://screenpi.pe/pipes)

对 OpenStaff 的启发：

1. 市场对“**本地观察 + 可查询历史 + 可挂 agent**”这条路线是有明确需求的。
2. 观察层和查询层本身就能成为产品，不需要一开始就全部压在自动执行上。
3. OpenStaff 可以继续把“个人知识结构化”和“skill/review/repair”做得更深，而不必去复制 Screenpipe 的全量录制体验。

### 3.3 Limitless / Rewind

截至本次调研，Limitless 官方首页已明确说明：

- Limitless 已被 Meta 收购
- 不再向新用户销售 Pendant
- `Rewind` 正在 sunset
- desktop 和 web 录制停止
- 若干地区已停止服务
- 但 Developer API / MCP 仍然存在

来源：

- [Limitless home](https://www.limitless.ai/)
- [Limitless Developers](https://www.limitless.ai/developers)

对 OpenStaff 的启发：

1. **云端个人记忆产品存在显著生命周期风险。**
2. “可导出、可迁移、可恢复、本地优先”比功能铺得更大更重要。
3. 即使产品收缩，memory API / MCP 仍然被保留，说明个人记忆资产的可编程化是长期价值点。

### 3.4 OpenAdapt

OpenAdapt 仍然坚持 `learn from demonstration` 的方向，即：

- 录制用户示范
- 学习 GUI 过程
- 再进行回放或自动化

来源：

- [OpenAdapt GitHub](https://github.com/OpenAdaptAI/OpenAdapt)
- [OpenAdapt architecture evolution](https://docs.openadapt.ai/architecture-evolution/)

对 OpenStaff 的启发：

1. “老师示教 -> 学生执行”这条产品叙事仍然有独特性。
2. 但从平台成熟度看，OpenClaw 和 Screenpipe 这类生态层现在更活跃。
3. OpenAdapt 更适合作为“示教学习思想”参考，而不是当前执行底座。

---

## 4. 学术界进展：零训练、个性化与 GUI Agent

### 4.1 Personalized GUI Agent 已经成为正式研究问题

最直接相关的代表工作是：

- [PersonalAlign (2026-01-14)](https://arxiv.org/abs/2601.09636)
- [Learning Personalized Agents from Human Feedback / PAHF (2026-02-18)](https://arxiv.org/abs/2602.16173)

这两类工作共同说明：

1. 个性化 GUI Agent 不是边缘问题，而是正式问题。
2. 关键不在“更大的通用模型”，而在：
   - 长期用户记录
   - 分层个人记忆
   - 模糊指令下的个体化 disambiguation
   - 反馈回写
   - 主动辅助

对 OpenStaff 的意义：

- teaching mode 学个人历史
- assist mode 做个体化下一步预测
- student mode 利用长期偏好和失败经验做更像老师的选择

这个产品方向与当前研究前沿高度一致。

### 4.2 最实用的“零训练”路线是 memory-first

最值得直接借鉴的工作包括：

- [TierMem (2026-02-20)](https://arxiv.org/abs/2602.17913)
- [RF-Mem (2026-03-10)](https://arxiv.org/abs/2603.09250)
- [Structured Distillation for Personalized Agent Memory (2026-03-13)](https://arxiv.org/abs/2603.13017)
- [A Survey of Personalization: From RAG to Agent (2025-04-16)](https://arxiv.org/abs/2504.10147)

这些工作共同给出的高价值共识是：

1. **原始事实不能过早丢弃。**
   - 摘要和规则必须可回链到原始证据。

2. **记忆需要分层。**
   - raw evidence
   - summary
   - procedural memory
   - preference memory

3. **推理时检索比训练新模型更现实。**
   - 在当前阶段，最划算的是优化“拿什么记忆给模型”，而不是先改模型权重。

4. **个性化记忆可以被压缩，但不能失去 provenance。**
   - 这与 OpenStaff 当前做 `skill provenance / review / repair / replay` 的路线完全相容。

对 OpenStaff 的直接建议是：

- 继续坚持本地文件为事实源
- 把 `ObservationBundle -> InteractionTurn -> PreferenceMemory -> SkillArtifact -> Review` 做成强回链结构
- 把个性化优先放在 retrieval、policy assembly、rule promotion、repair prioritization 上

### 4.3 隐私与记忆，仍然是 GUI Agent 的短板

相关工作：

- [MemGUI-Bench (2026-02-03)](https://arxiv.org/abs/2602.06075)
- [GUIGuard (2026-01-26)](https://arxiv.org/abs/2601.18842)

这两条线的信号很重要：

1. 当前 GUI agents 的跨时间、跨会话记忆能力仍然不稳。
2. GUI agents 对隐私敏感内容的识别和治理能力明显不足。

这意味着 OpenStaff 已经在做、并且必须继续强化的能力包括：

- Sensitive scene policy
- learning status surface
- app / window exclusion
- pause / resume
- retention / deletion
- audit log

换句话说，OpenStaff 当前的隐私与可见状态设计，不是工程附加项，而是研究前沿已经承认的刚需。

### 4.4 训练型个性化值得关注，但不应成为当前主线

可以关注但不宜立即主线投入的方向：

- [PersonaMem-v2 (2025-12-07)](https://arxiv.org/abs/2512.06688)

这类工作说明：

1. 训练型 personalization 未来有上限价值。
2. 但从产品落地角度，仍应先做 memory-only 基线。
3. 若未来进入训练型路线，也应该基于高质量个人事实层，而不是直接拿杂乱日志去训。

---

## 5. 对 OpenStaff 的直接启发

### 5.1 产品边界

下一阶段最合理的产品边界应是：

- OpenStaff：学习老师、沉淀知识、偏好回写、repair/review、导出恢复
- OpenClaw：执行、gateway、nodes、工具调用、skills runtime

### 5.2 数据层

OpenStaff 应继续从“点击事件日志”升级到“个人桌面观察资产”：

1. `ObservationBundle`
   - screenshot refs
   - window signature
   - AX / OCR refs
   - semantic target candidates
   - relative / absolute points

2. `InteractionTurn`
   - 一个主线动作回合的最小学习单元

3. `PreferenceMemory`
   - 老师偏好、风险阈值、步骤风格、常用路径、review 习惯

4. `SkillArtifact`
   - 带 provenance 的可执行工件

5. `ExecutionReview`
   - 执行结果、老师反馈、repair 建议、审计记录

### 5.3 个性化策略

短中期最推荐的不是训练，而是：

`现成强模型`
`+`
`Observation / Procedure / Preference Memory`
`+`
`retrieval / rerank`
`+`
`policy assembly`
`+`
`quick feedback -> rule promotion`
`+`
`replay / repair`

### 5.4 里程碑优先级

基于本次调研，下一版最值得优先投入的顺序应是：

1. 主干稳定与单一事实源对齐
2. Observation Bundle / Trace Graph
3. Skill Foundry + Replay / Repair 真机闭环
4. 零训练个性化 v1
5. Gateway / 查询边界 / 数据治理
6. 训练型 personalization 仅作为研究支线

---

## 6. 一句话判断

OpenStaff 现在最值得做的，不是“再造一个会操作电脑的大模型”，而是：

> 把老师的真实电脑操作、老师反馈、skill 工件、执行结果和修复过程，沉淀成一个本地优先、可回放、可恢复、可回写、可审计的个人桌面知识系统；并把 OpenClaw 作为执行平台，而不是学习层。

---

## 7. 参考来源

### OpenClaw

- [OpenClaw Releases](https://github.com/openclaw/openclaw/releases)
- [OpenClaw Docs Hubs](https://docs.openclaw.ai/start/hubs)
- [OpenClaw Gateway Security](https://docs.openclaw.ai/gateway/security)
- [OpenClaw Security](https://github.com/openclaw/openclaw/security)

### 类似软件

- [Microsoft Recall overview](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/recall/)
- [Microsoft Manage Recall](https://learn.microsoft.com/en-us/windows/client-management/manage-recall)
- [Screenpipe changelog](https://screenpi.pe/changelog)
- [Screenpipe MCP server](https://docs.screenpi.pe/mcp-server)
- [Screenpipe pipes](https://screenpi.pe/pipes)
- [Limitless home](https://www.limitless.ai/)
- [Limitless Developers](https://www.limitless.ai/developers)
- [OpenAdapt GitHub](https://github.com/OpenAdaptAI/OpenAdapt)
- [OpenAdapt architecture evolution](https://docs.openadapt.ai/architecture-evolution/)

### 研究

- [PersonalAlign](https://arxiv.org/abs/2601.09636)
- [Learning Personalized Agents from Human Feedback](https://arxiv.org/abs/2602.16173)
- [TierMem](https://arxiv.org/abs/2602.17913)
- [RF-Mem](https://arxiv.org/abs/2603.09250)
- [Structured Distillation for Personalized Agent Memory](https://arxiv.org/abs/2603.13017)
- [MemGUI-Bench](https://arxiv.org/abs/2602.06075)
- [GUIGuard](https://arxiv.org/abs/2601.18842)
- [PersonaMem-v2](https://arxiv.org/abs/2512.06688)
- [A Survey of Personalization: From RAG to Agent](https://arxiv.org/abs/2504.10147)

