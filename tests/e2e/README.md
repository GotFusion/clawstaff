# tests/e2e/

E2E 测试（TODO 6.2）。

## 当前覆盖
- `test_three_mode_minimal_demo.py`
  - 教学模式：验证知识与 LLM 结构化输出可通过严格校验。
  - 辅助模式：验证执行计划可从知识/LLM 信息归一化得到建议动作集。
  - 学生模式：验证生成的技能文档与映射 JSON 可通过完整结构校验。
- `test_three_mode_cli_roundtrip.py`
  - 调用 `OpenStaffOrchestratorCLI` 验证教学 -> 辅助切换守卫。
  - 调用 `OpenStaffAssistCLI` 验证预测 -> 确认 -> 执行 -> 日志闭环。
  - 调用 `OpenStaffStudentCLI` 验证规划 -> 执行 -> 审阅报告闭环。
