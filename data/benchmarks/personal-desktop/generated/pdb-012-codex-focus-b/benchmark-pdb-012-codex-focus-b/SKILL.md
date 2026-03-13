---
name: benchmark-pdb-012-codex-focus-b
description: 在 Codex 中复现任务 task-session-gui-b250e7f9-teaching-20260310-155114-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-012-codex-focus-b","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-b250e7f9-teaching-20260310-155114-001","taskId":"task-session-gui-b250e7f9-teaching-20260310-155114-001","sessionId":"session-gui-b250e7f9-teaching-20260310-155114","repairVersion":0}}
---

# 在 Codex 中复现任务 task-session-gui-b250e7f9-teaching-20260310-155114-001 的操作流程

## Context
- appName: `Codex`
- appBundleId: `com.openai.codex`
- windowTitle: `Codex`

## Provenance
- sessionId: `session-gui-b250e7f9-teaching-20260310-155114`
- taskId: `task-session-gui-b250e7f9-teaching-20260310-155114-001`
- knowledgeItemId: `ki-task-session-gui-b250e7f9-teaching-20260310-155114-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Codex（Codex）中，步骤摘要：点击。共 1 步，任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（源事件 b32deea6-6f40-4bd4-9e39-989770a3ce35）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `b32deea6-6f40-4bd4-9e39-989770a3ce35`

## Safety Notes
- 执行前前台应用必须是 com.openai.codex。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `1`
- requiredFrontmostAppBundleId: `com.openai.codex`
- confidence: `0.72`
