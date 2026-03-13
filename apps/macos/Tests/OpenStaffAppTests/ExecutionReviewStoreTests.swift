import Foundation
import XCTest
@testable import OpenStaffApp

final class ExecutionReviewStoreTests: XCTestCase {
    func testStoreBuildsComparisonRowsAndRepairActionForManualSkillRun() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-execution-review-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let logsRoot = workspaceRoot.appendingPathComponent("data/logs", isDirectory: true)
        let feedbackRoot = workspaceRoot.appendingPathComponent("data/feedback", isDirectory: true)
        let reportsRoot = workspaceRoot.appendingPathComponent("data/reports", isDirectory: true)
        let knowledgeRoot = workspaceRoot.appendingPathComponent("data/knowledge", isDirectory: true)
        let pendingSkillsRoot = workspaceRoot.appendingPathComponent("data/skills/pending", isDirectory: true)
        let doneSkillsRoot = workspaceRoot.appendingPathComponent("data/skills/done", isDirectory: true)

        try fileManager.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: feedbackRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: reportsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: knowledgeRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pendingSkillsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: doneSkillsRoot, withIntermediateDirectories: true)

        let knowledgeItem = KnowledgeItem(
            knowledgeItemId: "knowledge-001",
            taskId: "task-001",
            sessionId: "session-001",
            goal: "保存文档",
            summary: "老师打开保存对话框并点击保存按钮。",
            steps: [
                KnowledgeStep(stepId: "teacher-step-001", instruction: "点击工具栏中的保存按钮", sourceEventIds: ["evt-1"]),
                KnowledgeStep(stepId: "teacher-step-002", instruction: "确认保存对话框中的主按钮", sourceEventIds: ["evt-2"])
            ],
            context: KnowledgeContext(
                appName: "TestApp",
                appBundleId: "com.test.app",
                windowTitle: "Main",
                windowId: nil
            ),
            constraints: [],
            source: KnowledgeSource(
                taskChunkSchemaVersion: "task.chunk.v0",
                startTimestamp: "2026-03-14T10:00:00Z",
                endTimestamp: "2026-03-14T10:00:10Z",
                eventCount: 2,
                boundaryReason: .sessionEnd
            ),
            createdAt: "2026-03-14T10:00:10Z"
        )
        let knowledgeURL = knowledgeRoot.appendingPathComponent("knowledge-001.json", isDirectory: false)
        try JSONEncoder.sorted.encode(knowledgeItem).write(to: knowledgeURL)

        let skillDirectory = pendingSkillsRoot.appendingPathComponent("skill-save-doc", isDirectory: true)
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let skillPayload = SkillBundlePayload(
            schemaVersion: "openstaff.openclaw-skill.v1",
            skillName: "skill-save-doc",
            knowledgeItemId: knowledgeItem.knowledgeItemId,
            taskId: knowledgeItem.taskId,
            sessionId: knowledgeItem.sessionId,
            llmOutputAccepted: true,
            createdAt: "2026-03-14T10:10:00Z",
            mappedOutput: SkillBundleMappedOutput(
                objective: "保存文档",
                context: SkillBundleContext(
                    appName: "TestApp",
                    appBundleId: "com.test.app",
                    windowTitle: "Main"
                ),
                executionPlan: SkillBundleExecutionPlan(
                    requiresTeacherConfirmation: false,
                    steps: [
                        SkillBundleExecutionStep(
                            stepId: "skill-step-001",
                            actionType: "click",
                            instruction: "点击保存按钮",
                            target: "save-button",
                            sourceEventIds: ["evt-1"]
                        ),
                        SkillBundleExecutionStep(
                            stepId: "skill-step-002",
                            actionType: "click",
                            instruction: "点击确认按钮",
                            target: "confirm-button",
                            sourceEventIds: ["evt-2"]
                        )
                    ],
                    completionCriteria: SkillBundleCompletionCriteria(
                        expectedStepCount: 2,
                        requiredFrontmostAppBundleId: "com.test.app"
                    )
                ),
                safetyNotes: [],
                confidence: 0.91
            ),
            provenance: SkillBundleProvenance(
                skillBuild: SkillBundleSkillBuild(repairVersion: 2),
                stepMappings: [
                    SkillBundleStepMapping(
                        skillStepId: "skill-step-001",
                        knowledgeStepId: "teacher-step-001",
                        instruction: "点击保存按钮",
                        sourceEventIds: ["evt-1"],
                        preferredLocatorType: .roleAndTitle,
                        coordinate: SkillBundleCoordinate(x: 200, y: 120, coordinateSpace: "screen"),
                        semanticTargets: [
                            SkillBundleSemanticTarget(
                                locatorType: .roleAndTitle,
                                appBundleId: "com.test.app",
                                windowTitlePattern: "^Main$",
                                elementRole: "AXButton",
                                elementTitle: "保存",
                                confidence: 0.92,
                                source: "capture"
                            )
                        ]
                    ),
                    SkillBundleStepMapping(
                        skillStepId: "skill-step-002",
                        knowledgeStepId: "teacher-step-002",
                        instruction: "点击确认按钮",
                        sourceEventIds: ["evt-2"],
                        preferredLocatorType: .roleAndTitle,
                        coordinate: SkillBundleCoordinate(x: 240, y: 180, coordinateSpace: "screen"),
                        semanticTargets: [
                            SkillBundleSemanticTarget(
                                locatorType: .roleAndTitle,
                                appBundleId: "com.test.app",
                                windowTitlePattern: "^Save$",
                                elementRole: "AXButton",
                                elementTitle: "确认",
                                confidence: 0.88,
                                source: "capture"
                            )
                        ]
                    )
                ]
            )
        )
        try JSONEncoder.sorted.encode(skillPayload).write(
            to: skillDirectory.appendingPathComponent("openstaff-skill.json", isDirectory: false)
        )

        let logDirectory = logsRoot.appendingPathComponent("2026-03-14", isDirectory: true)
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logFile = logDirectory.appendingPathComponent("session-001-student.log", isDirectory: false)
        let logEntries = [
            StudentLoopLogEntry(
                timestamp: "2026-03-14T10:15:00Z",
                traceId: "trace-skill-ui-run-001",
                sessionId: "session-001",
                taskId: "task-001",
                component: "student.skill.single-run",
                status: StudentLoopStatusCode.executionStarted.rawValue,
                message: "Manual UI run started for skill skill-save-doc.",
                skillId: "skill-save-doc",
                skillName: "skill-save-doc",
                skillDirectoryPath: skillDirectory.path,
                sourceKnowledgeItemId: knowledgeItem.knowledgeItemId
            ),
            StudentLoopLogEntry(
                timestamp: "2026-03-14T10:15:02Z",
                traceId: "trace-skill-ui-run-001",
                sessionId: "session-001",
                taskId: "task-001",
                component: "student.skill.single-run",
                status: StudentLoopStatusCode.executionCompleted.rawValue,
                message: "已执行 click：定位到保存按钮",
                skillId: "skill-save-doc-skill-step-001",
                planStepId: "single-step-001",
                skillName: "skill-save-doc",
                skillDirectoryPath: skillDirectory.path,
                sourceKnowledgeItemId: knowledgeItem.knowledgeItemId,
                sourceStepId: "skill-step-001"
            ),
            StudentLoopLogEntry(
                timestamp: "2026-03-14T10:15:04Z",
                traceId: "trace-skill-ui-run-001",
                sessionId: "session-001",
                taskId: "task-001",
                component: "student.skill.single-run",
                status: StudentLoopStatusCode.executionFailed.rawValue,
                errorCode: StudentLoopErrorCode.executionFailed.rawValue,
                message: "未找到确认按钮，点击失败",
                skillId: "skill-save-doc-skill-step-002",
                planStepId: "single-step-002",
                skillName: "skill-save-doc",
                skillDirectoryPath: skillDirectory.path,
                sourceKnowledgeItemId: knowledgeItem.knowledgeItemId,
                sourceStepId: "skill-step-002"
            )
        ]
        let logContent = try logEntries
            .map { try JSONEncoder.sorted.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n") + "\n"
        try logContent.write(to: logFile, atomically: true, encoding: .utf8)

        let store = ExecutionReviewStore(
            logsRootDirectory: logsRoot,
            feedbackRootDirectory: feedbackRoot,
            reportsRootDirectory: reportsRoot,
            knowledgeRootDirectory: knowledgeRoot,
            skillRoots: [
                ExecutionReviewSkillRoot(scopeId: "pending", directory: pendingSkillsRoot),
                ExecutionReviewSkillRoot(scopeId: "done", directory: doneSkillsRoot)
            ]
        )

        let snapshot = store.loadExecutionSnapshot(limit: 20)
        let failedLog = try XCTUnwrap(snapshot.logs.first(where: { $0.errorCode == StudentLoopErrorCode.executionFailed.rawValue }))
        let detail = store.loadDetail(for: failedLog)

        XCTAssertEqual(detail.skillName, "skill-save-doc")
        XCTAssertEqual(detail.currentRepairVersion, 2)
        XCTAssertEqual(detail.comparisonRows.count, 2)
        XCTAssertEqual(detail.comparisonRows[0].teacherStep.detail, "点击工具栏中的保存按钮")
        XCTAssertEqual(detail.comparisonRows[1].actualResult.title, "执行失败")
        XCTAssertEqual(detail.locatorRepairAction?.type, .updateSkillLocator)
        XCTAssertEqual(detail.locatorRepairAction?.affectedStepIds, ["skill-step-002"])
        XCTAssertEqual(detail.reteachAction?.affectedStepIds, ["skill-step-002"])
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
