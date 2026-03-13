---
name: benchmark-pdb-017-safari-start-page-b
description: 在 Safari浏览器 中复现任务 task-session-gui-f23128c2-teaching-20260310-145427-002 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-017-safari-start-page-b","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-f23128c2-teaching-20260310-145427-002","taskId":"task-session-gui-f23128c2-teaching-20260310-145427-002","sessionId":"session-gui-f23128c2-teaching-20260310-145427","repairVersion":0}}
---

# 在 Safari浏览器 中复现任务 task-session-gui-f23128c2-teaching-20260310-145427-002 的操作流程

## Context
- appName: `Safari浏览器`
- appBundleId: `com.apple.Safari`
- windowTitle: `个人 — 起始页`

## Provenance
- sessionId: `session-gui-f23128c2-teaching-20260310-145427`
- taskId: `task-session-gui-f23128c2-teaching-20260310-145427-002`
- knowledgeItemId: `ki-task-session-gui-f23128c2-teaching-20260310-145427-002`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Safari浏览器（个人 — 起始页）中，步骤摘要：点击。共 1 步，任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（源事件 6e1d58b7-22a6-45c4-9310-d8bcfc59886b）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `6e1d58b7-22a6-45c4-9310-d8bcfc59886b`

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
