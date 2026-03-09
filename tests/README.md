# tests/

测试组织目录。

## 子目录职责
- `unit/`：核心能力单元测试（schema 校验、skill 映射器规则、skill 产物校验器）。
- `integration/`：组件协作测试（KnowledgeItem -> LLM 输出 -> skill 生成 -> skill 校验；Session raw events -> TaskChunk 切片）。
- `e2e/`：三模式最小演示用例（契约闭环 + 真实 CLI 闭环）。

## 运行方式

```bash
make test
make test-unit
make test-integration
make test-e2e
```

或直接执行：

```bash
python3 scripts/tests/run_all.py --suite all
```

输出会包含每个测试分组的通过/失败摘要。
