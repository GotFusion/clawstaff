# core/knowledge/

负责将采集到的操作事件转换为“可学习知识”。

## 当前实现（Phase 2.1）
- 已定义任务切片结构：`TaskChunk`（见 `core/contracts/KnowledgeTaskContracts.swift`）。
- 已定义切片规则文档：`core/knowledge/task-slicer-v0.md`。
- 已提供 CLI：`OpenStaffTaskSlicerCLI`（读取 session raw-events，输出 task chunk 文件）。

## 后续实现
- 定义 `KnowledgeItem` schema（TODO 2.2）。
- 任务摘要规则生成（TODO 2.3）。
- 输出可供 LLM 解析的结构化提示上下文。
- 转换为 OpenClaw skills 所需中间格式。
