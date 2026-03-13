---
name: benchmark-pdb-008-codex-focus-a
description: 在 Codex 中复现任务 task-session-gui-5c113c56-teaching-20260310-144428-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-008-codex-focus-a","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-5c113c56-teaching-20260310-144428-001","taskId":"task-session-gui-5c113c56-teaching-20260310-144428-001","sessionId":"session-gui-5c113c56-teaching-20260310-144428","repairVersion":0}}
---

# 在 Codex 中复现任务 task-session-gui-5c113c56-teaching-20260310-144428-001 的操作流程

## Context
- appName: `Codex`
- appBundleId: `com.openai.codex`
- windowTitle: `Codex`

## Provenance
- sessionId: `session-gui-5c113c56-teaching-20260310-144428`
- taskId: `task-session-gui-5c113c56-teaching-20260310-144428-001`
- knowledgeItemId: `ki-task-session-gui-5c113c56-teaching-20260310-144428-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Codex（Codex）中，步骤摘要：点击。共 1 步，任务分段原因：上下文切换切分。

## Steps
1. [click] 执行第 1 步点击操作（源事件 193981a2-8710-47e6-ab4a-d38531da5d05）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `193981a2-8710-47e6-ab4a-d38531da5d05`

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
