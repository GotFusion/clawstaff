---
name: benchmark-pdb-013-system-settings-navigation
description: 在 系统设置 中复现任务 task-session-gui-b3e503cf-teaching-20260310-164817-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-013-system-settings-navigation","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-b3e503cf-teaching-20260310-164817-001","taskId":"task-session-gui-b3e503cf-teaching-20260310-164817-001","sessionId":"session-gui-b3e503cf-teaching-20260310-164817","repairVersion":0}}
---

# 在 系统设置 中复现任务 task-session-gui-b3e503cf-teaching-20260310-164817-001 的操作流程

## Context
- appName: `系统设置`
- appBundleId: `com.apple.systempreferences`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-b3e503cf-teaching-20260310-164817`
- taskId: `task-session-gui-b3e503cf-teaching-20260310-164817-001`
- knowledgeItemId: `ki-task-session-gui-b3e503cf-teaching-20260310-164817-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `3`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在系统设置（未知窗口）中，步骤摘要：点击 -> 点击 -> 点击。共 3 步，任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（源事件 11345c2b-d203-4241-9c7f-68f9478d6fd4）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `11345c2b-d203-4241-9c7f-68f9478d6fd4`
2. [click] 执行第 2 步点击操作（源事件 a4f2f7db-3ad7-4c8f-ac54-411f7a4f9458）。
   - knowledgeStepId: `step-002`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `a4f2f7db-3ad7-4c8f-ac54-411f7a4f9458`
3. [click] 执行第 3 步点击操作（源事件 b55fe174-53de-43cc-8948-36908b15a761）。
   - knowledgeStepId: `step-003`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `b55fe174-53de-43cc-8948-36908b15a761`

## Safety Notes
- 执行前前台应用必须是 com.apple.systempreferences。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `3`
- requiredFrontmostAppBundleId: `com.apple.systempreferences`
- confidence: `0.72`
