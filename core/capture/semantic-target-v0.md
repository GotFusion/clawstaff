# Semantic Target v0

本文定义阶段 7.1 的语义定位模型，用于在保留点击坐标的同时，为后续回放、修复和 OpenClaw skill 生成提供更稳定的目标描述。

## 1. 设计目标

- 坐标永远保留，保证最小可回放性。
- 允许同一步骤持有多个 locator 候选，支持解析优先级和后续修复。
- 在当前采集能力有限时，先稳定落 `coordinateFallback`，后续再补 AX、文本锚点和图像锚点。

## 2. 核心对象

`SemanticTarget` 字段：

- `locatorType`：`axPath` / `roleAndTitle` / `textAnchor` / `imageAnchor` / `coordinateFallback`
- `appBundleId`：目标所在应用
- `windowTitlePattern`：窗口标题匹配模式，便于回放时先筛窗口
- `windowSignature`：可选窗口稳定签名，用于避免同名窗口误命中
- `elementRole` / `elementTitle` / `elementIdentifier`：元素级语义属性
- `axPath`：可选 AX 树路径，供 `axPath` locator 使用
- `textAnchor`：可选文本锚点，供 `textAnchor` locator 使用
- `imageAnchor`：可选轻量截图指纹（hash / averageLuma），供 `imageAnchor` locator 使用
- `boundingRect`：候选目标在屏幕坐标系下的矩形范围
- `confidence`：0~1 置信度
- `source`：`capture` / `inferred` / `repaired`

解析优先级遵循：

`axPath -> roleAndTitle -> textAnchor -> imageAnchor -> coordinateFallback`

## 3. 在现有模型中的嵌入

- `NormalizedEvent.target.coordinate`：始终保留原始点击坐标。
- `NormalizedEvent.target.semanticTargets[]`：保留语义目标候选。
- `KnowledgeStep.target.coordinate`：知识步骤中的回放坐标。
- `KnowledgeStep.target.semanticTargets[]`：知识步骤中的 locator 候选列表。
- `preferredLocatorType`：记录当前推荐优先尝试的 locator 类型。

## 4. v0 产出规则

阶段 7.2 ~ 7.3 接入焦点元素与截图上下文后，v0 的新增约定为：

- 若能从 `contextSnapshot.focusedElement` 读取到 `role/title/identifier`，优先生成一个 `roleAndTitle` 候选。
- 若能读取到元素可读文本（`title / description / help`），追加一个 `textAnchor` 候选。
- 若能读取到操作前 `screenshotAnchors.before`，追加一个 `imageAnchor` 候选。
- `axPath` 由解析器和回放验证器支持；当采集链路后续补齐 AX 路径时，可直接写入同一模型。
- 若采集不到焦点元素，继续仅落 `coordinateFallback`。

当前阶段的基础保证仍为：

- 每个点击步骤都生成一个 `coordinateFallback` 候选。
- `appBundleId` 直接来自采集上下文。
- `windowTitlePattern` 使用窗口标题的精确正则转义形式。
- `windowSignature` 若可用则一并落盘，供回放阶段先校验窗口。
- `boundingRect` 使用点击点扩展出的 `1x1` 屏幕矩形。
- `source=capture`
- `confidence=0.24`

这样可以先满足“坐标 + 至少一个语义候选”同时存在，后续再在同一数组中追加更强 locator。

## 5. 兼容与迁移

- 旧 `capture.normalized.v0` 数据可以缺省 `semanticTargets` 与 `preferredLocatorType`。
- 旧 `knowledge.item.v0` 数据可以缺省 `steps[].target`。
- Swift 读模型时会把缺失的 `semanticTargets` 视为 `[]`，缺失的步骤 `target` 视为 `nil`。
- 新写入数据仍保持 `capture.normalized.v0` 与 `knowledge.item.v0`，因为本次变更为向后兼容扩展。
