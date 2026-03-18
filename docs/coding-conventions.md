# OpenStaff 编码与命名规范（Phase 0）

## 1. 目标

本规范用于约束 Phase 0 之后的新代码与新模块，避免跨目录引用混乱和数据文件命名失控。

## 2. 目录契约

### 2.1 共享契约位置

- 统一位置：`core/contracts/`
- 适用范围：所有跨模块数据结构、错误码、状态码、跨层传输对象。
- 规则：凡是跨模块传递的数据，必须先在 `core/contracts/` 定义，再被 `core/*` 和 `modules/*` 引用。

### 2.2 目录职责不交叉

- `core/*`：基础能力，禁止依赖 `modules/*`。
- `modules/*`：模式编排与业务流程，可依赖 `core/*`。
- `scripts/*`：离线或半离线工具链，不承载长期常驻核心服务。

## 3. 文件命名规范

### 3.1 代码文件

- Swift 类型文件：`PascalCase.swift`，文件名与主类型同名。
- 工具类/扩展文件：`TypeName+Feature.swift`。
- Markdown 文档：`kebab-case.md`。

### 3.2 数据文件

- 根目录：`data/`
- 原始事件：`data/raw-events/{yyyy-mm-dd}/{sessionId}.jsonl`
- 任务切片：`data/task-chunks/{yyyy-mm-dd}/{taskId}.json`
- 知识条目：`data/knowledge/{yyyy-mm-dd}/{taskId}.json`
- 执行日志：`data/logs/{yyyy-mm-dd}/{sessionId}-{component}.log`
- 学生审阅报告：`data/reports/{yyyy-mm-dd}/{sessionId}-{taskId}-student-review.json`
- 老师反馈：`data/feedback/{yyyy-mm-dd}/{sessionId}-{taskId}-teacher-feedback.jsonl`
- 学习回合：`data/learning/turns/{yyyy-mm-dd}/{sessionId}/{turnId}.json`
- 学习证据：`data/learning/evidence/{yyyy-mm-dd}/{sessionId}/{turnId}.jsonl`

说明：
- `sessionId`、`taskId` 使用小写字母+数字+短横线（UUID 推荐）。
- 日期一律使用本地时区对应的 `yyyy-mm-dd`。

### 3.3 配置文件

- 通用配置：`config/default.yaml`
- 环境覆盖：`config/{env}.yaml`（如 `dev`/`staging`/`prod`）
- 本机私有环境变量：`.env.local`（不提交敏感值）
- 配置模板：`.env.example`

### 3.4 learning 目录约定

- `core/learning/` 只存学习层对象、builder、提炼器与治理逻辑，不再把学习工件散落到 `core/storage` / `core/orchestrator`。
- `core/learning/schemas/` 放学习层 JSON Schema。
- `core/learning/examples/` 放最小可读样例。
- `core/learning/fixtures/` 放脚本或测试直接消费的固定样本。
- `InteractionTurn`、`NextStateEvidence`、`PreferenceSignal` 这类跨模块对象本体仍定义在 `core/contracts/`，`core/learning/` 负责它们的构建与落盘。

## 4. JSON 字段命名

- 统一使用 `camelCase`。
- 时间字段统一命名 `timestamp`，值为 ISO-8601（例如 `2026-03-07T10:32:11+08:00`）。
- schema 版本字段固定为 `schemaVersion`。

## 5. 错误码规范

### 5.1 格式

错误码格式：`<DOMAIN>-<CATEGORY>-<DETAIL>`（全大写，中划线分隔）

示例：
- `CAP-PERMISSION-DENIED`
- `KNO-SCHEMA-INVALID`
- `EXE-ACTION-BLOCKED`

### 5.2 Domain 约定

- `CAP`：capture
- `KNO`：knowledge
- `ORC`：orchestrator
- `EXE`：executor
- `STO`：storage
- `SKL`：skill mapping
- `SYS`：system/common

### 5.3 Category 约定

- `PERMISSION` / `VALIDATION` / `SCHEMA` / `IO` / `TIMEOUT` / `STATE` / `SAFETY`

## 6. 状态码规范

状态码使用枚举常量命名：`STATUS_<DOMAIN>_<STATE>`（全大写，下划线分隔）

示例：
- `STATUS_CAP_RUNNING`
- `STATUS_CAP_STOPPED`
- `STATUS_ORC_WAITING_CONFIRMATION`
- `STATUS_EXE_COMPLETED`
- `STATUS_EXE_FAILED`

## 7. 日志字段规范

每条结构化日志至少包含：
- `timestamp`
- `traceId`
- `sessionId`
- `taskId`（如果已生成任务）
- `component`
- `status`
- `errorCode`（失败时必填）

## 8. 提交与评审要求

- 新增模块前先确认是否已有 `core/contracts` 契约可复用。
- 跨模块新增字段时必须同步更新契约与文档。
- 不允许在业务代码内硬编码错误码字符串，需走统一定义。
