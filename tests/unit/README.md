# tests/unit/

单元测试（TODO 6.2）。

## 当前覆盖
- `test_validate_knowledge_parse_output.py`
  - LLM 输出 schema 严格校验。
  - JSON 抽取能力（含 fenced code block）。
  - 与 KnowledgeItem 一致性校验。
- `test_openclaw_skill_mapper.py`
  - skill 名规范化。
  - LLM 输出异常诊断。
  - 映射 fallback 规则。
  - KnowledgeItem 基础字段校验。
- `test_validate_openclaw_skill.py`
  - SKILL.md frontmatter/body 结构校验。
  - 映射 JSON 与 frontmatter 一致性校验。
  - frontmatter 解析异常分支校验。
