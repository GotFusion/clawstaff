# scripts/

脚本与自动化工具目录。

## 子目录职责
- `learning/`：学习层离线回填与资产迁移脚本，包括 `InteractionTurn` / `NextStateEvidence` 生成、`SEM-101/102` raw-event action builder 与 selector extractor、`semantic_actions` SQLite 回填，以及 learning bundle 的导出、校验、恢复。
- `llm/`：与 ChatGPT 接口交互、提示词模板、解析流程（已落地 Phase 3.1 模板系统 + Phase 3.2 调用适配层）。
- `skills/`：将知识文件 + LLM 结构化输出转换为 OpenClaw skills（已落地 Phase 3.3 映射器与校验器）。
- `release/`：发布前检查工具（Phase 6.3，演示数据打包 + 回归脚本 + 报告输出）。
