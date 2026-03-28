# config/

配置模板与环境说明（Phase 6.3 发布前检查）。

## 文件说明
- `default.yaml`：默认配置基线（本地开发与最小运行默认值）。
- `dev.yaml`：开发环境覆盖（高日志等级等）。
- `release.example.yaml`：发布配置模板（含存储、安全、LLM、OpenClaw 参数模板）。
- `safety-rules.yaml`：统一安全策略（敏感窗口识别、自动执行阻断、App / task / skill 白名单）。
  - 当前采用 JSON-compatible YAML 书写，方便 Swift / Python 在无额外依赖下直接读取。
- `semantic-action-observability.v0.json`：`SEM-303` 语义执行观测 gate 配置，冻结环境列表与 `selectorHitRate / replaySuccessRate / manualConfirmationRate / misTriggerRiskEventCount` 阈值。
- `learning-privacy.example.yaml`：老师侧 learning 隐私 / 排除规则模板。
  - 桌面 App 默认将运行时修改写入 `data/runtime/learning-privacy.json`。
  - 若存在 `config/learning-privacy.yaml`，App 会优先读写该文件。
- 根目录 `.env.example`：环境变量模板（复制为 `.env.local` 后填写密钥或路径）。

## 推荐使用方式
1. 以 `default.yaml` 作为基础。
2. 在开发阶段叠加 `dev.yaml`。
3. 发布场景从 `release.example.yaml` 拷贝为本地配置并填充真实值。
4. 所有敏感信息通过 `.env.local` 注入，不写入仓库。
5. 调整自动执行风控时，优先修改 `safety-rules.yaml`，再决定是否同步更新 `default.yaml/release.example.yaml` 的说明性字段。
6. 若需要给老师预置 learning 隐私规则，可从 `learning-privacy.example.yaml` 复制出 `config/learning-privacy.yaml`。
7. 若需要调整 `SEM-303` 告警门槛，可直接修改 `semantic-action-observability.v0.json`，再通过 `make semantic-observability-gates` 验证。

## 发布前最小检查
1. `OPENAI_API_KEY`、`OPENCLAW_CLI_PATH` 已在 `.env.local` 设置。
2. `storage.root` 指向可写目录。
3. `openclaw.skillsPendingDir`、`openclaw.skillsDoneDir` 可写且隔离。
4. `config/safety-rules.yaml` 已按实际风控要求补充敏感窗口与白名单。
