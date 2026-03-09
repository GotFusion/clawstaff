# OpenStaff 用户使用说明书

版本：v0.6.3  
更新时间：2026-03-09

## 1. 产品简介

OpenStaff 是“老师-学生”式个人助理：
- 老师：你（用户）。
- 学生：OpenStaff 软件。

软件通过记录并学习你的桌面操作，沉淀为知识条目，然后在三种模式中协助你：
- 教学模式：观察并学习。
- 辅助模式：预测下一步并经确认后执行。
- 学生模式：根据知识自主执行并输出审阅报告。

## 2. 运行前准备

### 2.1 系统要求
- macOS（建议 14+）。
- Swift toolchain / Xcode Command Line Tools。
- Python 3.10+（用于脚本与测试）。

### 2.2 仓库准备
在项目根目录执行：

```bash
make build
```

### 2.3 环境变量
复制环境变量模板：

```bash
cp .env.example .env.local
```

按需填写：
- `OPENAI_API_KEY`：使用在线 OpenAI provider 时必填。
- `OPENCLAW_CLI_PATH`：OpenClaw 可执行文件路径。

### 2.4 配置文件
- 默认配置：`config/default.yaml`
- 开发覆盖：`config/dev.yaml`
- 演示模板：`config/demo.example.yaml`
- 发布模板：`config/release.example.yaml`

## 3. 三种模式使用方法

### 3.1 教学模式（Learning）
目标：采集你的操作并形成知识。

常用命令：

```bash
make capture ARGS="--max-events 20"
make slice ARGS="--session-id session-20260309-a1 --date 2026-03-09"
make knowledge ARGS="--task-chunk data/task-chunks/2026-03-09/task-session-20260309-a1-001.json"
```

### 3.2 辅助模式（Assist）
目标：学生预测下一步，经你确认后执行。

```bash
make assist ARGS="--knowledge-item core/knowledge/examples/knowledge-item.sample.json --auto-confirm yes"
```

### 3.3 学生模式（Student）
目标：学生根据目标自主执行并生成审阅报告。

```bash
make student ARGS="--goal 在 Safari 中复现点击流程 --knowledge core/knowledge/examples/knowledge-item.sample.json"
```

## 4. LLM 与 Skill 工作流

### 4.1 提示词渲染与校验
```bash
make llm-prompts
make llm-validate
```

### 4.2 调用适配层
```bash
make llm-call
make llm-retry-demo
```

### 4.3 Skill 生成与校验
```bash
make skills-demo
make skills-validate-demo
```

## 5. 一键 Demo 体验（推荐首次使用）

OpenStaff 提供了可直接体验的 Demo 程序 `OpenStaffDemoCLI`。

### 5.1 编译 Demo 程序
```bash
make demo-build
```

### 5.2 运行 Demo 程序
```bash
make demo-run
```

默认会自动执行：
1. 模式切换检查（teaching -> assist）。
2. 辅助模式闭环（预测 -> 确认 -> 执行）。
3. 学生模式闭环（规划 -> 执行 -> 报告）。

### 5.3 Demo 输出位置
默认输出目录：

```text
/tmp/openstaff-demo-experience
```

关键文件：
- `demo-summary.json`：Demo 执行摘要。
- `logs/`：辅助与学生模式日志。
- `reports/`：学生模式审阅报告。
- `step-outputs/*.stdout.log`：每一步原始输出。

### 5.4 自定义 Demo 参数
```bash
make demo-run ARGS="--goal 在 Finder 中执行示例流程 --output-root /tmp/my-openstaff-demo"
```

## 6. 发布前检查

### 6.1 生成演示数据包
```bash
make release-demo
```

### 6.2 执行发布回归
```bash
make release-regression
```

### 6.3 一键执行发布预检
```bash
make release-preflight
```

## 7. 常见问题

### 7.1 提示权限不足
- 采集功能依赖 macOS 辅助功能权限。
- 请在系统设置中授权后重试。

### 7.2 Swift 构建失败
- 检查 `xcode-select -p` 指向有效开发工具链。
- 保证当前用户对项目目录和缓存目录有写权限。

### 7.3 Demo 步骤失败
- 先运行 `make demo-build` 确保必需 CLI 已编译。
- 查看 `step-outputs/*.stderr.log` 定位失败原因。

## 8. 进阶建议

1. 使用真实采集会话替换样例知识条目，观察模型效果变化。  
2. 在 `config/release.example.yaml` 中细化 `safety.blockedActionKeywords`。  
3. 将 `make release-preflight` 接入 CI，作为发布门禁。  
