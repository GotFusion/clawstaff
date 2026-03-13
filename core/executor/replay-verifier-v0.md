# Replay Verifier v0

本文定义阶段 7.3 的 dry-run 回放验证器，用于在不执行危险动作的前提下，验证历史知识步骤能否在当前环境中重新定位到目标。

## 1. 目标

- 优先验证语义目标，不直接执行点击或输入。
- 对失败原因做结构化输出，而不是仅返回“点击失败”。
- 支持两种输入来源：
  - 实时前台窗口 AX 快照
  - 离线 `ReplayEnvironmentSnapshot` JSON

## 2. 解析顺序

`SemanticTargetResolver` 固定按以下优先级尝试：

`axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback`

行为约定：

- `axPath`：匹配当前窗口 AX 树中的稳定路径。
- `roleAndTitle`：匹配 `role/title/identifier` 的组合。
- `textAnchor`：匹配元素可读文本；若结构相近但文本不再命中，输出 `textAnchorChanged`。
- `imageAnchor`：优先使用离线 snapshot 中的截图锚点，其次实时抓取当前矩形区域指纹。
- `coordinateFallback`：不会被视为真正成功，只会返回 `degraded` 和 `coordinateFallbackOnly`。

## 3. 验证输出

单步结果 `ReplayStepVerification`：

- `resolved`
- `degraded`
- `failed`
- `skipped`

结构化失败原因：

- `appMismatch`
- `windowMismatch`
- `elementMissing`
- `textAnchorChanged`
- `imageAnchorChanged`
- `captureUnavailable`
- `coordinateFallbackOnly`

## 4. CLI

```bash
make replay-verify ARGS="--knowledge core/knowledge/examples/knowledge-item.sample.json --snapshot core/executor/examples/replay-environment.sample.json --json"
```

退出码：

- `0`：所有已检查步骤均成功解析
- `1`：CLI 或输入错误
- `2`：存在 `failed` 或 `degraded` 步骤
