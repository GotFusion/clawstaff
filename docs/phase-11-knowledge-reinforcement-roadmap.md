# ClawStaff 下一阶段技术计划（Phase 11）

版本：v0.11.2-roadmap  
更新时间：2026-03-18

## 1. 路线定位

ClawStaff Phase 11 可以直接理解成一件更朴素的事：

给现有 `Capture -> Knowledge -> Skill -> Execute -> Review` 主链路补上一层**反馈数据层 + 偏好回写层**。

本阶段只承诺交付 3 类能力：

1. 把一次主线桌面任务落成一条可追溯的 learning trace，而不是散落的 capture / review / log 文件。
2. 把 review、repair、replay、benchmark 里的反馈抽成两类可用信号：`evaluative` 和 `directive`。
3. 先把这些信号回写到 assist、skill 生成、repair、review 四个模块；student planner 只做带开关接入，不作为默认放开范围。

如果一定要给它起一个短名字，Phase 11 更接近：

- 学习反馈层
- 偏好规则层
- 策略回写层

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

OpenClaw-RL 最值得我们直接吸收的，不是训练器，而是下面 5 个机制：

| OpenClaw-RL 机制 | 对我们的直接映射 |
|---|---|
| `next-state signal` | `NextStateEvidence`：把执行后的老师反馈、环境变化、repair、benchmark 收敛成统一证据 |
| `main-line / side turn` | `TurnLearningEligibility`：只让主线行为进入学习样本 |
| `evaluative + directive` 双通路 | `PreferenceSignal`：把“好不好”和“应该怎么改”分开存 |
| hint judge 只在有 hindsight 时产出 hint | `DirectiveHint`：只有 next-state 真提供纠偏信息时才生成 hint |
| non-blocking record + async scoring | 主执行链路只落盘与发 job，提炼/晋升/评测全走异步 worker |

### 2.1 本阶段直接采用的 5 条规则

1. 每个主线行为 turn 都必须带稳定 `turnId`、`traceId`，并能追溯到 capture、skill、execution、review 原工件。
2. `evaluative` 信号先只用离散值：`pass / fail / neutral`，不在 v0 阶段引入复杂 reward。
3. `directive hint` 只在 next-state 真提供 hindsight 信息时生成；hint 必须 1-3 句、可执行、只描述怎么改。
4. LLM 提炼不直接生效为规则；默认采用 `3` 次投票，至少 `2/3` 一致才接受，否则进入 `needs_review`。
5. 同步链路只负责“记录”和“投递异步任务”，不在老师操作的实时链路里做重提炼、重打分或训练。

### 2.2 本阶段明确不照搬的部分

- GPU 训练基础设施
- SGLang / Megatron / slime 训练栈
- 在线权重更新机制
- teacher log-prob / token-level advantage
- 无门控的实时策略探索

### 2.3 最近的 OpenClaw 变化，对 Phase 11 的直接影响

最近几周 `openclaw/openclaw` 的变化，给我们的启发比论文还更“产品化”：

1. **插件 / provider 边界继续加深**
   - 最近主干连续在做 plugin registry、provider auth contract、provider discovery contract、background service、gateway RPC seams 清理。
   - 这说明 OpenClaw 正在把“核心 agent loop”和“扩展行为”切开。
   - 对我们的要求是：Phase 11 的学习层不要直接绑死在 OpenClaw 内核细节上，而要优先提供：
     - 文件工件
     - hook 事件
     - gateway 方法
     - 可由插件消费的结构化输出

2. **备份 / 恢复已经变成一等能力**
   - `openclaw backup create` / `verify` 已把 `manifest.json + payload validation` 变成正式能力。
   - 这说明用户已经不再把 agent 状态当“可丢弃缓存”，而是当作资产。
   - 对我们的要求是：偏好规则、学习工件、审计日志也要能导出、校验、恢复。

3. **技能与会话快照默认“下一轮生效”**
   - OpenClaw 对 skills 用 session snapshot，并支持 watcher / hot reload。
   - 这给了我们一个很好的默认行为：新晋升的偏好规则默认在**下一次新任务 / 新 session**生效，避免中途静默改规划。

4. **会话连续性与执行恢复在持续加强**
   - 最近 release 明确修了 session reset 保留上下文、browser existing-session 生命周期、防重复投递等问题。
   - 对我们的要求是：Phase 11 不能只关注“学到什么”，还要关注“学习结果在会话恢复时是否稳定”。

5. **输入体验在变低摩擦**
   - Talk mode、Voice Wake、移动端 onboarding、chat settings 等变化说明：用户越来越期待低摩擦输入、明确状态反馈、少配置打断。
   - 对我们的要求是：老师给反馈不能依赖长文本备注，必须支持一键确认、一键驳回、单键修正理由。

### 2.4 市场与竞品信号

结合相关软件，可以看到这个方向已经形成 4 条比较稳定的市场规律：

1. **记忆类产品先拼信任，再拼智能**
   - Microsoft Recall、Rewind、Screenpipe 都把“本地处理、暂停、过滤、删除、可控”放在首位。
   - 这意味着我们的“观察老师电脑”必须默认带：
     - 可见状态
     - 一键暂停
     - app / 窗口排除
     - 敏感场景过滤

2. **录制式自动化产品先拼上手速度**
   - Keysmith、Keyboard Maestro、Shortcuts 的共同点不是“更聪明”，而是“更快录出来、更快触发、更快改”。
   - 这意味着我们的 teaching / assist UX 要优先支持：
     - 一次录制
     - 按 app 生效
     - run by name / 快速调用
     - 失败后就地修，而不是重新大段配置

3. **Agent 平台开始从“功能堆叠”转向“扩展边界清晰”**
   - OpenClaw 最近的 plugin / hook / provider seam 清理，Screenpipe 的 pipes / MCP，也都在说明：生态比单点能力更重要。
   - 这意味着 Phase 11 的学习层应优先提供稳定边界，而不是只在 App 内部长逻辑。

4. **云端个人记忆产品存在明显生命周期风险**
   - Rewind / Limitless 这类产品已经出现能力收缩、地区受限、桌面能力下线或 capture 策略调整。
   - 这意味着我们的个人知识与偏好必须做到：
     - 本地优先
     - 文件可迁移
     - 不依赖单一云服务才能读回历史
     - 可以脱离某个供应商继续工作

### 2.5 代表性产品与技术实现拆解（截至 2026-03-17）

这轮调研里，真正值得参考的，不是“谁更像我们”，而是“谁把某一层做得足够清楚，可以直接拿来当实现参考”。

| 类别 | 代表产品 | 当前可见实现特征 | 对 Phase 11 的直接借鉴 | 不建议照搬 |
|---|---|---|---|---|
| 系统级记忆 / 回忆 | Microsoft Recall / Click to Do | `opt-in` 快照、本地分析、任务栏状态图标、app / 网站过滤、导出与重置、基于屏幕分割与图像识别的本地语义理解 | 学习状态必须可见；默认本地优先；capture 必须支持暂停、排除、导出、恢复；未来如做历史检索，应优先做“可解释的本地回放” | 不把全天候快照当 v0 默认；不复制 Windows 专属分割栈 |
| 本地观察与可检索上下文 | Screenpipe | 本地优先；事件驱动抓屏；同时间点保留 screenshot、accessibility tree、OCR 回退；本地 SQLite；通过 localhost API、pipes、MCP、OpenClaw skill 暴露查询 | `Capture` 不应只存点击坐标，应该存 `ObservationBundle`；学习层要天然支持被 agent / skill 查询，而不是只给 App 内部逻辑使用 | 不照搬其 24/7 全量采集默认体验；不把长时音频采集放进 Phase 11 v0 |
| 个人记忆与隐私控制 | Rewind | 本地录制与转写、菜单栏可见状态、暂停、app 排除、保留量控制、隐私模式排除 | 学习模式应内建可见状态、暂停和排除；后续若扩展长时记忆，必须先有 retention 与删除策略 | 不把“长期全盘录制”当成当前主线；不让 retention 规则晚于 capture 落地 |
| 示范学习 / 录制后回放 | OpenAdapt | 录屏 + 输入记录 + 任务分解 + synthetic replay；不确定时允许用户 takeover；强调从 demonstration 到 automation 的桥 | teaching 数据应同时保留“老师怎么做”和“系统如何复现”；失败后先给接管 / 修复入口，而不是直接静默重试 | 不直接引入完整 Python runtime 作为主执行面；不把模型控制的 replay 直接越过现有 safety gate |
| 录制式自动化 / 快速触发 | Keysmith / Keyboard Maestro | 快速录制；按 app / 网站作用域生效；可用名字、热键、palette、CLI / URL scheme / AppleScript 触发；失败后容易手改 | teaching UX 要优先“录出来就能跑”；知识条目要有 `app` 作用域、名字、快速调用入口；执行入口要支持命令式调用 | 不把复杂宏编辑器整体搬进 v0；不依赖纯坐标回放 |
| 系统原生动作编排 | Apple Shortcuts / App Intents | app 显式暴露 capabilities，系统可通过菜单、快捷键、Services、命令行、Spotlight 等调用 | 需要把 `nativeAction` 与 `guiAction` 分开建模；能走 Shortcuts / AppleScript / CLI / 原生 API 的步骤，不应退化成屏幕点击 | 不假设所有 app 都会暴露原生动作；原生动作不足时仍要保留 GUI 技能链路 |

基于上面的产品拆解，可以把我们真正要学的东西压缩成 6 条：

1. **capture 要从“点击坐标”升级为“事件驱动的观察包”**
   - 每次可学习动作至少应补齐：
     - 动作前后 screenshot 引用
     - 窗口签名 / app context
     - accessibility snapshot 引用
     - OCR / 文本锚点摘要
     - browser URL / title（若可得）
     - 绝对坐标 + 相对坐标
     - 现有 `SemanticTarget` 候选集引用

2. **`ObservationBundle` 与 `InteractionTurn` 必须分层**
   - `ObservationBundle` 是事实层，负责“当时看到了什么”。
   - `InteractionTurn` 是学习层，负责“这轮是否该学、学到了什么”。
   - 这样才能支持回填、重建、导出，而不用重复拷贝原始大文件。

3. **技能生成必须区分 `nativeAction` 与 `guiAction`**
   - `nativeAction` 优先走 `Shortcuts / AppleScript / CLI / app-specific API`。
   - `guiAction` 再走 `OpenClaw + SemanticTarget + fallback locator`。
   - 同一个任务允许混合两类 action，但治理和审计要分开。

4. **GUI 技能必须强制多候选 locator，而不是单点回放**
   - 推荐固定顺序：
     - `AX`
     - `text anchor / DOM / 可读属性`
     - `image anchor`
     - `relative coordinate`
     - `absolute coordinate`
   - 这能把 Keysmith 式“快录快跑”和我们已有的语义定位能力接起来。

5. **学习结果必须天然可查询，而不是只存在内部状态里**
   - 文件是事实源。
   - SQLite / FTS / embedding 只做索引。
   - 对外至少能暴露：
     - 历史观察检索
     - 偏好规则查询
     - bundle 导出
     - trace / turn 追溯

6. **老师接管 / 快速修复必须是一等能力**
   - 录制式自动化工具和 OpenAdapt 的共同点都说明：
   - 真正提高可用性的，不是“自动得更猛”，而是“不确定时能立刻接管并把修正沉淀回去”。

### 2.6 调研后的实现路线收敛

如果把“观察老师操作 -> 生成知识 -> 转成 OpenClaw skill”拆成最适合当前代码继续推进的路径，建议固定为下面 7 层：

1. **Trigger Layer**
   - 只在 teaching、assist、student 审阅回放三类任务态下开启。
   - 触发器优先收敛到：
     - app activated
     - window focused
     - mouse up / click committed
     - command shortcut
     - browser URL / title changed
     - assist accept / reject

2. **Observation Layer**
   - 复用现有 `data/raw-events/**/*.jsonl`，但为每个主线动作补一个 sidecar `ObservationBundle`。
   - 第一版不新建整套平行录屏体系，只补：
     - screenshot refs
     - accessibility refs
     - OCR summary
     - relative point
     - window signature
     - optional browser metadata

3. **Action Normalization Layer**
   - 把原始事件归一成 `ActionAtom` 或等价契约。
   - 每个动作先分两类：
     - `nativeAction`
     - `guiAction`

4. **Locator Assembly Layer**
   - `guiAction` 复用现有 `SemanticTarget`，但强制输出候选顺序与 fallback 说明。
   - `nativeAction` 只记录调用入口、参数与回执，不参与 GUI locator 修复。

5. **Skill Materialization Layer**
   - `nativeAction` 优先转成原生 adapter。
   - `guiAction` 再转成 OpenClaw skill。
   - skill metadata 必须写入：
     - 来源 trace
     - observation refs
     - 命中的 preference rules
     - action kind

6. **Review / Repair Layer**
   - 失败优先产出结构化 repair reason，而不是一句“执行失败”。
   - 如果失败原因来自 locator，就回到 `guiAction` 的 locator repair。
   - 如果失败原因来自动作类型判断错误，就回到 `nativeAction` / `guiAction` 分类修正。

7. **Gateway / Query Layer**
   - 给 OpenClaw、外部 worker、后续 MCP 插件暴露稳定边界：
     - `turns.search`
     - `observations.get`
     - `preferences.listRules`
     - `preferences.exportBundle`
   - 不允许外部直接依赖桌面 App 内部对象图。

### 2.7 市场调研之后，Phase 11 的收敛结论

基于上面的 OpenClaw 变化、用户体验趋势和竞品取向，Phase 11 不再按“大而全个人操作系统”展开，而先收敛成下面 6 个 `v0` 产品决策：

1. **学习只在任务态开启，不做全天候无感录屏**
   - 第一版只在 teaching、assist、student 审阅回放这 3 类任务态里进入学习流程。
   - 不把“24/7 被动记录整个桌面”作为默认产品能力。

2. **先把老师可见控制面做出来，再谈持续学习**
   - 第一版必须先有：
     - 菜单栏或悬浮状态
     - 一键暂停 / 恢复
     - app / 窗口排除
   - 如果老师看不见系统是否在学，就不应默认打开学习模式。

3. **老师反馈优先走 quick actions，不要求长文字**
   - 第一版反馈入口只做：
     - `通过`
     - `驳回`
     - `修 locator`
     - `重示教`
     - `太危险`
     - `顺序不对`
     - `风格不对`
   - 文字备注只作为补充，不作为主入口。

4. **偏好作用域先收敛到 3 层**
   - 第一版只优先稳定：
     - `global`
     - `app`
     - `taskFamily`
   - `windowPattern`、跨设备共享 profile、复杂 persona 合并先不做。

5. **学习资产必须文件优先，可导出、可恢复**
   - 第一版就要能把 turns、signals、rules、profiles、audit 导出成 bundle。
   - SQLite 最多做索引，不做唯一事实源。

6. **对 OpenClaw 先接边界，不反向侵入内核**
   - 第一版优先交付：
     - 文件工件
     - hook 事件
     - gateway 查询 / 导出接口
   - 不把 OpenClaw 当前 plugin 内部对象当成长期稳定依赖。

### 2.8 本轮调研来源

- [Microsoft Support - Retrace your steps with Recall](https://support.microsoft.com/en-us/windows/retrace-your-steps-with-recall-aa03f8a0-a78b-4b3e-b0a1-2eb8ac48701c)
- [Microsoft Support - Filtering apps, websites, and sensitive information in Recall](https://support.microsoft.com/en-us/windows/filtering-apps-websites-and-sensitive-information-in-recall-a4c28bee-e200-4a4a-b60d-c0522b404a5b)
- [Microsoft Learn - Click to Do overview](https://learn.microsoft.com/en-us/windows/ai/click-to-do/)
- [Screenpipe Docs - How it works](https://docs.screenpi.pe/architecture)
- [Screenpipe Docs - OpenClaw](https://docs.screenpi.pe/openclaw)
- [OpenAdapt GitHub README](https://github.com/OpenAdaptAI/OpenAdapt)
- [Keysmith - Examples](https://www.keysmith.app/examples)
- [Keyboard Maestro Wiki - Record Quick Macro](https://wiki.keyboardmaestro.com/action/Record_Quick_Macro)
- [Keyboard Maestro Wiki - Macro Groups](https://wiki.keyboardmaestro.com/manual/Macro_Groups)
- [Apple Developer - App Intents](https://developer.apple.com/documentation/appintents)
- [Apple Support - Intro to Shortcuts on Mac](https://support.apple.com/guide/shortcuts-mac/intro-to-shortcuts-apdf22b0444c/mac)
- [Apple Support - Launch a shortcut from another app on Mac](https://support.apple.com/guide/shortcuts-mac/launch-a-shortcut-from-another-app-apd163eb9f95/mac)

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

但要把它做成一个能持续复用老师习惯的桌面助理，还缺 10 个很具体的工程件：

1. **`InteractionTurn` 文件和回填脚本**
   - 还没有一条“这一轮到底做了什么”的统一记录。
2. **`NextStateEvidence` 统一证据层**
   - 还没有把 review、repair、drift、benchmark 放进同一种 evidence 结构。
3. **规则优先的信号提炼器**
   - 还没有先用确定性规则从结构化工件中提取基础偏好。
4. **LLM 辅助的 hint / signal 提炼器**
   - 还没有把老师备注、修正说明转成可执行的 directive hint。
5. **偏好记忆与回写装配层**
   - 还没有把 signal 变成 rule，再回写到 assist / skill / repair / review。
6. **偏好专项 benchmark**
   - 还没有一套能回答“系统有没有更像这个老师”的稳定评测。
7. **老师侧的学习状态与反馈入口**
   - 还没有把“现在是否在学习、如何暂停、如何一键反馈”做成明确表面。
8. **可迁移资产与外部集成边界**
   - learning bundle 导出 / 校验 / 恢复已落地，但稳定 hook / gateway 契约仍待补齐。
9. **`ObservationBundle` 统一观察包**
   - 还没有把点击前后截图、窗口上下文、AX 引用、OCR 摘要、相对坐标、浏览器上下文收成同一条事实记录。
10. **`nativeAction` / `guiAction` 双轨动作模型**
   - 还没有把原生能力调用与 GUI 模拟操作分开建模，因此后续 skill 生成、repair 与安全治理仍会互相污染。

---

## 4. 下一阶段总目标

Phase 11 的目标，不是“让模型更强”，而是先把下面 5 件事做实：

1. 任意一次主线任务结束后，都能额外落下 `turn.json + evidence.jsonl + signals.json` 三类学习工件。
2. 至少 `20` 条历史任务可回填成 `InteractionTurn`，至少 `30` 条真实审阅样本可提炼出 `PreferenceSignal`。
3. assist、skill 生成、repair、review 至少 `3` 个模块能展示“这次命中了哪些偏好规则，为什么这样做”。
4. 建立一套不少于 `24` 条 case 的 `Personal Preference Benchmark`，能对比偏好学习前后的差异。
5. 老师能在 `1` 次操作内知道系统是否正在学习，并能在 `1` 次操作内暂停、排除或给出 quick feedback。

本阶段完成后，应该能直接回答 5 个问题：

- 这次老师为什么判它通过、驳回或要求修复？
- 这次失败更像 locator 问题、步骤顺序问题，还是风险阈值问题？
- 系统这次为什么优先推荐历史 A，而不是历史 B？
- 这条偏好规则来自哪几次任务，什么时候生效，什么时候应回滚？
- 系统现在到底有没有在学习，如果不该学，老师能否立刻停掉？

---

## 5. 设计原则

### 5.1 知识强化优先于模型训练

- 优先更新知识、规则、模板、检索、排序、阈值和装配逻辑。
- 不将“调模型权重”作为本阶段核心目标。
- 一切改进都应可审计、可回滚、可解释。

### 5.2 偏好是结构化资产，不是零散备注副产物

- 老师的反馈必须被结构化保存。
- ChatGPT 的解析或修正建议必须被标注来源与置信度。
- 每条偏好都需要 provenance、版本和适用范围。

### 5.3 主线学习，非任务产物降噪

- 仅主线任务步骤参与偏好学习。
- 系统状态播报、背景资料整理、纯日志镜像、非任务性辅助说明不直接进入偏好更新。

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

### 5.7 可见采集优先于无感采集

- 学习模式必须有明确可见状态。
- 老师必须能一键暂停、恢复、排除某个 app / 窗口。
- 默认不在敏感场景中继续学习，例如密码、支付、隐私授权、医疗与金融页面。

### 5.8 反馈必须低摩擦

- 老师反馈的默认入口应是一键动作，而不是长文本。
- 推荐最先支持的 quick actions：
  - 通过
  - 驳回
  - 修 locator
  - 重示教
  - 太危险
  - 顺序不对
  - 风格不对

### 5.9 新规则默认下一次任务生效

- 偏好规则默认在下一次新任务 / 新 session 生效。
- 中途热更新只允许：
  - 老师手动确认刷新
  - 或低风险提示层重排
- 不允许在当前自动执行链路中静默切换高风险规则。

### 5.10 学习资产必须可迁移、可备份

- 学习工件、偏好规则、profile、审计日志都必须可导出。
- 导出包必须带 manifest 与校验步骤。
- 不允许把老师长期偏好只存在某个私有数据库黑盒里。

### 5.11 优先提供集成边界，而不是内部耦合

- 学习层优先输出文件、hook、gateway RPC、可消费 schema。
- 不把 OpenClaw 内部私有对象当作长期契约。
- 未来无论接 OpenClaw 插件、Screenpipe、还是自有 worker，都应尽量复用这层边界。

---

## 6. 核心架构升级

### 6.1 新增闭环抽象

当前：

`Capture -> Knowledge -> Skill -> Execute -> Review`

Phase 11 之后：

`Observe -> Plan -> Execute -> Next-State -> Review -> Preference Extract -> Policy Assemble -> Verify -> Reuse`

其中新增的关键层有：

1. `NextState Layer`
   - 汇总执行后的环境反馈、老师反馈、ChatGPT 提炼/修正建议、repair action、benchmark 结果。
2. `Preference Extraction Layer`
   - 从 next-state 中提炼 `evaluativeDecision + directiveHint`，并归类为 outcome / procedure / locator / style / risk / repair 信号。
3. `Preference Memory Layer`
   - 将信号沉淀为长期生效的偏好记忆。
4. `Policy Assembly Layer`
   - 在 assist、student、skill 生成、review 中装配这些偏好。
5. `Preference Verification Layer`
   - 通过 benchmark 和 replay 验证偏好是否真的改善结果。

### 6.2 同步链路与异步链路边界

为避免把 OpenClaw-RL 的“异步四环”误做成桌面 App 内的同步重活，Phase 11 采用下面的边界：

**同步主链路只做 3 件事**

1. 给每个主线行为分配 `turnId` / `traceId`。
2. 把 capture、skill、execution、review 的原始路径写入 manifest。
3. 在任务完成后投递异步 learning job。

**异步 worker 再做 4 件事**

1. 组装 `InteractionTurn`。
2. 生成 `NextStateEvidence`。
3. 提炼 `PreferenceSignal` 并尝试晋升 `PreferenceRule`。
4. 汇总 benchmark 和 drift 指标。

这意味着：

- 老师操作电脑时，不等待 hint 提炼、规则晋升或 benchmark。
- 所有学习结果都必须可重放、可回填、可删除后重建。

### 6.3 观察层与动作层的推荐拆分

结合这轮调研，Phase 11 最值得先固化的，不是再加一个“更聪明的学习器”，而是把观察和动作边界先拆对。

建议按下面 6 个对象组织第一版代码：

1. `ObservationBundle`
   - 代表“老师做这一步时，系统当时看到的上下文”。
   - 应优先引用现有 raw-event、screenshot、window signature、`SemanticTarget` 工件，而不是重复拷贝正文。

2. `ActionKind`
   - 第一版固定只分：
     - `nativeAction`
     - `guiAction`
   - 不要求一开始就做更细的动作 taxonomy。

3. `ActionAtom`
   - 代表一个可 replay、可修复、可审阅的最小动作。
   - 例如：
     - 点击某个按钮
     - 触发某个快捷键
     - 调用某个 CLI / AppleScript / Shortcut

4. `LocatorPlan`
   - 只对 `guiAction` 生效。
   - 建议直接复用当前 `SemanticTarget` 候选模型，不再平行发明第二套 locator schema。
   - 但要额外固化：
     - 候选顺序
     - fallback 原因
     - 失败时的 repair 分类

5. `InteractionTurn`
   - 不直接承载全部观测细节，只保存：
     - `ObservationBundle` 引用
     - `ActionKind`
     - `LocatorPlan` 引用
     - execution / review / evidence 引用

6. `SkillMaterializationRecord`
   - 记录这次 turn 最终是如何落成：
     - 原生动作
     - GUI skill
     - 或混合动作链

这样拆完之后，下一步代码编写会更清晰：

1. `capture` 负责写 `ObservationBundle`。
2. `learning` 负责从 `ObservationBundle + review` 生成 `InteractionTurn / PreferenceSignal`。
3. `skill mapper` 负责把 `ActionKind + LocatorPlan` 转成 OpenClaw 或原生 adapter。
4. `repair` 负责修 `LocatorPlan` 或修 `ActionKind`，而不是回头直接改原始 capture。

### 6.4 `v0` 文件落点

Phase 11 第一版先把学习工件固定到以下目录：

- `data/learning/turns/{date}/{sessionId}/{turnId}.json`
- `data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`
- `data/preferences/signals/{date}/{sessionId}/{turnId}.json`
- `data/preferences/rules/{ruleId}.json`
- `data/preferences/profiles/{profileVersion}.json`
- `data/preferences/assembly/{date}/{module}/{sessionId}/{decisionId}.json`
- `data/preferences/audit/{date}.jsonl`

要求：

- 文件层是事实源，便于审计与回填。
- 后续若加 SQLite，只作为索引层，不取代文件层。

### 6.5 新增核心对象

建议新增以下数据对象：

1. `InteractionTurn`
   - 一次可学习的主线动作单元。
   - 连接 capture、knowledge、skill、execution、review。
   - `v0` 最少字段：
     - `turnId`
     - `traceId`
     - `sessionId`
     - `taskId`
     - `mode`
     - `stepIndex`
     - `appContext`
     - `intentSummary`
     - `actionSummary`
     - `learningState`
     - `privacyTags`
     - `riskLevel`
     - `sourceRefs`
     - `startedAt`
     - `endedAt`
     - `status`

2. `NextStateEvidence`
   - 动作之后出现的反馈证据。
   - 来源可以是：
     - 老师明确反馈
     - OpenClaw 执行结果
     - 系统环境变化
     - ReplayVerifier / DriftDetector 输出
     - ChatGPT 修正建议
     - benchmark 判定
   - `v0` 最少字段：
     - `evidenceId`
     - `turnId`
     - `source`
     - `summary`
     - `rawRef`
     - `timestamp`
     - `confidence`
     - `severity`
     - `role`
     - `evaluativeCandidate`
     - `directiveCandidate`

3. `PreferenceSignal`
   - 从 evidence 中提炼出的结构化偏好信号。
   - 基本类型：
     - `outcome`
     - `procedure`
     - `locator`
     - `risk`
     - `style`
     - `repair`
   - `v0` 最少字段：
     - `signalId`
     - `turnId`
     - `type`
     - `evaluativeDecision`
     - `polarity`
     - `scope`
     - `hint`
     - `confidence`
     - `evidenceIds`
     - `proposedAction`
     - `promotionStatus`

4. `PreferenceRule`
   - 已晋升为长期记忆的偏好规则。
   - 第一版默认优先稳定 3 层作用域：
     - `global`
     - `app`
     - `task family`
   - `skill family` 与更细粒度 scope 先保留为扩展位，不作为 v0 默认晋升目标。
   - `v0` 最少字段：
     - `ruleId`
     - `sourceSignalIds`
     - `scope`
     - `statement`
     - `riskLevel`
     - `activationStatus`
     - `teacherConfirmed`
     - `createdAt`
     - `updatedAt`

5. `PreferenceProfile`
   - 用户当前偏好快照。
   - 由多条 `PreferenceRule` 聚合生成。
   - `v0` 最少字段：
     - `profileVersion`
     - `activeRuleIds`
     - `assistPreferences`
     - `skillPreferences`
     - `repairPreferences`
     - `reviewPreferences`
     - `plannerPreferences`

6. `PolicyAssemblyDecision`
   - 某次 assist / student / skill 生成时，实际应用了哪些偏好规则。
   - 用于可解释性与回滚。
   - `v0` 最少字段：
     - `decisionId`
     - `targetModule`
     - `inputRef`
     - `appliedRuleIds`
     - `suppressedRuleIds`
     - `finalDecisionSummary`
     - `timestamp`

### 6.6 偏好信号分类

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

### 6.7 `v0` 老师侧 UX contract

Phase 11 第一版，老师真正会看到并直接使用的表面，只先做 5 个：

1. `Learning Status Surface`
   - 菜单栏或悬浮状态必须显示：
     - 当前模式
     - 当前 app
     - learning `on / paused / excluded / sensitive-muted`
     - 最近一次成功落盘时间

2. `Quick Feedback Bar`
   - 默认只提供 7 个 quick actions：
     - `通过`
     - `驳回`
     - `修 locator`
     - `重示教`
     - `太危险`
     - `顺序不对`
     - `风格不对`
   - 允许可选补充备注，但备注不应成为必填入口。

3. `Privacy / Exclusion Panel`
   - 第一版必须支持：
     - app 排除
     - 窗口标题排除
     - `15` 分钟临时暂停
     - 敏感场景自动静默

4. `Rule Hit Explanation Card`
   - assist、repair、review 三个表面必须能显示：
     - 命中的 rule ids
     - 命中原因
     - 生效范围
     - 是否下次任务才生效

5. `Learning Bundle Export Entry`
   - 设置页或工具页必须能触发：
     - 导出 bundle
     - 校验 bundle
     - 恢复前 dry-run 预览

---

## 7. 分阶段技术路线

执行原则：

- 每周必须产出 3 样东西：可回放样本、脚本入口、简短结果报告。
- 先打通一条最小闭环，再扩信号类型和接入模块。
- student planner 永远排在最后，且默认挂在 feature flag 后面。

### 阶段 11.0：老师侧 UX 与隐私基线（Week 1）

#### 目标

先把“老师敢开、愿意给反馈”的产品表面做出来，再开始累积 learning trace。

#### TODO 11.0.1 落地 `Learning Status Surface`

- 第一版最少显示：
  - 当前模式
  - 当前 app
  - learning `on / paused / excluded / sensitive-muted`
  - 最近一次落盘结果
- 优先放菜单栏和轻量悬浮层，不做复杂控制台。

**输出物**
- `apps/macos/Sources/OpenStaffApp/*`
- `core/learning/LearningSessionState.swift`
- `docs/ux/learning-status-surface-v0.md`

**验收标准**
- [x] 老师能在 `1` 次视线切换内知道系统是否正在学习。
- [x] 暂停 / 恢复在 `1` 次点击内完成。

#### TODO 11.0.2 落地 `Quick Feedback Bar`

- 第一版固定支持 7 个 quick actions：
  - `通过`
  - `驳回`
  - `修 locator`
  - `重示教`
  - `太危险`
  - `顺序不对`
  - `风格不对`
- 每个 quick action 必须能落成标准化 `teacherReview` evidence。
- 可选备注限制在短句补充，不要求长段说明。

**输出物**
- `core/contracts/TeacherQuickFeedbackContracts.swift`
- `apps/macos/Sources/OpenStaffApp/*`
- `docs/ux/teacher-quick-feedback-v0.md`

**验收标准**
- [ ] 抽样 `20` 次 review 中，至少 `16` 次可只靠 quick actions 完成。
- [ ] 单次反馈中位耗时不高于 `8` 秒。

#### TODO 11.0.3 落地 `Privacy / Exclusion Panel`

- 第一版必须支持：
  - [x] app 排除名单
  - [x] 窗口标题排除规则
  - [x] `15` 分钟临时暂停
  - [x] 敏感页面自动静默
- 敏感场景至少先覆盖：
  - [x] 密码输入
  - [x] 支付
  - [x] 隐私授权
  - [x] 医疗 / 金融

**输出物**
- [x] `config/learning-privacy.example.yaml`
- [x] `core/learning/SensitiveScenePolicy.swift`
- [x] `docs/ux/learning-privacy-controls-v0.md`

**验收标准**
- [x] 被排除 app / 窗口不会继续生成 learning 工件。
- [x] 自动化回归样本中 `capture-policy-violation-count = 0`。

### 阶段 11.1：学习数据层（Week 2）

#### 目标

先把学习工件落盘，而不是先讨论偏好规则。

#### TODO 11.1.1 定义并落盘 `InteractionTurn`

- 先只覆盖主线任务推进、主线 skill 执行、主线 repair 三类 turn。
- 每个 turn 必须引用一条 `ObservationBundle` 或等价 sidecar，而不是只剩点击坐标和文本摘要。
- 每个 turn 必须显式区分：
  - `nativeAction`
  - `guiAction`
- 每个 turn 必须写到：
  - `data/learning/turns/{date}/{sessionId}/{turnId}.json`
- 历史回填先做 `20` 条样本，至少覆盖：
  - teaching
  - student
  - assist（仓库当前先以 example fixture 固化 schema；真实 assist log 入库后再补历史批量回填）

**输出物**
- `core/contracts/InteractionTurnContracts.swift`
- `core/learning/InteractionTurnBuilder.swift`
- `scripts/learning/build_interaction_turns.py`
- `core/learning/examples/interaction-turns/*.json`

**验收标准**
- [x] 20 条历史任务能批量回填成 `InteractionTurn`。
- [x] 任意一条 benchmark-backed `InteractionTurn` 都能追溯到 capture、skill、execution、review 原工件。
- [x] 抽查样本时，能从 `InteractionTurn` 回看该步的窗口上下文、raw-event sidecar 引用与 locator 候选；截图 / AX / OCR refs 待 `ObservationBundle` 正式落盘后补齐。

#### TODO 11.1.2 定义并落盘 `NextStateEvidence`

- 每条 evidence 必须写到：
  - `data/learning/evidence/{date}/{sessionId}/{turnId}.jsonl`
- 第一版只接 6 类来源：
  - teacherReview
  - executionRuntime
  - replayVerify
  - driftDetection
  - chatgptSuggestion
  - benchmarkResult
- 若 evidence 指向 GUI 失败，必须能说明它是在：
  - locator 解析失败
  - 动作分类错误
  - 风险阻断
  三类中的哪一种

**输出物**
- `core/contracts/NextStateEvidenceContracts.swift`
- `core/learning/NextStateEvidenceBuilder.swift`
- `core/learning/next-state-evidence-v0.md`
- `core/learning/schemas/next-state-evidence.schema.json`
- `scripts/learning/build_next_state_evidence.py`

**验收标准**
- [x] 20 条 `InteractionTurn` 中，至少 15 条能补出 1 条以上 evidence。
- [x] evidence 只保留摘要和原始引用，不复制大文件正文。

#### TODO 11.1.3 主线 / 非主线任务片段分类器

- `TurnLearningEligibility` 输出固定为：
  - `eligible`
  - `ineligible`
  - `needs_review`
- 每次判断都必须带 `reasonCode`，例如：
  - `status_only`
  - `log_only`
  - `background_only`
  - `mainline_repair`

**输出物**
- `core/learning/TurnLearningEligibility.swift`
- `core/learning/turn-learning-eligibility-v0.md`
- `docs/adr/ADR-0011-mainline-vs-side-turns.md`

**验收标准**
- [ ] 抽查 50 条历史记录时，学习无关片段不会自动进入偏好更新流程。
- [x] 每条被排除记录都能说明“为什么不学”。

---

### 阶段 11.2：偏好信号提炼层（Week 3 ~ Week 4）

#### 目标

先把反馈变成可执行信号，不急着把信号变长期规则。

#### TODO 11.2.1 定义 `PreferenceSignal` 模型

- `evaluative` 先只允许：
  - `pass`
  - `fail`
  - `neutral`
- `directive payload` 在存在 hindsight 时必须包含：
  - `hint`
  - `scope`
  - `proposedAction`

**输出物**
- `core/contracts/PreferenceSignalContracts.swift`
- `core/learning/preference-signal-v0.md`
- `core/learning/schemas/preference-signal.schema.json`

**验收标准**
- [x] outcome / procedure / locator / style / risk / repair 六类信号均可表达。

#### TODO 11.2.2 先做规则优先提炼器 v0

- 第一版先不用 LLM 处理所有来源，只先从结构化输入提炼：
  - review action
  - replay verify
  - drift reason
  - benchmark result
  - safety block
- 输出固定写到：
  - `data/preferences/signals/{date}/{sessionId}/{turnId}.json`

**输出物**
- `core/learning/RuleBasedPreferenceSignalExtractor.swift`
- `core/learning/examples/preference-signals-rule-based/*.json`

**验收标准**
- [x] 对 30 条真实审阅样本，至少 60% 能产出 1 条以上有效信号。
- [x] 能区分“结果不满意”和“修法不满意”。

#### TODO 11.2.3 再做 LLM 辅助 hint 提炼器 v1

- 输入固定为 4 段：
  - 上一步动作摘要
  - next-state 摘要
  - next-state role
  - 老师备注或修正说明
- 输出固定 JSON：
  - `decision`
  - `hint`
  - `signalType`
  - `scope`
  - `confidence`
- 默认采用 `3` 次投票：
  - 至少 `2/3` 一致才接受
  - hint 必须是 `1-3` 句
  - hint 只写“怎么改”，不写空泛评价

**输出物**
- `scripts/learning/extract_preference_signals.py`
- `scripts/learning/prompts/preference-hint-extractor.md`
- `scripts/learning/schemas/preference-extraction-output.schema.json`

**验收标准**
- [ ] 对自由文本备注样本，结构化输出成功率不低于 80%。
- [x] 不满足投票或格式要求的样本统一进入 `needs_review`。

补充说明：

- 当前仓库已补齐 `provider=openai`、离线 `heuristic/mock`、`3-vote` 多数接受、schema 校验、`1-3` 句可执行 hint 校验与 `needs_review` 落盘路径。
- `80%` 结构化成功率指标仍需要在真实 `OpenAI` 联机环境下补跑，不在本次离线回归内宣称完成。

#### TODO 11.2.4 生成 `DirectiveHint`

- hint 只服务 4 类下游模块：
  - assist rerank
  - skill mapper
  - repair planner
  - review suggestion
- checklist 中对应 `TODO 11.2.5`；两份文档的编号在本次实现后已通过说明对齐，不再把 `DirectiveHint` 与 signal merger 混写。

**输出物**
- `core/learning/DirectiveHintBuilder.swift`
- `core/learning/directive-hint-template-v0.md`

**验收标准**
- [x] 每条被接受的 directive signal 至少能生成 1 条可直接消费的 hint。

---

### 阶段 11.3：偏好记忆层（Week 5）

#### 目标

把 signal 变成可治理的 rule，并设定默认晋升阈值。

#### TODO 11.3.1 实现 `PreferenceMemoryStore`

- 第一版只做文件事实源：
  - signals
  - rules
  - profiles
  - audit
- 目录必须和 6.4 保持一致。

**输出物**
- `core/storage/PreferenceMemoryStore.swift`
- `data/preferences/`
- `docs/adr/ADR-0014-preference-memory-store.md`

**验收标准**
- [x] 所有规则都能追溯到原始 signal 和 evidence。
- [ ] 删除某条规则后，可从 signal 重新计算 profile。
  - 当前 `PreferenceMemoryStore` 已保留 `signals / rules / profiles / audit` 事实源与回链信息，但自动重建 profile 的 builder / rollback 流程仍待 `11.3.3` 与 `11.6.3` 完成。

#### TODO 11.3.2 固化默认晋升与冲突策略

- 第一版默认阈值建议：
  - `low risk`：至少 `3` 条 signal、跨 `2` 个 session、平均置信度 `>= 0.75`
  - `medium risk`：至少 `4` 条 signal、跨 `3` 个 session、最近无显式驳回
  - `high risk`：无论命中多少次，都必须 `teacherConfirmed`
- 第一版默认自动晋升 scope：
  - `global`
  - `app`
  - `taskFamily`
  - `skill family` 与更细粒度 scope 暂不自动晋升
- 冲突规则默认优先级：
  - 更具体 scope
  - 最近明确确认
  - 更低风险范围

**输出物**
- `core/learning/PreferenceRulePromoter.swift`
- `core/learning/PreferenceConflictResolver.swift`
- `config/preference-promotion.example.yaml`
- `docs/adr/ADR-0015-preference-rule-promotion-and-governance.md`

**验收标准**
- [x] 单次偶发反馈不会直接成为长期规则。
- [x] 同一任务族下规则冲突可结构化解释。

#### TODO 11.3.3 形成 `PreferenceProfile`

- 第一版 profile 先只聚合 5 组信息：
  - assist
  - skill generation
  - repair
  - review
  - planner
- checklist 中对应 `TODO 11.3.5`；本次实现已补齐 builder 与查看 CLI，后续请以“roadmap 11.3.3 = checklist 11.3.5”理解编号映射。

**输出物**
- `core/learning/PreferenceProfileBuilder.swift`
- `data/preferences/profiles/`
- `apps/macos/Sources/OpenStaffPreferenceProfileCLI/*`

**验收标准**
- [x] GUI 或 CLI 可查看当前生效规则和 profile 快照。

---

### 阶段 11.4：策略装配层（Week 6 ~ Week 7）

#### 目标

按“低风险模块优先”的顺序接入偏好，不一次性把所有模块全改掉。

#### TODO 11.4.1 Assist 偏好重排先落地

状态：已完成（2026-03-19，统一 assembly log 已在 TODO 11.4.6 落盘）

- 只改 rerank，不改基础 retrieval。
- 输出必须附带：
  - 命中的 rule ids
  - 被压低分的候选原因

**输出物**
- `core/orchestrator/PreferenceAwareAssistPredictor.swift`
- `core/contracts/AssistPreferenceContracts.swift`

**验收标准**
- [x] assist 推荐可解释“为什么这次选择了历史 A 而不是历史 B”。

#### TODO 11.4.2 Skill mapper 第二个接入

状态：已完成（2026-03-19，统一 `PolicyAssemblyDecision` 落盘已在 TODO 11.4.6 完成）

- 第一版只改：
  - `nativeAction` / `guiAction` 分流
  - locator 顺序
  - prompt 约束
  - 风险确认要求
- `nativeAction` 优先走 `Shortcuts / AppleScript / CLI / app adapter`。
- `guiAction` 固定按以下顺序装配 locator：
  - `AX`
  - `text anchor / DOM / 可读属性`
  - `image anchor`
  - `relative coordinate`
  - `absolute coordinate`
- 保持 `openstaff.openclaw-skill.v1` 与现有 preflight 门槛不变；为 traceability 在 v1 上新增可选 preference 审计字段。

**输出物**
- `scripts/skills/openclaw_skill_mapper.py`
- `scripts/skills/templates/*`

**验收标准**
- [x] skill 产物能写出“本次引用的偏好规则”摘要。

本次落地说明：
- GUI workflow 调 mapper 时会自动传入 `data/preferences`，skill build 默认读取最新 profile。
- `nativeAction` 步骤会记录 `Shortcuts / AppleScript / CLI / app adapter` 的优先顺序；`guiAction` 会把 locator 候选按固定顺序写入 `stepMappings`。
- `SKILL.md` frontmatter metadata 与 `openstaff-skill.json -> provenance.skillBuild / stepMappings` 会同时记录命中的 preference rule ids、profile version 与 step 级说明。

#### TODO 11.4.3 Repair planner 第三个接入

状态：已完成（2026-03-19，统一 `PolicyAssemblyDecision` 落盘已在 TODO 11.4.6 完成）

- 第一版只让偏好影响：
  - 先修 locator
  - 先 replay
  - 重新示教
  三者的优先级。

**输出物**
- `core/repair/PreferenceAwareSkillRepairPlanner.swift`

**验收标准**
- [x] repair 建议可解释“为什么先给这个修法”。

本次落地说明：
- `PreferenceAwareSkillRepairPlanner` 会在默认 drift->repair heuristics 之上，对 `PreferenceProfile.repairPreferences` 做二次排序。
- repair plan 会把命中的 `rule ids`、候选修法的 `preferenceReason` 与结构化 `preferenceDecision` 一起写入 JSON 输出。
- GUI 技能详情页与 `OpenStaffReplayVerifyCLI --skill-dir` 都会自动尝试读取最新 `data/preferences` profile；skill provenance 中已有的 `taskFamily / skillFamily` 也会参与作用域匹配。

#### TODO 11.4.4 Review 建议第四个接入

状态：已完成（2026-03-19，统一 `PolicyAssemblyDecision` 落盘已在 TODO 11.4.6 完成）

- 审阅台只做建议排序，不自动替老师做决定。

**输出物**
- `core/storage/ExecutionReviewStore.swift`
- `apps/macos/Sources/OpenStaffApp/*`

**验收标准**
- [x] review 建议不再是统一模板，而是能显示个体偏好命中。

本次落地说明：
- `ExecutionReviewStore` 现会在“三栏对照 + repair 建议”基础上，结合最新 `PreferenceProfile.reviewPreferences` 生成 `reviewSuggestions` 与 `reviewPreferenceDecision`。
- 审阅台会展示“推荐动作 / 推荐短备注 / 规则来源”，并显式说明诸如“你通常更倾向于先修 locator”这类偏好命中原因。
- `Quick Feedback Bar` 仍保持固定 7 个动作与原快捷键，不会自动代老师提交，只负责给出更贴近个人偏好的排序与说明。

#### TODO 11.4.5 Student planner 最后接入，且默认挂 feature flag

状态：已完成（2026-03-19，benchmark runner 仍在 TODO 11.5，但启用门槛已通过显式 attestation gate 预留）

- 只有满足以下条件才接 student：
  - preference benchmark 已跑通
  - `unsafe-auto-execution-regression = 0`
  - assist / skill / repair 至少 3 个模块稳定

**输出物**
- `core/orchestrator/PreferenceAwareStudentPlanner.swift`
- `core/contracts/PlanningPreferenceContracts.swift`
- `scripts/llm/prompts/student/*`

**验收标准**
- [x] student planner 默认关闭，需显式开关才能启用。

本次落地说明：
- 新增 `PreferenceAwareStudentPlanner`，会对 `PreferenceProfile.plannerPreferences` 做候选知识条目重排，并把命中的 `rule ids`、执行姿态（`conservative / assertive`）与失败恢复偏好（`repairBeforeReteach / reteachBeforeRepair`）写入 `StudentExecutionPlan.preferenceDecision`。
- `OpenStaffStudentCLI` 默认仍走 `RuleBasedStudentTaskPlanner`；只有同时传入 `--enable-preference-aware-planner` 与 `--student-planner-benchmark-safe` 才切到偏好装配 planner。
- GUI 的 `IntegratedModeWorkflows.runStudentLoop` 同样默认关闭；仅在 `OPENSTAFF_ENABLE_PREFERENCE_AWARE_STUDENT_PLANNER=1` 与 `OPENSTAFF_STUDENT_PLANNER_BENCHMARK_SAFE=1` 同时满足时启用。
- 已补齐 Swift 单测与 CLI 集成回归，验证默认 `ruleV0` 不变、feature flag 开启后才输出 `preferenceAwareRuleV1`。

#### TODO 11.4.6 记录 `PolicyAssemblyDecision`

状态：已完成（2026-03-19，默认仍挂在 `OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG=1` feature flag 后）

**输出物**
- `core/contracts/PolicyAssemblyDecisionContracts.swift`
- `core/storage/PolicyAssemblyDecisionStore.swift`

**验收标准**
- [x] assist / student / skill generation / repair 在启用 feature flag 时都会写出一条 assembly decision。
- [x] 决策文件统一记录 `appliedRuleIds / suppressedRuleIds / finalWeights / finalDecisionSummary`。
- [x] 日志写入 `data/preferences/assembly/{date}/{module}/{sessionId}/{decisionId}.json`，可按日期 / 模块 / session 查询。

本次落地说明：
- Swift 端新增 `PolicyAssemblyDecisionStore` 与统一 contract，assist / student orchestrator、repair planner CLI 与 GUI 都会在 feature flag 打开时自动写盘。
- Python `scripts/skills/openclaw_skill_mapper.py` 同样支持在相同 feature flag 下落盘 skill generation 的装配决策，不要求额外 CLI flag。
- student planner 的执行开关仍独立受 `--enable-preference-aware-planner` / `--student-planner-benchmark-safe` 与对应 App 环境变量控制；`PolicyAssemblyDecision` 只增加解释性与可追溯性。

---

### 阶段 11.5：偏好学习评测层（Week 8）

#### 目标

建立一套能量化“更像老师了没有”的 benchmark。

#### TODO 11.5.1 建立 `Personal Preference Benchmark`

- 第一版固定做 `24` 条 case：
  - style `6`
  - procedure `6`
  - risk `6`
  - repair `6`
- case 来源建议：
  - `12` 条真实历史任务
  - `12` 条基于真实任务改写的扰动样本

**输出物**
- `data/benchmarks/personal-preference/`
- `docs/personal-preference-benchmark-spec.md`
- `scripts/benchmarks/run_personal_preference_benchmark.py`

**验收标准**
- [x] 24 条 case 都能重复运行并生成稳定 report。

本次落地说明：
- 新增 `data/benchmarks/personal-preference/catalog.json` 与 `manifest.json`，固定 `24` 条 case、`12` 个 profile，覆盖 `style / procedure / risk / repair` 四类偏好，且真实样本与扰动样本各 `12` 条。
- 新增 `scripts/benchmarks/run_personal_preference_benchmark.py`，可从 catalog 自动物化 profile snapshot，并分别驱动 assist / student / review / repair 四条偏好链路，输出 `source-record / module-result / review-result / case-report / manifest`。
- 新增 `docs/personal-preference-benchmark-spec.md` 与 `OpenStaffExecutionReviewCLI`，让 review 建议链路也能被 benchmark 直接回归；当前基线 `personal-preference-v20260319` 已稳定跑通 `24 / 24`。

#### TODO 11.5.2 固化 v0 指标与门槛

- 第一版指标：
  - `preference-match-rate`
  - `assist-acceptance-rate`
  - `repair-path-hit-rate`
  - `teacher-override-rate`
  - `unsafe-auto-execution-regression`
  - `quick-feedback-completion-rate`
  - `median-feedback-latency-seconds`
  - `capture-policy-violation-count`
- 第一版门槛：
  - `preference-match-rate >= 0.70`
  - `repair-path-hit-rate >= 0.60`
  - `unsafe-auto-execution-regression = 0`
  - `teacher-override-rate` 不得比基线恶化超过 `10%`
  - `quick-feedback-completion-rate >= 0.80`
  - `median-feedback-latency-seconds <= 8`
  - `capture-policy-violation-count = 0`

**输出物**
- `docs/metrics/preference-learning-metrics.md`
- `scripts/benchmarks/aggregate_preference_metrics.py`
- `data/benchmarks/personal-preference/metrics-v0.json`
- `data/benchmarks/personal-preference/metrics-summary.json`

**验收标准**
- [x] 指标可稳定比较不同版本的偏好学习效果。

本次落地说明：
- 新增 `scripts/benchmarks/aggregate_preference_metrics.py`，可从 `manifest.json + catalog.json + generated/*/case-report.json` 聚合 `preferenceMatchRate / assistAcceptanceRate / repairPathHitRate / teacherOverrideRate / unsafeAutoExecutionRegression / quickFeedbackCompletionRate / medianFeedbackLatencySeconds / capturePolicyViolationCount` 八项 v0 指标。
- 新增 `data/benchmarks/personal-preference/metrics-v0.json`，冻结 baseline、Quick Feedback 支持动作、批准的 benchmark source root 与 v0 gate 配置。
- `run_personal_preference_benchmark.py` 现会为每条 case 记录 `moduleExecutionDurationSeconds`，并在写出 `manifest.json` 后自动生成 `metrics-summary.json`。
- `docs/metrics/preference-learning-metrics.md` 明确了各指标口径；其中 `assistAcceptanceRate` 与 `teacherOverrideRate` 被显式标记为 benchmark proxy，避免与线上真实老师行为遥测混淆。

#### TODO 11.5.3 接入发布门禁

**输出物**
- `scripts/release/run_regression.py`
- `Makefile`

**验收标准**
- [x] `release-preflight` 会执行 personal preference benchmark，并在 benchmark 产出后追加 v0 gate 检查。
- [x] `preferenceMatchRate / repairPathHitRate / quickFeedbackCompletionRate / medianFeedbackLatencySeconds / capturePolicyViolationCount` 等关键指标在发布前统一判定。
- [x] `unsafeAutoExecutionRegression > 0`、`capturePolicyViolationCount > 0`、`teacherOverrideRate` 超过冻结基线允许恶化幅度时直接 fail。

本次落地说明：
- `scripts/release/run_regression.py` 现新增 `benchmark-personal-preference` 与 `benchmark-personal-preference-gates` 两个检查项，前者产出 benchmark 工件，后者通过 `aggregate_preference_metrics.py --check-gates` 把 v0 指标门槛真正接入发布门禁。
- 发布脚本补充了 `--assist-executable / --student-executable / --review-executable / --preference-catalog / --preference-metrics-config` 参数，便于 CI 或本地复用已构建 CLI 并验证临时 gate 配置。
- `Makefile` 新增 `benchmark-preference-gates` 与 `benchmark-preference-preflight`，可在不跑整套 release regression 的情况下单独复现偏好门禁。

---

### 阶段 11.6：安全与治理层（Week 9）

#### 目标

把“会学习”限制在“可审计、可回滚、不会越学越危险”的边界里。

#### TODO 11.6.1 固化偏好治理策略

- 第一版风险级别建议：
  - `low`：允许自动晋升
  - `medium`：允许晋升，但不放开自动执行
  - `high`：必须老师确认
  - `critical`：不自动晋升，只保留 candidate

**输出物**
- `core/learning/PreferencePromotionPolicy.swift`
- `config/preference-governance.yaml`

**验收标准**
- [x] 高风险偏好不会因单次反馈自动生效。

本次落地说明：
- 新增 `config/preference-governance.yaml` 与 `core/learning/PreferencePromotionPolicy.swift`，把 `enabledScopeLevels / conflictPriority / riskPolicies / signalTypePolicies` 收口到统一治理配置；`PreferenceRulePromoter` 与 `PreferenceConflictResolver` 现在都会默认读取该配置，避免阈值、局部 scope 和冲突优先级散落硬编码。
- 四级风险策略已固化为：`low -> inheritSafetyInterlocks`、`medium -> promoted but autoExecutionPolicy=disabled`、`high -> requiresTeacherConfirmation`、`critical -> allowAutomaticPromotion=false`；因此高风险偏好不会因单次反馈直接自动生效。
- signal type 治理已固化为：`style / risk` 允许 `global / app / taskFamily`，不设置过期；`outcome / procedure / locator / repair` 只能按局部 scope 生效，其中 `outcome=45d`、`procedure=90d`、`locator=30d`、`repair=30d` 会自动带上治理过期窗口。
- promoted `PreferenceRule` 现会写入 `governance` 元数据（`autoExecutionPolicy / expiresAfterDays / expiresAt / allowedScopeLevels`），为后续 `11.6.2 audit`、`11.6.3 rollback` 和 `11.6.4 drift monitor` 预留稳定事实源。

#### TODO 11.6.2 落地偏好审计与回滚

状态：已完成（2026-03-19，含单条规则撤销、snapshot rollback 与 dry-run）

- 审计日志至少记录：
  - 哪条规则何时创建
  - 来自哪些 signal / evidence
  - 何时被覆盖或撤销
  - 由谁确认

**输出物**
- `core/storage/PreferenceAuditLogStore.swift`
- `core/learning/PreferenceRollbackService.swift`
- `apps/macos/Sources/OpenStaffPreferenceProfileCLI/OpenStaffPreferenceProfileCLI.swift`

**验收标准**
- [x] 任意已生效规则都能回滚并重建 profile。

本次落地说明：
- 新增 `core/storage/PreferenceAuditLogStore.swift`，把 `ruleCreated / rulePromoted / ruleSuperseded / ruleRevoked / ruleRolledBack / rollbackApplied` 等生命周期事件统一写入 `data/preferences/audit/{date}.jsonl`，每条日志都固定带 `actor`、`source.kind/referenceId/summary`、关联 `ruleId / profileVersion / signalIds`，可按规则或 profile 过滤查看完整链路。
- `PreferenceMemoryStore` 已改为统一依赖 `PreferenceAuditLogStore`；规则创建、信号入库、profile snapshot 持久化、supersede / revoke 都会写入新审计格式，因此不再只有模糊的 `ruleStatusChanged`，而是能明确区分“创建、覆盖、撤销、回滚”等语义动作。
- 新增 `core/learning/PreferenceRollbackService.swift`，把“撤销单条规则”和“回滚到某个 profile snapshot”统一抽象为 `preview -> apply` 两阶段；dry-run 会返回 `impactedRuleIds / missingRuleIds / projectedSnapshot / moduleSummaries`，apply 会真正改写规则状态并重建最新 profile。
- `OpenStaffPreferenceProfileCLI` 已扩展 `--audit`、`--rollback-rule`、`--rollback-profile-version`、`--dry-run` 与 `--persist`，现在可以直接在 CLI 里查看规则完整生命周期、预览回滚影响，或把最新 profile 回滚到历史快照。

#### TODO 11.6.3 落地偏好漂移监控

状态：已完成（2026-03-19，基于 rules + audit + policy assembly decisions 的 v0 监控）

- 第一版先做 3 条简单规则：
  - `30` 天未命中
  - 最近 `10` 次相关任务里 override 比例超过 `50%`
  - 最近 `3` 次明确被老师驳回

**输出物**
- `core/learning/PreferenceDriftMonitor.swift`
- `docs/adr/ADR-0019-preference-drift-monitoring.md`
- `core/learning/preference-drift-monitor-v0.md`
- `apps/macos/Sources/OpenStaffPreferenceProfileCLI/OpenStaffPreferenceProfileCLI.swift`

**验收标准**
- [x] 系统能提醒“这条偏好可能已过时”并给出触发原因。

本次落地说明：
- 新增 `core/learning/PreferenceDriftMonitor.swift`，固定输出 `PreferenceDriftMonitorReport`，并把 drift finding 统一收敛为 `longTimeNoHit / overrideRateElevated / stylePreferenceChanged / teacherRejectedRepeatedly / highRiskBehaviorMismatch` 五类。
- 监控输入第一版只依赖已有文件事实源：`rules / profiles / audit / assembly`；其中 usage-based finding 会复用 `PolicyAssemblyDecisionStore` 的 `appliedRuleIds / suppressedRuleIds`，而老师明确驳回则从 `PreferenceAuditLogStore` 的 lifecycle 与 `teacherAction` 语义中抽取。
- 为避免误报，当仓库中还没有任何 `data/preferences/assembly/**/*.json` 时，监控会自动跳过 stale / override 这类 usage-based finding，只保留 teacher reject / style drift 等 audit-based 提醒。
- `OpenStaffPreferenceProfileCLI` 已扩展 `--drift-monitor` 与 `--drift-profile-version`，现在可以直接对 latest 或指定 snapshot 运行漂移检查，并以 `JSON` 或 summary 形式输出 findings。

#### TODO 11.6.4 落地 learning bundle 导出、校验与恢复

- 第一版 bundle 至少包含：
  - turns
  - evidence
  - signals
  - rules
  - profiles
  - audit
- 导出包必须带：
  - `manifest.json`
  - schema version
  - payload 校验结果
- 恢复前必须支持 dry-run，先展示将恢复哪些对象。

**输出物**
- `scripts/learning/export_learning_bundle.py`
- `scripts/learning/verify_learning_bundle.py`
- `docs/learning-bundle-spec.md`

**验收标准**
- [x] 同一 bundle 可完成导出、校验、恢复三步闭环。
- [x] 恢复后可重新构建 profile 并对齐 rule ids。

本次落地说明：
- 新增 `scripts/learning/learning_bundle_common.py` 统一 bundle 的导出选择、manifest 生成、payload 校验与 restore preview/apply 逻辑，避免 export / verify 两个 CLI 各自维护一套规则。
- `export_learning_bundle.py` 现支持按 `session / task / turn` 过滤导出，并通过闭环扩张自动补齐依赖对象；bundle 固定输出 `manifest.json` 与 `verification.json`，其中 `audit` 支持按命中对象裁切成子集。
- `verify_learning_bundle.py` 现同时承担 verify 与 restore 入口：默认只做校验；指定 `--restore-workspace-root` 时先输出 dry-run 预览；只有显式加 `--apply` 才真正恢复，并默认阻止覆盖已有文件。
- 恢复后的 payload 会落回标准 `data/learning/**` 与 `data/preferences/**` 布局；若 bundle 包含 `latestProfileVersion`，恢复时会同步重建 `data/preferences/profiles/latest.json`。
- 新增 `tests/integration/test_learning_bundle.py`，固定覆盖 `export -> verify -> restore -> OpenStaffPreferenceProfileCLI --rebuild` 闭环，确保恢复后新的 profile snapshot 仍能对齐原始 `ruleId`。

#### TODO 11.6.6 固化 hook / gateway 集成边界

- 第一版至少提供 4 类事件：
  - `learning.turn.created`
  - `learning.signal.extracted`
  - `preference.rule.promoted`
  - `preference.profile.updated`
- 第一版至少提供 3 个 gateway 方法：
  - `preferences.listRules`
  - `preferences.listAssemblyDecisions`
  - `preferences.exportBundle`
- 外部 worker 或插件只能消费这些边界，不直接读内部对象图。

**输出物**
- `core/contracts/LearningIntegrationContracts.swift`
- `core/storage/LearningGateway.swift`
- `docs/integrations/learning-hooks-gateway-v0.md`

**验收标准**
- [x] 外部插件或 worker 可在不依赖内部私有对象的前提下消费学习结果。

本次落地说明：
- 新增 `core/contracts/LearningIntegrationContracts.swift`，统一定义 4 类 hook 事件 envelope、3 个 gateway 方法名，以及 rules / assembly / bundle export 的公开 request/response 契约，外部消费者无需再依赖 `PreferenceRuleQuery`、`PolicyAssemblyDecisionQuery` 等内部查询对象。
- 新增 `core/storage/LearningGateway.swift`，把 `PreferenceMemoryStore`、`PolicyAssemblyDecisionStore` 与 `scripts/learning/export_learning_bundle.py --json` 收敛到 `FileSystemLearningGateway` 后面；`preferences.exportBundle` 现固定复用公开 `PreferencesExportBundleRequest/Response` 边界，不向外泄露脚本参数拼装细节。
- 新增 `OpenStaffAppTests/LearningGatewayTests.swift`，固定验证 `preferences.listRules`、`preferences.listAssemblyDecisions` 与 `preferences.exportBundle` 三条公开路径都可以只通过 contract 层完成消费与结果映射。
- 新增 `docs/integrations/learning-hooks-gateway-v0.md`，明确 hook 何时发、gateway 何时查、外部插件允许依赖哪些公开契约，以及禁止直接读取哪些内部对象 / 存储路径。

---

## 8. 本阶段明确不做的事情

为保持路线清晰，本阶段暂不优先：

- 在线 GPU 训练或实时权重更新。
- 引入 Megatron / slime / Ray 等训练基础设施。
- 引入 teacher log-prob、token-level advantage 或 Tinker 训练链路。
- 在真实桌面环境中做无门控的强化学习探索。
- 用模型自更新替代现有 safety gate、preflight、replay verify。
- 将 ClawStaff 变成通用云端训练平台。

后续如要进入参数级适配，应作为下一阶段单独立项，且只考虑：

- 小规模 LoRA
- 离线验证
- 可回滚适配层
- 不影响主执行链路的异步部署

---

## 9. 九周里程碑视图

### Week 1

- 菜单栏 / 悬浮 learning 状态上线。
- quick feedback bar 和隐私排除规则跑通。

### Week 2

- `InteractionTurn` / `NextStateEvidence` schema 定稿。
- 20 条历史任务回填成功。
- 主线 / 非主线分类规则可输出 `reasonCode`。

### Week 3

- `PreferenceSignal` schema 定稿。
- 规则优先 extractor 能从 30 条真实审阅样本里提取基础信号。

### Week 4

- LLM hint extractor 接上 3-vote 流程。
- 形成第一版 `signals.json` 样本集和人工复核队列。

### Week 5

- `PreferenceMemoryStore` 落盘。
- 默认晋升阈值、冲突策略和 profile builder 可运行。

### Week 6

- assist 完成偏好重排并输出 assembly log。
- skill mapper 接入偏好规则摘要。

### Week 7

- repair planner、review suggestion 接入偏好装配。
- student planner 仅完成 feature flag 接线，不默认开启。

### Week 8

- `Personal Preference Benchmark` 24 条 case 跑通。
- 输出 baseline 指标报告。

### Week 9

- 治理、回滚、漂移监控跑通。
- learning bundle 导出 / 恢复和 hook / gateway 边界跑通。
- preference benchmark 接入 `release-preflight`。

---

## 10. 阶段完成标志（Definition of Done）

当满足以下条件时，可认为 Phase 11 第一阶段完成：

1. 至少 `20` 条历史任务和 `10` 条新增任务能落成 `InteractionTurn + NextStateEvidence + PreferenceSignal` 闭环。
2. 老师侧 learning 状态、暂停 / 排除和 quick feedback 已上线，且 `quick-feedback-completion-rate >= 0.80`。
3. 规则优先 + LLM 辅助两条提炼链都能运行，且自由文本备注结构化成功率不低于 `80%`。
4. 已产生可查询的 `PreferenceRule`、`PreferenceProfile` 和 `PolicyAssemblyDecision` 工件。
5. assist、skill mapper、repair planner、review suggestion 至少 `3` 个模块已接入偏好装配。
6. `Personal Preference Benchmark` 可稳定运行，且满足：
   - `preference-match-rate >= 0.70`
   - `repair-path-hit-rate >= 0.60`
   - `unsafe-auto-execution-regression = 0`
   - `capture-policy-violation-count = 0`
7. student planner 仍处于 feature flag 后，未因为 Phase 11 默认放开自动执行。
8. 高风险偏好具备门禁、审计、回滚和漂移提醒。
9. learning bundle 与 hook / gateway 边界已可被外部恢复流程或插件消费。

---

## 11. 一句话结论

ClawStaff 下一阶段最重要的升级，不是“训练一个更强的模型”，而是先补齐这条链：

**把一次主线任务的执行、审阅、修复和老师偏好，整理成可落盘、可提炼、可回写、可评测的反馈闭环。**
