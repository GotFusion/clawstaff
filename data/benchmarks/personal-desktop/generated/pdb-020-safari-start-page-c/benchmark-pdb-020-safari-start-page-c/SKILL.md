---
name: benchmark-pdb-020-safari-start-page-c
description: 在 Safari浏览器 中复现任务 task-session-gui-fff3b655-teaching-20260310-201407-002 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-020-safari-start-page-c","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-fff3b655-teaching-20260310-201407-002","taskId":"task-session-gui-fff3b655-teaching-20260310-201407-002","sessionId":"session-gui-fff3b655-teaching-20260310-201407","repairVersion":0}}
---

# 在 Safari浏览器 中复现任务 task-session-gui-fff3b655-teaching-20260310-201407-002 的操作流程

## Context
- appName: `Safari浏览器`
- appBundleId: `com.apple.Safari`
- windowTitle: `个人 — 起始页`

## Provenance
- sessionId: `session-gui-fff3b655-teaching-20260310-201407`
- taskId: `task-session-gui-fff3b655-teaching-20260310-201407-002`
- knowledgeItemId: `ki-task-session-gui-fff3b655-teaching-20260310-201407-002`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `13`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Safari浏览器（个人 — 起始页）中，步骤摘要：输入。共 1 步（原始事件 13 条），任务分段原因：上下文切换切分。

## Steps
1. [input] 执行第 1 步输入"www.baidu.com"（源事件 ea3ace57-e5e5-4e3c-8242-c4fbd7a340c1, 55791118-6cb6-46d2-9673-456747a3dcc9, e275445f-381a-4272-9abd-e39ea3e7f08b, a4d6a6a7-5df7-469d-bf0d-257e28dd228a, 8d61b6eb-b76c-4281-8161-36362bd792ae, 13d1d6eb-3238-4dcb-a10f-4e727e2861af, 2225d86f-ef5f-44b1-ab63-ff8e79fe494f, ccfd1e9e-feb0-4fd5-8208-2a705d1552dd, d1de1dd3-b16f-42a0-80bc-7054d31893db, bafa59c4-fb78-4c98-9918-04b20ed0e1df, aec5658d-3000-44d7-b139-68f787907be3, 9a09dc37-ce26-49a1-8d65-825ae76ef39c, 41e02ebb-a1fe-43ec-9988-54e855690175）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `ea3ace57-e5e5-4e3c-8242-c4fbd7a340c1, 55791118-6cb6-46d2-9673-456747a3dcc9, e275445f-381a-4272-9abd-e39ea3e7f08b, a4d6a6a7-5df7-469d-bf0d-257e28dd228a, 8d61b6eb-b76c-4281-8161-36362bd792ae, 13d1d6eb-3238-4dcb-a10f-4e727e2861af, 2225d86f-ef5f-44b1-ab63-ff8e79fe494f, ccfd1e9e-feb0-4fd5-8208-2a705d1552dd, d1de1dd3-b16f-42a0-80bc-7054d31893db, bafa59c4-fb78-4c98-9918-04b20ed0e1df, aec5658d-3000-44d7-b139-68f787907be3, 9a09dc37-ce26-49a1-8d65-825ae76ef39c, 41e02ebb-a1fe-43ec-9988-54e855690175`

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
