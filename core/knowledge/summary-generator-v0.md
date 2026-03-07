# Summary Generator v0（TODO 2.3）

## 1. 目标

在不使用 LLM 的前提下，为每个 `KnowledgeItem` 生成老师可读摘要文本。

输出到 `KnowledgeItem.summary`，用于快速审阅任务内容。

## 2. 输入

- `TaskChunk`
- `KnowledgeStep[]`

## 3. 规则（rule-v0）

1. 识别步骤动作关键词（打开/点击/输入/快捷键）。
2. 将动作按顺序串联为链路：`动作1 -> 动作2 -> ...`。
3. 合并上下文信息（`appName`、`windowTitle`）。
4. 补充统计与切分原因（`eventCount`、`boundaryReason`）。

最终模板：

`在{appName}（{windowTitle}）中，步骤摘要：{actionChain}。共 {eventCount} 步，任务分段原因：{boundaryReasonText}。`

## 4. 代码落地

- 生成模块：`apps/macos/Sources/OpenStaffKnowledgeBuilderCLI/KnowledgeSummaryGenerator.swift`
- 写入字段：`core/contracts/KnowledgeItemContracts.swift#summary`
