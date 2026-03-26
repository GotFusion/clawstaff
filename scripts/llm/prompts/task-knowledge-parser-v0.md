请把下面的 `KnowledgeItem` 转换为结构化执行计划 JSON。

要求：
1. 严格遵循 system prompt 规则。
2. 只输出 JSON 对象。
3. JSON 键名和字符串定界符只能使用标准 ASCII 双引号 `"`，不能使用 `“ ”`。
4. 必须通过后附的 JSON Schema 约束。

## 输入 KnowledgeItem

{{KNOWLEDGE_ITEM_JSON}}

## 输出 JSON Schema

{{OUTPUT_SCHEMA_JSON}}

现在开始转换，并且仅输出 JSON。
