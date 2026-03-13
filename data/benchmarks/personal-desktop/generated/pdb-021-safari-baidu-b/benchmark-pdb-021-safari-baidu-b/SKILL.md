---
name: benchmark-pdb-021-safari-baidu-b
description: 在 Safari浏览器 中复现任务 task-session-gui-fff3b655-teaching-20260310-201407-003 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-021-safari-baidu-b","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-fff3b655-teaching-20260310-201407-003","taskId":"task-session-gui-fff3b655-teaching-20260310-201407-003","sessionId":"session-gui-fff3b655-teaching-20260310-201407","repairVersion":0}}
---

# 在 Safari浏览器 中复现任务 task-session-gui-fff3b655-teaching-20260310-201407-003 的操作流程

## Context
- appName: `Safari浏览器`
- appBundleId: `com.apple.Safari`
- windowTitle: `个人 — 百度一下，你就知道`

## Provenance
- sessionId: `session-gui-fff3b655-teaching-20260310-201407`
- taskId: `task-session-gui-fff3b655-teaching-20260310-201407-003`
- knowledgeItemId: `ki-task-session-gui-fff3b655-teaching-20260310-201407-003`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `2`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Safari浏览器（个人 — 百度一下，你就知道）中，步骤摘要：快捷键 -> 点击。共 2 步（原始事件 2 条），任务分段原因：会话结束。

## Steps
1. [shortcut] 执行第 1 步快捷键 return（源事件 d72a604e-d461-4596-af31-5c313d130f80）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `d72a604e-d461-4596-af31-5c313d130f80`
2. [click] 执行第 2 步点击操作（x=45, y=964，源事件 70cb0ae1-53f4-436f-a501-a82a30889f98）。
   - knowledgeStepId: `step-002`
   - target: `coordinate:45,964`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `70cb0ae1-53f4-436f-a501-a82a30889f98`

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
