---
name: benchmark-pdb-002-xcode-package-navigation-b
description: 在 Xcode 中复现任务 task-session-gui-0cacb6a5-teaching-20260310-204532-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-002-xcode-package-navigation-b","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-0cacb6a5-teaching-20260310-204532-001","taskId":"task-session-gui-0cacb6a5-teaching-20260310-204532-001","sessionId":"session-gui-0cacb6a5-teaching-20260310-204532","repairVersion":0}}
---

# 在 Xcode 中复现任务 task-session-gui-0cacb6a5-teaching-20260310-204532-001 的操作流程

## Context
- appName: `Xcode`
- appBundleId: `com.apple.dt.Xcode`
- windowTitle: `macos — Package.swift`

## Provenance
- sessionId: `session-gui-0cacb6a5-teaching-20260310-204532`
- taskId: `task-session-gui-0cacb6a5-teaching-20260310-204532-001`
- knowledgeItemId: `ki-task-session-gui-0cacb6a5-teaching-20260310-204532-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `19`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Xcode（macos — Package.swift）中，步骤摘要：点击 -> 点击 -> 点击 -> 点击 -> 回车 -> 点击。共 6 步（原始事件 19 条），任务分段原因：会话结束。

## Steps
1. [click] 执行第 1 步点击操作（x=538, y=43，源事件 2a50f718-c3ba-46e0-800f-2e4475858053）。
   - knowledgeStepId: `step-001`
   - target: `coordinate:538,43`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `2a50f718-c3ba-46e0-800f-2e4475858053`
2. [click] 执行第 2 步点击操作（x=729, y=637，源事件 03b6c26e-f326-4f5c-9161-2cef96ba9ed8）。
   - knowledgeStepId: `step-002`
   - target: `coordinate:729,637`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `03b6c26e-f326-4f5c-9161-2cef96ba9ed8`
3. [click] 执行第 3 步点击操作（x=382, y=761，源事件 980c729d-a8d5-4ba1-8923-2cf34285c24c）。
   - knowledgeStepId: `step-003`
   - target: `coordinate:382,761`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `980c729d-a8d5-4ba1-8923-2cf34285c24c`
4. [click] 执行第 4 步点击操作（x=1581, y=824，源事件 62f69cbd-03be-47e1-8333-e28500bdc318）。
   - knowledgeStepId: `step-004`
   - target: `coordinate:1581,824`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `62f69cbd-03be-47e1-8333-e28500bdc318`
5. [input] 执行第 5 步输入"www.baidu.com"并按回车（源事件 45f0a6f2-1288-48c9-a226-67f19c5a6b09, cdd1f9e6-737c-4231-ae0e-53b77f9316cb, 5e51a65c-2b35-4103-96ee-d0b50e091923, 45785b7a-e0a2-43a0-8fbf-fedd9b2fa88d, 71c86528-f7a6-4016-b4a0-0f6ef1f06b42, c8590d15-8731-416c-976c-cfe56153f614, 45ca7e4a-90b3-47b1-9cb3-18d5eaaff8ee, 2ba9043e-bf28-42a8-9686-fb34afd075c6, 67decfa2-bcaa-49be-b73f-52583ce38375, d5f28f45-5fbf-4195-bfed-971e501cebb5, 291ce534-feae-4727-aa7c-92c61fd42684, 4c351779-4d14-4d7d-ab8e-3bb250591ff5, bbf632ac-3ba8-45c9-ae73-1c95639ff383, 31f5d6a0-cb3f-4d79-a3b7-3c43f0bae6a1）。
   - knowledgeStepId: `step-005`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `45f0a6f2-1288-48c9-a226-67f19c5a6b09, cdd1f9e6-737c-4231-ae0e-53b77f9316cb, 5e51a65c-2b35-4103-96ee-d0b50e091923, 45785b7a-e0a2-43a0-8fbf-fedd9b2fa88d, 71c86528-f7a6-4016-b4a0-0f6ef1f06b42, c8590d15-8731-416c-976c-cfe56153f614, 45ca7e4a-90b3-47b1-9cb3-18d5eaaff8ee, 2ba9043e-bf28-42a8-9686-fb34afd075c6, 67decfa2-bcaa-49be-b73f-52583ce38375, d5f28f45-5fbf-4195-bfed-971e501cebb5, 291ce534-feae-4727-aa7c-92c61fd42684, 4c351779-4d14-4d7d-ab8e-3bb250591ff5, bbf632ac-3ba8-45c9-ae73-1c95639ff383, 31f5d6a0-cb3f-4d79-a3b7-3c43f0bae6a1`
6. [click] 执行第 6 步点击操作（x=756, y=779，源事件 cbf104dc-8fea-43d0-8bcb-c0a45344d1ee）。
   - knowledgeStepId: `step-006`
   - target: `coordinate:756,779`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `cbf104dc-8fea-43d0-8bcb-c0a45344d1ee`

## Safety Notes
- 执行前前台应用必须是 com.apple.dt.Xcode。
- 执行该知识条目时，需要老师确认后再执行。
- 坐标点击目标可能随分辨率或界面变化漂移。

## Failure Policy
- onContextMismatch: `stopAndAskTeacher`
- onStepError: `stopAndAskTeacher`
- onUnknownAction: `stopAndAskTeacher`

## Runtime Requirements
- requiresTeacherConfirmation: `true`
- expectedStepCount: `6`
- requiredFrontmostAppBundleId: `com.apple.dt.Xcode`
- confidence: `0.72`
