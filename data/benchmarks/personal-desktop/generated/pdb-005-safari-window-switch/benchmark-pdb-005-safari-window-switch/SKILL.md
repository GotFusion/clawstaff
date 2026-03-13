---
name: benchmark-pdb-005-safari-window-switch
description: 在 Safari浏览器 中复现任务 task-session-gui-4214a172-teaching-20260310-142748-002 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-005-safari-window-switch","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-4214a172-teaching-20260310-142748-002","taskId":"task-session-gui-4214a172-teaching-20260310-142748-002","sessionId":"session-gui-4214a172-teaching-20260310-142748","repairVersion":0}}
---

# 在 Safari浏览器 中复现任务 task-session-gui-4214a172-teaching-20260310-142748-002 的操作流程

## Context
- appName: `Safari浏览器`
- appBundleId: `com.apple.Safari`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-4214a172-teaching-20260310-142748`
- taskId: `task-session-gui-4214a172-teaching-20260310-142748-002`
- knowledgeItemId: `ki-task-session-gui-4214a172-teaching-20260310-142748-002`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `2`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Safari浏览器（未知窗口）中，步骤摘要：点击 -> 点击。共 2 步，任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（源事件 ceee3db7-9bcb-40bf-890c-5c042f557557）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `ceee3db7-9bcb-40bf-890c-5c042f557557`
2. [click] 执行第 2 步点击操作（源事件 967ec859-bf5a-44d3-8ddc-01823ee9f353）。
   - knowledgeStepId: `step-002`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `967ec859-bf5a-44d3-8ddc-01823ee9f353`

## Safety Notes
- 执行前前台应用必须是 com.apple.Safari。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `2`
- requiredFrontmostAppBundleId: `com.apple.Safari`
- confidence: `0.72`
