# core/storage/

负责知识数据、日志与索引管理。

## 当前实现（Phase 4.2）
- `AssistLoopLogWriter.swift`：辅助模式闭环日志回写（JSONL）：
  - 路径：`data/logs/{yyyy-mm-dd}/{sessionId}-assist.log`
  - 按步骤追加写入（预测、确认、执行）。
  - 日志字段满足 `timestamp/traceId/sessionId/taskId/component/status/errorCode` 基线。

## 后续实现
- 知识文件存储结构与版本管理。
- 学习记录、执行日志、审阅记录统一索引。
- 搜索索引（按应用、任务、时间、模式检索）。
- 导入导出与备份恢复策略。
