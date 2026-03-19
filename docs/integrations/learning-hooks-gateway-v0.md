# Learning Hooks / Gateway v0

## 目标

为 learning 结果提供一层稳定、可版本化的外部集成边界，让插件、worker 或后续 OpenClaw 侧能力可以：

- 通过 hook 事件订阅新产生的学习结果。
- 通过 gateway 查询当前 rules / assembly decisions。
- 通过 gateway 导出可迁移的 learning bundle。

同时明确禁止外部集成直接依赖内部 store、内部查询对象或 `data/**` 私有目录布局。

---

## 公开代码入口

- 合约：`core/contracts/LearningIntegrationContracts.swift`
- 文件系统网关实现：`core/storage/LearningGateway.swift`

外部消费者允许依赖：

- `LearningIntegrationContracts.swift`
- 该文件中引用到的公开 contract：
  - `InteractionTurnContracts.swift`
  - `PreferenceSignalContracts.swift`
  - `PreferenceRuleContracts.swift`
  - `PreferenceProfileContracts.swift`
  - `PolicyAssemblyDecisionContracts.swift`

外部消费者不应直接依赖：

- `PreferenceMemoryStore`
- `PolicyAssemblyDecisionStore`
- `PreferenceRuleQuery`
- `PolicyAssemblyDecisionQuery`
- `scripts/learning/learning_bundle_common.py`
- `data/learning/**`
- `data/preferences/**`

换句话说，外部看到的是“公开 request / response + hook envelope”，而不是内部对象图或目录树。

---

## Hook 事件

### `learning.turn.created`

- 触发时机：新的 `InteractionTurn` 成功写入并成为可消费学习事实后。
- payload：`LearningTurnCreatedHookPayload`
- 核心内容：`InteractionTurn`

### `learning.signal.extracted`

- 触发时机：`PreferenceSignal` 成功提炼并入库后。
- payload：`LearningSignalExtractedHookPayload`
- 核心内容：`PreferenceSignal`

### `preference.rule.promoted`

- 触发时机：`PreferenceRule` 成功晋升并入库后。
- payload：`PreferenceRulePromotedHookPayload`
- 核心内容：`PreferenceRule`

### `preference.profile.updated`

- 触发时机：新的 `PreferenceProfileSnapshot` 成功生成并写入后。
- payload：`PreferenceProfileUpdatedHookPayload`
- 核心内容：`PreferenceProfileSnapshot`

### envelope 约定

所有 hook 事件统一使用：

- `LearningHookEventMetadata`
- `LearningHookEnvelope<Payload>`

固定元数据字段：

- `eventId`
- `eventName`
- `emittedAt`
- `producer`
- `traceId`
- `sessionId`
- `taskId`

这保证外部消费者既能按事件类型路由，也能把事件回链到老师会话、任务和 trace。

---

## Gateway 方法

### `preferences.listRules`

- request：`PreferencesListRulesRequest`
- response：`PreferencesListRulesResponse`
- 用途：查询当前激活或包含 inactive 的规则子集。
- filter：
  - `appBundleId`
  - `taskFamily`
  - `skillFamily`
  - `includeInactive`
- 返回：
  - `rules`
  - 可选 `latestProfileSnapshot`
  - `generatedAt`

当前实现由 `FileSystemLearningGateway` 转调 `PreferenceMemoryStore.loadRules(...)`。

### `preferences.listAssemblyDecisions`

- request：`PreferencesListAssemblyDecisionsRequest`
- response：`PreferencesListAssemblyDecisionsResponse`
- 用途：查询 assist / student / repair / skill generation 的偏好装配解释结果。
- filter：
  - `date`
  - `targetModule`
  - `sessionId`
  - `taskId`
  - `traceId`
- 返回：
  - `decisions`
  - 可选 `latestProfileSnapshot`
  - `generatedAt`

当前实现由 `FileSystemLearningGateway` 转调 `PolicyAssemblyDecisionStore.loadDecisions(...)`。

### `preferences.exportBundle`

- request：`PreferencesExportBundleRequest`
- response：`PreferencesExportBundleResponse`
- 用途：按公开筛选条件导出当前 learning 资产，供外部迁移、审计或恢复。
- filter：
  - `sessionIds`
  - `taskIds`
  - `turnIds`
- 返回：
  - `bundleId`
  - `bundlePath`
  - `manifestPath`
  - `verificationPath`
  - `counts`
  - `indexes`
  - `passed`
  - `issues`

当前实现由 `FileSystemLearningGateway` 转调 `scripts/learning/export_learning_bundle.py --json`，但脚本参数拼装和 JSON 结果映射都被封装在 gateway 内部。

---

## 边界规则

### 对外保证

- `LearningIntegrationContracts.swift` 中的 schema string、方法名和 event name 视为公开边界。
- gateway response 只能返回 `core/contracts/**` 中定义的 contract，不能返回 store 私有查询对象。
- hook payload 只能携带公开 contract，不能把内部 writer / builder / store 实例透出。

### 对内允许变化

以下内容允许继续演进，只要不破坏公开 request / response：

- `PreferenceMemoryStore` 的索引实现
- `PolicyAssemblyDecisionStore` 的目录布局细节
- bundle 导出脚本的内部实现
- learning 目录中间产物如何组织

---

## 版本策略

- v0 先冻结事件名、方法名和 request / response shape。
- 后续新增字段时优先走“向后兼容的可选字段”。
- 若需要删字段或改变语义，必须升级 schema version，并在 ADR 中记录。

---

## 当前限制

- v0 只定义了 4 个最核心 hook 事件，尚未覆盖 rollback、drift finding、teacher quick feedback 等旁路事件。
- v0 gateway 仍是文件系统实现，不包含网络 transport、RPC 认证或分页游标。
- `preferences.exportBundle` 当前复用 Python 脚本实现，因此运行环境仍要求可执行 `python3`。
