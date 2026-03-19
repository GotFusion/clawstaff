# OpenStaff Assist 偏好重排 v1（Phase 11.4.1）

## 1. 目标

在不改 `AssistKnowledgeRetriever` 基础检索逻辑的前提下，把老师已经沉淀到 `PreferenceProfile.assistPreferences` 的偏好装配到辅助模式预测链路里。

本次只做：

- retrieval 结果之上的 rerank
- 结构化输出命中的 rule ids
- 结构化输出被压低候选的原因

本次不做：

- 独立持久化 assembly log
- 修改 retrieval 信号或候选生成策略

统一 `PolicyAssemblyDecision` 落盘仍由 `TODO 11.4.6` 负责。

## 2. 接入点

- `PreferenceAwareAssistPredictor`
  - 输入：`AssistKnowledgeRetriever.retrieve(input:)` 的结果 + `PreferenceProfile`
  - 输出：`AssistSuggestion`
  - 附加结构：`AssistPreferenceRerankDecision`

- 运行入口：
  - `OpenStaffAssistCLI`
  - `OpenStaffApp` 中的 assist workflow

若当前没有 profile snapshot，则自动回退到原来的 `retrievalV1` 行为。

## 3. v1 重排信号

### 3.1 Step preference

- 面向 `procedure / style` 规则。
- 用 `statement / hint / proposedAction` 与候选 `stepInstruction / targetDescription / goal` 做轻量文本匹配。
- 若规则明确偏好 `shortcut / click / input` 某种动作风格，则优先提升动作类型匹配的候选。

### 3.2 App preference

- 面向 `app` scope 规则。
- 比较当前 app 与候选证据上的 `appBundleId / appName`。
- 命中时增加上下文偏好分。

### 3.3 Risk preference

- 面向 `risk` 规则。
- 先从候选步骤文案估计一个轻量风险分。
- 再按“更稳妥动作优先”的方向对候选做加减权。

## 4. 输出约定

`AssistSuggestion.preferenceDecision` 会附带：

- `profileVersion`
- `appliedRuleIds`
- `summary`
- `candidateExplanations[]`

其中每个 `candidateExplanations[]` 会保留：

- `baseScore / finalScore`
- `ruleHits[]`
- `loweredReasons[]`

这样辅助模式可以直接回答：

- 这次命中了哪些偏好规则？
- 为什么历史 A 被选中而不是历史 B？
- 哪个候选被压低了，原因是什么？

## 5. 验收口径

- 同样历史知识下，不同 `PreferenceProfile` 会改变最终推荐。
- CLI / GUI 使用同一套 rerank 逻辑。
- 无 profile 时仍保持原有 assist retrieval 行为。
