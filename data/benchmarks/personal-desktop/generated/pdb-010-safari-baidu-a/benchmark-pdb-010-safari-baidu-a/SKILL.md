---
name: benchmark-pdb-010-safari-baidu-a
description: 在 Safari浏览器 中复现任务 task-session-gui-5c113c56-teaching-20260310-144428-003 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-010-safari-baidu-a","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-5c113c56-teaching-20260310-144428-003","taskId":"task-session-gui-5c113c56-teaching-20260310-144428-003","sessionId":"session-gui-5c113c56-teaching-20260310-144428","repairVersion":0}}
---

# 在 Safari浏览器 中复现任务 task-session-gui-5c113c56-teaching-20260310-144428-003 的操作流程

## Context
- appName: `Safari浏览器`
- appBundleId: `com.apple.Safari`
- windowTitle: `个人 — 百度一下，你就知道`

## Provenance
- sessionId: `session-gui-5c113c56-teaching-20260310-144428`
- taskId: `task-session-gui-5c113c56-teaching-20260310-144428-003`
- knowledgeItemId: `ki-task-session-gui-5c113c56-teaching-20260310-144428-003`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Safari浏览器（个人 — 百度一下，你就知道）中，步骤摘要：点击。共 1 步，任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（源事件 258f6659-8738-43b0-8332-5b5a02a81149）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `258f6659-8738-43b0-8332-5b5a02a81149`

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
