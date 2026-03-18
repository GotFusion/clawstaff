# PreferenceSignal v0

## 目标

`PreferenceSignal` 是从 `NextStateEvidence` 提炼出的结构化偏好对象，用来把：

1. 这一步到底是被鼓励、被否定，还是保持中性。
2. 如果需要纠偏，系统下一次应该怎么改。

`v0` 先只固化 `evaluative + directive` 双通路，不引入复杂 reward 或在线学习权重。

## 核心字段

- `signalId / turnId / traceId / sessionId / taskId / stepId`
- `type`：`outcome / procedure / locator / style / risk / repair`
- `evaluativeDecision`：`pass / fail / neutral`
- `polarity`：`reinforce / discourage / neutral`
- `scope`：作用域对象，至少包含 `level`
- `confidence`
- `evidenceIds[]`：回链提炼来源 evidence
- `promotionStatus`：`candidate / confirmed / rejected / superseded`
- `timestamp`：信号提炼时间

## Directive payload 约定

`scope` 永远存在，因为每条 signal 都必须声明它影响哪一层偏好。

当 next-state 真的提供 hindsight 时，signal 还会带 directive payload：

- `hint`
- `proposedAction`

`v0` 约定：

- `hint` 只写 1-3 句、可执行、面向行为纠偏。
- `proposedAction` 先保留为字符串动作名，供后续 assist rerank、skill mapper、repair planner、review suggestion 消费。
- 如果没有明确 hindsight，只保留 evaluative 面，不强行生成空 hint。

## Scope 策略

支持 5 种 scope level：

- `global`
- `app`
- `taskFamily`
- `skillFamily`
- `windowPattern`

其中 `v0` 默认优先生效的只有：

- `global`
- `app`
- `taskFamily`

`skillFamily / windowPattern` 先作为扩展位落盘保留，避免 schema 未来再破坏性升级。

## 推荐提炼映射

- `outcome`：老师通过、benchmark 成功、runtime 成功
- `procedure`：顺序不对、步骤跳跃、应先检查再执行
- `locator`：定位失败、坐标回退过多、标题变化
- `style`：表达方式不对、回答太长、语气不合适
- `risk`：太危险、必须确认、禁止自动执行
- `repair`：优先修 locator、优先重放、优先重示教

## 落盘约定

- 单 turn 信号文件：`data/preferences/signals/{date}/{sessionId}/{turnId}.json`
- 一个 turn 可以写多条 signal
- 第一版仍以文件为事实源，后续存储层只做索引与查询加速

## v0 说明

- `evaluativeDecision` 先只允许离散值：`pass / fail / neutral`
- 不在 `PreferenceSignal` 内复制 evidence 正文，只保留 `evidenceIds`
- 是否默认生效由 `scope.level` 推导，不额外写冗余布尔字段
