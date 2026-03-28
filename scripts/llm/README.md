# scripts/llm/

LLM 解析与调用适配工具目录（Phase 3.1 + Phase 3.2）。

## 已实现（TODO 3.1）
- `prompts/system-knowledge-parser-v0.md`
  - 系统提示词模板，定义角色、字段映射与稳定性规则。
- `prompts/task-knowledge-parser-v0.md`
  - 任务提示词模板，注入 `KnowledgeItem` 与输出 schema。
- `schemas/knowledge-parse-output.schema.json`
  - LLM 输出结构约束（`llm.knowledge-parse.v0`）。
- `render_knowledge_prompts.py`
  - 读取 `KnowledgeItem`，渲染稳定的 system/user prompts。
  - 默认输出 `semantic-first` 视图：保留语义 target/context，省略坐标 provenance 与 boundingRect。
- `validate_knowledge_parse_output.py`
  - 强制 JSON 提取与严格校验（可选与原始 `KnowledgeItem` 做一致性比对）。
- `examples/knowledge-parse-output.sample.json`
  - 结构化输出样例。

## 已实现（TODO 3.2）
- `chatgpt_adapter.py`
  - ChatGPT 调用适配层（provider 抽象、超时、重试、限流、错误报告）。
  - 默认支持离线 `text` provider（无需 API），用于当前开发阶段本地验证。
  - 支持 `openai` provider（`/v1/chat/completions`），待 API 可用时可直接切换。
  - 请求日志仅记录摘要和哈希，不落原始提示词正文。

## 使用方式

### 1) 渲染提示词

```bash
python3 scripts/llm/render_knowledge_prompts.py \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json \
  --out-dir /tmp/openstaff-llm-prompts
```

输出：
- `/tmp/openstaff-llm-prompts/system.prompt.md`
- `/tmp/openstaff-llm-prompts/user.prompt.md`

### 2) 校验 LLM 输出

```bash
python3 scripts/llm/validate_knowledge_parse_output.py \
  --input scripts/llm/examples/knowledge-parse-output.sample.json \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json
```

可选参数：
- `--normalized-output <path>`：输出提取后的规范化 JSON 文件。

### 3) 调用适配层（离线文本模式，推荐）

```bash
python3 scripts/llm/chatgpt_adapter.py \
  --provider text \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json \
  --output /tmp/openstaff-llm-call-output.json
```

### 4) 重试链路演示（离线模拟网络抖动）

```bash
python3 scripts/llm/chatgpt_adapter.py \
  --provider text \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json \
  --simulate-transient-failures 2 \
  --max-retries 3 \
  --output /tmp/openstaff-llm-retry-output.json
```

### 5) OpenAI 模式（待 API 可用后）

```bash
export OPENAI_API_KEY="***"
python3 scripts/llm/chatgpt_adapter.py \
  --provider openai \
  --model gpt-4.1-mini \
  --knowledge-item core/knowledge/examples/knowledge-item.sample.json \
  --output /tmp/openstaff-llm-openai-output.json
```

## 约束说明
- 模型响应必须只包含 JSON 对象。
- 必须匹配 `schemas/knowledge-parse-output.schema.json` 的字段和枚举约束。
- 手动提示词与 `text` provider 默认禁止把 `coordinate:x,y` 当成主目标；若缺少稳定语义锚点，应输出 `unknown`。
- 当传入 `--knowledge-item` 时，会额外检查：
  - ID、上下文、步骤顺序、源事件引用一致性。
  - `objective == KnowledgeItem.goal`。
  - `safetyNotes` 与约束描述顺序一致。
- `chatgpt_adapter.py` 默认写入结构化日志到：
  - `data/logs/{yyyy-mm-dd}/{sessionId}-llm-adapter.log`
  - 每条日志至少包含 `timestamp/traceId/sessionId/taskId/component/status`。
