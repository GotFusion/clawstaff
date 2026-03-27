# 语义动作捕获模型迁移执行 Backlog（废除纯坐标方案）

更新时间：2026-03-27  
状态：进行中（SEM-001 / SEM-002 / SEM-003 / SEM-101 / SEM-102 已完成，其余待执行）

## 1. 目标与原则

### 1.1 目标

将项目从“纯坐标动作回放”迁移为“语义动作捕获与执行”模型，直接废除坐标作为执行主路径，显著降低噪声和误操作风险（例如误点到错误 App、Dock、系统菜单等）。

### 1.2 强制原则（冻结后不可回退）

1. 坐标不可作为执行主依据。
2. 执行动作必须基于语义选择器（元素身份 + 上下文约束）。
3. 回放前置上下文校验失败时，必须中止并请求确认。
4. 坐标仅允许作为诊断日志字段（可选），不允许进入执行链路。

### 1.3 迁移成功门槛（上线门槛）

1. 错误应用误触发率：`0`
2. 语义回放成功率：`>= 95%`
3. 关键路径（切窗、输入、拖动）成功率：`>= 98%`
4. 需人工确认步骤占比：`< 10%`

## 2. 范围定义

### 2.1 In Scope

1. 语义动作 DSL、存储模型、捕获推断器、执行器、断言器。
2. 回放前后强校验（前台 App、窗口标题、URL/域名、元素可用性）。
3. 拖动动作语义化（source/target selectors）。
4. 旧数据迁移策略与灰度切换。
5. 监控、回归集、发布与清理。

### 2.2 Out of Scope（本期不做）

1. 复杂多步策略规划（LLM 自主改写任务）。
2. 跨机器 UI 自动修复（仅保留人工确认机制）。
3. 完整视觉代理自动探索。

## 3. 周级计划与 Issue Backlog

## Week 1（2026-03-30 ~ 2026-04-05）：冻结决策 + 底座建模

### SEM-001 决策冻结与坐标执行禁用开关
状态：已完成（2026-03-26）
- 目标：发布 ADR，落地“坐标执行禁用”总开关。
- 任务：
  - [x] 编写 ADR：语义优先、坐标禁用、失败即停策略。
  - [x] 在执行入口加入 `semantic_only=true` 强制开关。
  - [x] 为旧入口增加显式错误提示（拒绝坐标执行）。
- DoD：
  - [x] 合并后的代码中不存在可直达的坐标执行路径。
  - [x] 单测覆盖：坐标执行请求返回明确错误码和原因。
  - [x] ADR 审核通过并落地到 `docs/adr`。
- 风险：
  - 历史流程临时不可用。
  - 缓解：提供只读转换预览和人工确认回退流程。

### SEM-002 语义动作数据模型与迁移脚本
状态：已完成（2026-03-26）
- 目标：新增 `semantic_actions` 相关表并可写可查。
- 任务：
  - 数据库 migration：
    - [x] `semantic_actions`
    - [x] `action_targets`
    - [x] `action_assertions`
    - [x] `action_execution_logs`
  - [x] 定义字段：`session_id`、`action_type`、`selector_json`、`args_json`、`context_json`、`confidence`、`source_event_ids`。
  - [x] 增加 DAO/Repository 层接口。
  - [x] 新增 `scripts/learning/migrate_semantic_actions.py`，把 `InteractionTurn` 回填到独立 SQLite store。
- DoD：
  - [x] migration 可前后滚动（up/down）。
  - [x] 插入/查询 API 测试通过。
  - [x] 字段支持审计追踪（`source_event_ids`, `source_frame_ids`）。
- 风险：
  - schema 设计过早固化。
  - 缓解：`selector_json/args_json/context_json` 先 JSON 扩展，后续再收敛。
- 落地产物：
  - `scripts/learning/migrations/semantic_actions/0001_semantic_actions.{up,down}.sql`
  - `scripts/learning/semantic_action_store.py`
  - `scripts/learning/migrate_semantic_actions.py`
  - `tests/integration/test_semantic_action_migration.py`

### SEM-003 CI 守门规则（禁止新增坐标执行调用）
状态：已完成（2026-03-27）
- 目标：防止坐标执行逻辑回流。
- 任务：
  - [x] 新增 lint/grep rule：阻止 `execute_click(x,y)` 等入口被调用。
  - [x] PR 模板新增检查项：语义选择器、上下文校验、断言。
- 落地产物：
  - `scripts/validation/guard_coordinate_execution.py`
  - `tests/unit/test_guard_coordinate_execution.py`
  - `.github/workflows/semantic-coordinate-guard.yml`
  - `.github/PULL_REQUEST_TEMPLATE.md`
- DoD：
  - [x] CI 对违规调用直接失败。
  - [x] 规则在 main 分支生效。
- 风险：
  - 误伤合法测试代码。
  - 缓解：允许测试 fixture 白名单目录。

## Week 2（2026-04-06 ~ 2026-04-12）：语义捕获推断器（Builder v1）

### SEM-101 Action Builder v1（click/type/shortcut/switch）
状态：已完成（2026-03-27）
- 目标：从输入事件流构建语义步骤序列。
- 任务：
  - [x] 聚合事件窗口（时间邻近 + 上下文一致）形成动作候选。
  - [x] 规则引擎识别动作类型：
    - [x] `switch_app`
    - [x] `focus_window`
    - [x] `click(target)`
    - [x] `type(target,text)`
    - [x] `shortcut(keys)`
  - [x] 输出置信度和 `source_event_ids`。
- 落地产物：
  - `scripts/learning/semantic_action_builder.py`
  - `scripts/learning/build_semantic_actions.py`
  - `tests/unit/test_semantic_action_builder.py`
  - `tests/integration/test_semantic_action_builder.py`
- DoD：
  - [x] 离线回放日志上 80% 以上步骤可成功语义化。
  - [x] 每个动作都有可解释来源（source_event_ids 非空）。
  - [x] 生成结果可写入 `semantic_actions`。
- 风险：
  - 事件合并过度导致动作丢失。
  - 缓解：保留可调参数并输出冲突诊断日志。

### SEM-102 选择器抽取器 v1（Accessibility 优先）
状态：已完成（2026-03-27）
- 目标：为动作生成稳定 selector。
- 任务：
  - 选择器优先级：
    - [x] `automation_id`
    - [x] `role + name/text`
    - [x] `role + ancestry_path`
    - [x] `bounds_norm`（仅回退匹配）
  - [x] 绑定 `app/window/url` 上下文。
- 落地产物：
  - `scripts/learning/semantic_selector_extractor.py`
  - `scripts/learning/semantic_action_builder.py`
  - `tests/unit/test_semantic_selector_extractor.py`
  - `tests/unit/test_semantic_action_builder.py`
  - `tests/integration/test_semantic_action_builder.py`
- DoD：
  - [x] 生成 selector 可在同会话重复定位成功率 >= 95%。
  - [x] 可输出 fallback selector 链路。
- 风险：
  - UI 文本变化导致 selector 脆弱。
  - 缓解：多特征组合 + fallback 链。

### SEM-103 拖动动作语义化（drag source -> target）
- 目标：废除坐标拖动，改成元素对元素。
- 任务：
  - 识别拖动起点/终点事件簇。
  - 生成 `drag(source_selector, target_selector, intent)`。
  - 支持窗口拖拽与列表重排等常见场景。
- DoD：
  - 拖动场景基准集成功率 >= 90%（v1）。
  - 无任何 `drag(x1,y1,x2,y2)` 执行落地。
- 风险：
  - source/target 错配。
  - 缓解：加入拖动后状态断言（位置变化/层级变化）。

## Week 3（2026-04-13 ~ 2026-04-19）：语义执行器与强校验

### SEM-201 Semantic Executor v1
- 目标：实现语义动作执行器（替换坐标执行器）。
- 任务：
  - 执行动作：`switch_app`, `focus_window`, `click`, `type`, `shortcut`, `drag`。
  - 选择器解析与优先级 fallback。
  - 执行日志统一写入 `action_execution_logs`。
- DoD：
  - 执行链路不读取坐标字段作为决策输入。
  - 关键动作单测和集成测试通过。
  - 执行日志含选择器命中路径和耗时。
- 风险：
  - fallback 过度导致误点。
  - 缓解：fallback 到最低级时必须二次确认。

### SEM-202 Context Guard（前置校验）
- 目标：执行前强校验上下文，不匹配即停。
- 任务：
  - 校验维度：
    - `requiredFrontmostApp`
    - `windowTitlePattern`
    - `urlHost`（浏览器场景）
  - 校验失败策略：`stopAndAskTeacher`。
- DoD：
  - 错误 app 场景全部被拦截（回归集 100%）。
  - 失败返回包含结构化原因。
- 风险：
  - 校验过严导致可执行率下降。
  - 缓解：支持“可放宽规则”但默认严格。

### SEM-203 Post-Assertion Engine（后置断言）
- 目标：执行后验证动作是否真的成功。
- 任务：
  - 断言类型：
    - 焦点变化
    - 元素值变化
    - 页面/窗口状态变化
  - 失败时自动停止并上报。
- DoD：
  - 每个动作至少 1 条默认断言。
  - 断言失败能触发中止并给出可读原因。
- 风险：
  - 断言成本增加延迟。
  - 缓解：分级断言（必需/可选）与超时策略。

## Week 4（2026-04-20 ~ 2026-04-26）：兼容迁移与灰度

### SEM-301 历史任务转换器（Coordinate -> Semantic）
- 目标：将可转换旧任务迁移到语义格式。
- 任务：
  - 建立转换规则：基于历史帧和事件还原 selector。
  - 无法可靠转换的步骤标记 `manual_review_required=true`。
- DoD：
  - 历史样本任务转换率 >= 70%（自动）。
  - 不可转换步骤都有明确原因码。
- 风险：
  - 旧数据缺上下文。
  - 缓解：只自动转高置信度步骤，低置信度转人工。

### SEM-302 审核工作流（Teacher Confirmation）
- 目标：将人工确认内建到低置信度路径。
- 任务：
  - 置信度阈值与策略配置。
  - UI 显示候选 selector、上下文、断言。
- DoD：
  - 低置信度动作全部进入审核，不直接执行。
  - 审核结果可回写并参与后续学习。
- 风险：
  - 审核负担上升。
  - 缓解：只拦截高风险动作（跨 app、drag、批量输入）。

### SEM-303 可观测性与指标看板
- 目标：建立迁移期实时质量追踪。
- 任务：
  - 指标：
    - selector 命中率
    - fallback 层级分布
    - 拦截率
    - 回放成功率
    - 人工确认率
  - Dashboard 与告警阈值。
- DoD：
  - 指标按环境分维度可视化（dev/staging/prod）。
  - 出现“误触发风险”时自动告警。
- 风险：
  - 指标口径不一致。
  - 缓解：统一埋点事件与字段规范。

## Week 5（2026-04-27 ~ 2026-05-03）：稳定性与回归硬化

### SEM-401 端到端基准集与回归套件
- 目标：覆盖核心高风险交互场景。
- 任务：
  - 场景集：
    - 切换 app/window
    - 文本输入和快捷键
    - 拖动（窗口、列表）
    - 多显示器
    - 浏览器 URL 场景
  - 建立 nightly 回归。
- DoD：
  - 关键场景自动化回归全部接入 CI。
  - 失败可复现并带结构化上下文。
- 风险：
  - 测试环境抖动造成误报。
  - 缓解：基准环境固定 + flake 重跑策略。

### SEM-402 性能与鲁棒性优化
- 目标：控制迁移后时延与资源占用。
- 任务：
  - 优化 selector 解析和断言耗时。
  - 优化高频事件聚合窗口，减少噪声触发。
  - 异常恢复和超时策略。
- DoD：
  - P95 动作执行时延满足设定阈值（由平台定义）。
  - 长会话稳定运行通过压测。
- 风险：
  - 优化影响正确性。
  - 缓解：性能优化必须通过一致性回归。

## Week 6（2026-05-04 ~ 2026-05-10）：切流与清理发布

### SEM-501 正式切流（Semantic-Only）
- 目标：全量启用语义执行，关闭旧路径。
- 任务：
  - staging 全量灰度 -> prod 全量。
  - 发布开关固定为 `semantic_only=true`。
  - 建立回滚预案（仅回滚版本，不恢复坐标执行）。
- DoD：
  - 生产环境无坐标执行调用。
  - 全量后一周核心指标稳定。
- 风险：
  - 线上长尾场景失败率上升。
  - 缓解：灰度分批 + 人工确认兜底。

### SEM-502 技术债清理与文档收口
- 目标：完成坐标方案残留清理。
- 任务：
  - 删除坐标执行代码、配置、文档、无效测试。
  - 更新用户手册和开发文档。
  - 发布迁移复盘。
- DoD：
  - 代码库中无可执行坐标路径。
  - 文档与实现一致，审计通过。
- 风险：
  - 清理时误删通用组件。
  - 缓解：按模块分批清理并逐步回归。

## 4. 全局风险清单（Risk Register）

| ID | 风险描述 | 概率 | 影响 | 触发信号 | 缓解措施 | Owner |
|---|---|---|---|---|---|---|
| R-01 | 语义选择器不稳定导致命中失败 | 中 | 高 | fallback 频繁升高 | 多特征 selector + fallback 链 + 断言 | Capture |
| R-02 | 误命中错误 App/窗口 | 低 | 严重 | 执行前上下文不一致 | 强制 Context Guard，失败即停 | Executor |
| R-03 | 拖动语义化准确率不足 | 中 | 高 | drag 失败率偏高 | source/target 双断言 + 人工确认 | Capture |
| R-04 | 历史任务转换率低 | 中 | 中 | manual_review 占比高 | 高置信度自动迁移，低置信度人工 | Migration |
| R-05 | 性能回退（高延迟） | 中 | 中 | P95 延迟超过阈值 | 热路径优化、缓存、并发控制 | Platform |
| R-06 | 规则过严导致可执行率下降 | 中 | 中 | 拦截率异常升高 | 引入策略分级与白名单审批 | Product/Eng |
| R-07 | 测试环境不稳定造成误判 | 中 | 中 | 回归波动大 | 固定环境 + flake 重跑 | QA |
| R-08 | 团队并行改动引入回归 | 中 | 高 | 主干冲突增多 | CI 守门 + feature flag + 小步合并 | Tech Lead |
| R-09 | 指标口径不统一导致误决策 | 中 | 中 | Dashboard 数据冲突 | 统一埋点协议与指标定义 | Observability |
| R-10 | 清理阶段残留坐标暗路径 | 低 | 高 | 静态扫描发现调用 | CI 禁用规则 + 发布前审计清单 | Release |

## 5. 执行节奏与治理机制

1. 每周一：计划评审（本周 issue owner + 依赖确认）。
2. 每周三：中期检查（指标、风险、阻塞）。
3. 每周五：验收与复盘（按 DoD 打勾，不达标不关单）。
4. 任一严重风险触发（R-02/R-10）时：立即冻结发布并进入专项修复。

## 6. 交付物清单

1. 代码：语义捕获、语义执行、断言引擎、迁移工具、监控埋点。
2. 数据：新表 migration、历史转换结果、审计日志。
3. 测试：单测、集成、E2E、回归基准集。
4. 文档：ADR、开发文档、用户文档、迁移复盘。

## 7. 关闭条件（Project Exit Criteria）

1. 连续 2 个发布周期满足门槛指标。
2. 坐标执行代码与开关已物理移除。
3. 风险清单高风险项均关闭或降级。
4. 文档、实现、测试三者一致且可审计。
