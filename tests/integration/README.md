# tests/integration/

集成测试（TODO 6.2）。

## 当前覆盖
- `test_skill_pipeline.py`
  - 端到端调用 `openclaw_skill_mapper.py` 与 `validate_openclaw_skill.py`。
  - 验证正常 LLM 输出链路可生成并校验 skill。
  - 验证无效 LLM 输出触发 fallback 后链路仍可生成并校验 skill。
