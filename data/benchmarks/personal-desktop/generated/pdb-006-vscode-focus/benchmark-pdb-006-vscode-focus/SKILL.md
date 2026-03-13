---
name: benchmark-pdb-006-vscode-focus
description: 在 Code 中复现任务 task-session-gui-4589dbd7-teaching-20260310-143404-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-006-vscode-focus","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-4589dbd7-teaching-20260310-143404-001","taskId":"task-session-gui-4589dbd7-teaching-20260310-143404-001","sessionId":"session-gui-4589dbd7-teaching-20260310-143404","repairVersion":0}}
---

# 在 Code 中复现任务 task-session-gui-4589dbd7-teaching-20260310-143404-001 的操作流程

## Context
- appName: `Code`
- appBundleId: `com.microsoft.VSCode`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-4589dbd7-teaching-20260310-143404`
- taskId: `task-session-gui-4589dbd7-teaching-20260310-143404-001`
- knowledgeItemId: `ki-task-session-gui-4589dbd7-teaching-20260310-143404-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Code（未知窗口）中，步骤摘要：点击。共 1 步，任务分段原因：上下文切换切分。

## Steps
1. [click] 执行第 1 步点击操作（源事件 29374208-eabd-4ac2-8c33-0b5579887a59）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `29374208-eabd-4ac2-8c33-0b5579887a59`

## Safety Notes
- 执行前前台应用必须是 com.microsoft.VSCode。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `1`
- requiredFrontmostAppBundleId: `com.microsoft.VSCode`
- confidence: `0.72`
