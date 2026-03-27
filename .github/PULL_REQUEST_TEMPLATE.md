## SEM-003 Checklist

- [ ] 本次改动没有新增坐标执行调用；如必须触达冻结遗留入口，已同步更新 `scripts/validation/guard_coordinate_execution.py` 的 allowlist 并说明原因。
- [ ] 自动化步骤优先使用语义选择器，并补充了必要的上下文校验。
- [ ] 已为成功路径或失败路径补充测试 / 断言，覆盖本次行为变化。
