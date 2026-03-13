---
name: benchmark-pdb-022-xcode-double-step
description: 在 Xcode 中复现任务 task-session-gui-199fd65f-teaching-20260311-173758-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-022-xcode-double-step","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-199fd65f-teaching-20260311-173758-001","taskId":"task-session-gui-199fd65f-teaching-20260311-173758-001","sessionId":"session-gui-199fd65f-teaching-20260311-173758","repairVersion":0}}
---

# 在 Xcode 中复现任务 task-session-gui-199fd65f-teaching-20260311-173758-001 的操作流程

## Context
- appName: `Xcode`
- appBundleId: `com.apple.dt.Xcode`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-199fd65f-teaching-20260311-173758`
- taskId: `task-session-gui-199fd65f-teaching-20260311-173758-001`
- knowledgeItemId: `ki-task-session-gui-199fd65f-teaching-20260311-173758-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `2`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Xcode（未知窗口）中，步骤摘要：点击 -> 点击。共 2 步（原始事件 2 条），任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（x=526, y=46，源事件 11902171-1722-47b6-8740-7c9583a961be）。
   - knowledgeStepId: `step-001`
   - target: `coordinate:526,46`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `11902171-1722-47b6-8740-7c9583a961be`
2. [click] 执行第 2 步点击操作（x=719, y=653，源事件 7ea3acc0-a1a6-4a7c-8c1c-ae3848dcb864）。
   - knowledgeStepId: `step-002`
   - target: `coordinate:719,653`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `7ea3acc0-a1a6-4a7c-8c1c-ae3848dcb864`

## Safety Notes
- 执行前前台应用必须是 com.apple.dt.Xcode。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `2`
- requiredFrontmostAppBundleId: `com.apple.dt.Xcode`
- confidence: `0.72`
