# core/storage/

负责知识数据、日志与索引管理。

## 当前实现（Phase 4.2 ~ 9.3）
- `AssistLoopLogWriter.swift`：辅助模式闭环日志回写（JSONL）：
  - 路径：`data/logs/{yyyy-mm-dd}/{sessionId}-assist.log`
  - 按步骤追加写入（预测、确认、执行）。
  - 日志字段满足 `timestamp/traceId/sessionId/taskId/component/status/errorCode` 基线。
- `StudentLoopLogWriter.swift`：学生模式闭环日志回写（JSONL）：
  - 路径：`data/logs/{yyyy-mm-dd}/{sessionId}-student.log`
  - 按步骤追加写入（规划、执行、报告生成）。
  - Phase 9.3 起额外记录 `skillName/skillDirectoryPath/sourceKnowledgeItemId/sourceStepId`，便于审阅台把日志回链到 skill 与老师原始步骤。
- `StudentReviewReportWriter.swift`：学生模式结构化审阅报告落盘（JSON）：
  - 路径：`data/reports/{yyyy-mm-dd}/{sessionId}-{taskId}-student-review.json`
- `ExecutionReviewStore.swift`：执行审阅索引与三栏对照装配：
  - 读取 `data/logs/*/*.log`、`data/feedback/*/*.jsonl`、`data/reports/*/*.json`、`data/knowledge/**/*.json`、`data/skills/**/openstaff-skill.json`
  - 为 GUI 生成“老师原始步骤 / 当前 skill 步骤 / 本次实际执行结果”对照数据
  - 统一回写老师反馈（通过 / 驳回 / 修复 locator / 重新示教）

## 后续实现
- 知识文件存储结构与版本管理。
- 搜索索引（按应用、任务、时间、模式检索）。
- 导入导出与备份恢复策略。
