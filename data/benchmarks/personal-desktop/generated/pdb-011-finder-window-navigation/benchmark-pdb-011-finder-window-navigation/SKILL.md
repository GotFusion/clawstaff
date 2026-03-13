---
name: benchmark-pdb-011-finder-window-navigation
description: 在 访达 中复现任务 task-session-gui-8ec4947b-teaching-20260310-202519-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-011-finder-window-navigation","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-8ec4947b-teaching-20260310-202519-001","taskId":"task-session-gui-8ec4947b-teaching-20260310-202519-001","sessionId":"session-gui-8ec4947b-teaching-20260310-202519","repairVersion":0}}
---

# 在 访达 中复现任务 task-session-gui-8ec4947b-teaching-20260310-202519-001 的操作流程

## Context
- appName: `访达`
- appBundleId: `com.apple.finder`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-8ec4947b-teaching-20260310-202519`
- taskId: `task-session-gui-8ec4947b-teaching-20260310-202519-001`
- knowledgeItemId: `ki-task-session-gui-8ec4947b-teaching-20260310-202519-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `16`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在访达（未知窗口）中，步骤摘要：点击 -> 回车 -> 点击。共 3 步（原始事件 16 条），任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（x=543, y=30，源事件 536208db-4a5d-4c4a-9776-20ef4e24f940）。
   - knowledgeStepId: `step-001`
   - target: `coordinate:543,30`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `536208db-4a5d-4c4a-9776-20ef4e24f940`
2. [input] 执行第 2 步输入"www.baidu.com"并按回车（源事件 f35460e1-5168-4527-99ae-740eef79b927, 2bee0fa6-b25c-496a-9846-9bf21f405822, 109361ba-0216-4d46-8915-2143cbb05c5d, dbb83705-0c4b-43d6-8135-8569dc8adf41, 7b2b0a01-0e4d-4373-9827-51faed5d38ee, e850337e-3631-4e18-acd9-50ecd1b1db15, a73d4a84-e26e-4fb2-aadf-02e993b42fcb, b69ec096-235b-4da4-bb1b-9541d1a8fa4d, 4d6e21fd-e686-4eca-941b-75c0ff6bc764, 3c31fbb8-bd1a-45f4-b6f0-6a3ee902958d, 0c78b289-5300-41c9-83db-fedcd52148d9, 98c5da65-693f-4fef-bc47-466af2761b98, e5d8593c-267b-4565-85dc-d85785a7e62f, 3582360b-2f5a-4ab5-b2b3-49038ae1414b）。
   - knowledgeStepId: `step-002`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `f35460e1-5168-4527-99ae-740eef79b927, 2bee0fa6-b25c-496a-9846-9bf21f405822, 109361ba-0216-4d46-8915-2143cbb05c5d, dbb83705-0c4b-43d6-8135-8569dc8adf41, 7b2b0a01-0e4d-4373-9827-51faed5d38ee, e850337e-3631-4e18-acd9-50ecd1b1db15, a73d4a84-e26e-4fb2-aadf-02e993b42fcb, b69ec096-235b-4da4-bb1b-9541d1a8fa4d, 4d6e21fd-e686-4eca-941b-75c0ff6bc764, 3c31fbb8-bd1a-45f4-b6f0-6a3ee902958d, 0c78b289-5300-41c9-83db-fedcd52148d9, 98c5da65-693f-4fef-bc47-466af2761b98, e5d8593c-267b-4565-85dc-d85785a7e62f, 3582360b-2f5a-4ab5-b2b3-49038ae1414b`
3. [click] 执行第 3 步点击操作（x=39, y=972，源事件 95dddaef-b572-41aa-a033-f389e819971f）。
   - knowledgeStepId: `step-003`
   - target: `coordinate:39,972`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `95dddaef-b572-41aa-a033-f389e819971f`

## Safety Notes
- 执行前前台应用必须是 com.apple.finder。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `3`
- requiredFrontmostAppBundleId: `com.apple.finder`
- confidence: `0.72`
