# ADR-0011 Mainline Vs Side Turns

## Status

Accepted

## Context

Phase 11 需要把 `InteractionTurn` 接到后续的 `NextStateEvidence` 和 `PreferenceSignal` 提炼链路里。

如果所有 turn 都直接进入学习：

- 系统状态播报会被误当成老师偏好
- 日志镜像、review 注释、后台整理会污染主线样本
- assist 预测提示和真实执行结果会混在一起，难以解释为什么学了或没学

因此，学习层必须先回答一个更基础的问题：这条 turn 到底是不是“真正推进老师任务”的主线行为。

## Options

### A. 所有任务片段都学习

优点：

- 实现最简单
- 不容易漏掉潜在信号

缺点：

- 噪声最多
- 审计成本高
- 后续 preference/profile 很快失真

### B. 只有执行成功的 execution turn 才学习

优点：

- 训练样本更干净
- 容易围绕 runtime result 做判断

缺点：

- teaching 主线观察样本会被排掉
- repair 与失败样本无法积累
- assist 的确认式推进不容易纳入

### C. 主线任务推进 + 修复行为学习，其余降噪

优点：

- 保留真正的 task progression、skill execution、repair
- 允许失败样本和老师负反馈继续产生价值
- 对 status/log/background 这类 side turn 有明确出口

缺点：

- 需要一层可解释规则，而不是直接靠 turn kind 盲信

## Decision

采用方案 C。

`TurnLearningEligibility` 作为进入偏好学习前的最后一道显式分类器，固定输出：

- `eligible`
- `ineligible`
- `needs_review`

并且每次分类都必须附带 `reasonCode`。

## Rule Set

### Eligible

- `taskProgression` 且存在真实任务推进证据
  - `reasonCode = mainline_task_progression`
- `skillExecution` 且存在真实任务推进证据
  - `reasonCode = mainline_skill_execution`
- `repair`
  - `reasonCode = mainline_repair`

### Ineligible

- 命中隐私排除
  - `reasonCode = privacy_excluded`
- 样例/夹具 turn
  - `reasonCode = synthetic_fixture`
- 纯状态播报
  - `reasonCode = status_only`
- 纯日志镜像或纯审阅记录
  - `reasonCode = log_only`
- 后台整理、分析、资料汇总等非任务推进片段
  - `reasonCode = background_only`

### Needs Review

- assist 预测已出现，但还没有确认或执行回执
  - `reasonCode = assist_prediction_only`
- 结构化证据不足，无法安全判定
  - `reasonCode = insufficient_task_context`

## Consequences

正向影响：

- 学习样本和 side-turn 噪声之间有了硬边界
- 被排除的 turn 可以解释“为什么不学”
- repair、失败执行、老师负反馈仍可保留在主线学习闭环内

代价：

- 需要维护一套规则与关键词表
- assist 和弱结构化样本仍会有 `needs_review` 队列
- 后续如果要做更细的 LLM classifier，仍要兼容当前 `reasonCode`

## Follow-up

- 当真实 assist 历史样本冻结后，补充对“已建议未确认”和“确认后执行”两类 turn 的回归样本。
- 当 replay/drift/benchmark 产生更多 side-turn 工件时，补充 `status_only / log_only / background_only` 的真实负样本审查。
- 下游 `PreferenceSignal` 提炼默认只消费 `eligible` 的 turn。
