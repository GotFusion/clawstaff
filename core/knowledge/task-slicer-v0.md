# Task Slicer v0（TODO 2.1）

## 1. 目标

将同一 `sessionId` 下的 `RawEvent` 序列切分为多个 `TaskChunk`。

切分规则聚焦两个边界信号：
- 空闲间隔（idle gap）
- 上下文切换（app/window）

## 2. 输入与输出

### 输入
- `RawEvent[]`（同一 `sessionId`）

### 输出
- `TaskChunk[]`
- 每个 `TaskChunk` 生成唯一 `taskId`

## 3. 切分规则（rule-v0）

设 `event[i-1]` 与 `event[i]`：

1. **空闲切分**
- 当 `deltaSeconds(event[i-1].timestamp, event[i].timestamp) > idleGapSeconds` 时，切分。

2. **上下文切分**（默认开启）
- 当 `appBundleId` 变化时，切分。
- 当 `windowId` 变化时，切分。
- 若 `windowId` 缺失，则以 `windowTitle` 变化作为补充判断。

3. **会话结束切分**
- 最后一段以 `sessionEnd` 作为 `boundaryReason` 结束。

## 4. taskId 生成规则

- 模式：`task-{sessionId}-{NNN}`
- `NNN` 从 `001` 递增。
- 同一 session、同一输入顺序下，taskId 稳定可重现。

## 5. TaskChunk 字段（v0）

见 `core/contracts/KnowledgeTaskContracts.swift`：
- `schemaVersion`: `knowledge.task-chunk.v0`
- `taskId`
- `sessionId`
- `startTimestamp` / `endTimestamp`
- `eventIds` / `eventCount`
- `primaryContext`
- `boundaryReason`（`idleGap` / `contextSwitch` / `sessionEnd`）
- `slicerVersion`: `rule-v0`

## 6. 输出落地约定

- 输出目录：`data/knowledge/{yyyy-mm-dd}/`
- 输出文件：`{taskId}.json`
