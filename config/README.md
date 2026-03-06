# config/

配置与环境说明。

## 当前基线
- `default.yaml`：默认配置（应用模式、存储路径、日志、OpenClaw 集成参数）。
- `dev.yaml`：开发环境覆盖配置。
- 根目录 `.env.example`：本地环境变量模板（复制为 `.env.local` 后填写密钥）。

## 未来实现
- 模式开关、隐私级别与安全策略细化。
- LLM API 配置模板与密钥读取规范。
- OpenClaw 运行参数与能力白名单策略。
