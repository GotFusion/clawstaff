---
name: benchmark-pdb-016-xcode-package-single-click
description: 在 Xcode 中复现任务 task-session-gui-f23128c2-teaching-20260310-145427-001 的操作流程
user-invocable: true
disable-model-invocation: false
metadata: {"openclaw":{"emoji":"🎓","skillKey":"benchmark-pdb-016-xcode-package-single-click","requires":{"config":["openstaff.enabled"]}},"openstaff":{"knowledgeItemId":"ki-task-session-gui-f23128c2-teaching-20260310-145427-001","taskId":"task-session-gui-f23128c2-teaching-20260310-145427-001","sessionId":"session-gui-f23128c2-teaching-20260310-145427","repairVersion":0}}
---

# 在 Xcode 中复现任务 task-session-gui-f23128c2-teaching-20260310-145427-001 的操作流程

## Context
- appName: `Xcode`
- appBundleId: `com.apple.dt.Xcode`
- windowTitle: `macos — Package.swift`

## Provenance
- sessionId: `session-gui-f23128c2-teaching-20260310-145427`
- taskId: `task-session-gui-f23128c2-teaching-20260310-145427-001`
- knowledgeItemId: `ki-task-session-gui-f23128c2-teaching-20260310-145427-001`
- sourceTaskChunkSchemaVersion: `knowledge.task-chunk.v0`
- sourceEventCount: `1`
- knowledgeGeneratorVersion: `rule-v0`
- skillGeneratorVersion: `openstaff-skill-mapper-v1`
- repairVersion: `0`

## Teacher Summary
在Xcode（macos — Package.swift）中，步骤摘要：点击。共 1 步，任务分段原因：上下文切换切分。

## Steps
1. [click] 执行第 1 步点击操作（源事件 49153b44-2ee7-41e4-a12d-855652e81075）。
   - knowledgeStepId: `step-001`
   - target: `unknown`
   - preferredLocatorType: `unknown`
   - sourceEventIds: `49153b44-2ee7-41e4-a12d-855652e81075`

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
