# modules/assist/

辅助模式模块。

## 当前实现（Phase 4.2）
- 已实现最小闭环：规则预测下一步 -> 模拟弹窗确认 -> 执行器执行 -> 结构化日志回写。
- 运行入口：`make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"`

## 后续实现
- 下一步预测策略从规则扩展到模型。
- 弹窗从 CLI mock 升级为 GUI 原生对话框。
- 与 OpenClaw 执行器联动真实动作执行。
