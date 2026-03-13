---
name: benchmark-pdb-019-xcode-focus-d
description: 在 Xcode 中复现任务 task-session-gui-fff3b655-teaching-20260310-201407-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-019-xcode-focus-d","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-fff3b655-teaching-20260310-201407-001","taskId":"task-session-gui-fff3b655-teaching-20260310-201407-001","sessionId":"session-gui-fff3b655-teaching-20260310-201407","repairVersion":0}}
---

# 在 Xcode 中复现任务 task-session-gui-fff3b655-teaching-20260310-201407-001 的操作流程

## Context
- appName: `Xcode`
- appBundleId: `com.apple.dt.Xcode`
- windowTitle: `None`

## Provenance
- sessionId: `session-gui-fff3b655-teaching-20260310-201407`
- taskId: `task-session-gui-fff3b655-teaching-20260310-201407-001`
- knowledgeItemId: `ki-task-session-gui-fff3b655-teaching-20260310-201407-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Xcode（未知窗口）中，步骤摘要：点击。共 1 步（原始事件 1 条），任务分段原因：上下文切换切分。

## Steps
1. [click] 执行第 1 步点击操作（x=535, y=46，源事件 499c2eee-fc33-4cac-a71e-d2e97151fa4e）。
   - knowledgeStepId: `step-001`
   - target: `coordinate:535,46`
   - preferredLocatorType: `coordinateFallback`
   - sourceEventIds: `499c2eee-fc33-4cac-a71e-d2e97151fa4e`

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
- expectedStepCount: `1`
- requiredFrontmostAppBundleId: `com.apple.dt.Xcode`
- confidence: `0.72`
