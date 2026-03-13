---
name: benchmark-pdb-015-safari-focus
description: 在 Safari浏览器 中复现任务 task-session-gui-f03aebb3-teaching-20260310-160325-002 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-015-safari-focus","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-f03aebb3-teaching-20260310-160325-002","taskId":"task-session-gui-f03aebb3-teaching-20260310-160325-002","sessionId":"session-gui-f03aebb3-teaching-20260310-160325","repairVersion":0}}
---

# 在 Safari浏览器 中复现任务 task-session-gui-f03aebb3-teaching-20260310-160325-002 的操作流程

## Context
- appName: `Safari浏览器`
- appBundleId: `com.apple.Safari`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-f03aebb3-teaching-20260310-160325`
- taskId: `task-session-gui-f03aebb3-teaching-20260310-160325-002`
- knowledgeItemId: `ki-task-session-gui-f03aebb3-teaching-20260310-160325-002`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Safari浏览器（未知窗口）中，步骤摘要：点击。共 1 步，任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（源事件 fc1c4088-1a75-4c3f-a019-767c2c203640）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `fc1c4088-1a75-4c3f-a019-767c2c203640`

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
- expectedStepCount: `1`
- requiredFrontmostAppBundleId: `com.apple.Safari`
- confidence: `0.72`
