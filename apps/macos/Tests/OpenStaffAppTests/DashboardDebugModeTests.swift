import Foundation
import XCTest
@testable import OpenStaffApp

final class DashboardDebugModeTests: XCTestCase {
    func testDiagnosticsBuilderSurfacesPermissionTransitionAndExecutionFailures() {
        let diagnostics = DashboardDebugDiagnosticsBuilder.build(
            input: DashboardDebugDiagnosticsInput(
                selectedMode: .assist,
                currentMode: .teaching,
                runningMode: nil,
                modeStatusSummary: "待机（已选择辅助模式）",
                currentStatusCode: OrchestratorStatusCode.modeTransitionRejected.rawValue,
                transitionMessage: "Transition guard conditions are not met.",
                transitionAccepted: false,
                unmetRequirements: [.teacherConfirmed, .executionPlanReady],
                permissionSnapshot: PermissionSnapshot(
                    accessibilityTrusted: false,
                    dataDirectoryWritable: false
                ),
                captureStatusText: nil,
                activeObservationSessionId: nil,
                capturedEventCount: 0,
                learningSessionState: LearningSessionState(
                    mode: .assist,
                    runningMode: .assist,
                    observesTeacherActions: true,
                    captureRunning: false,
                    teacherPaused: false,
                    temporaryPauseUntil: nil,
                    currentApp: .init(appName: "OpenStaff", appBundleId: "dev.openstaff.app"),
                    status: .paused,
                    statusReason: "学习采集等待恢复。",
                    matchedRule: nil,
                    lastSuccessfulWriteAt: nil,
                    activeSessionId: nil,
                    capturedEventCount: 0,
                    updatedAt: Date(timeIntervalSince1970: 1_742_868_000)
                ),
                quickFeedbackStatusMessage: "反馈保存失败：mock failure",
                quickFeedbackSucceeded: false,
                teachingSkillStatusMessage: nil,
                teachingSkillStatusSucceeded: true,
                teachingSkillProcessing: false,
                skillActionStatusMessage: nil,
                skillActionSucceeded: true,
                skillActionProcessing: false,
                learningPrivacyStatusMessage: nil,
                learningPrivacyStatusSucceeded: true,
                executorBackendDescription: "Direct Accessibility Executor",
                usesHelperExecutorBackend: false,
                executorHelperPath: nil,
                isObservationCaptureRunning: false,
                currentCapabilities: ["observeTeacherActions", "predictNextAction"],
                selectedExecutionLog: ExecutionLogSummary(
                    id: "log-001",
                    mode: .assist,
                    timestamp: Date(timeIntervalSince1970: 1_742_868_100),
                    traceId: "trace-001",
                    sessionId: "session-001",
                    taskId: "task-001",
                    status: "STATUS_ASSIST_FAILED",
                    message: "Assist execution failed at locator resolution.",
                    component: "assist.mode.loop",
                    errorCode: "ERR-LOCATOR-FAILED",
                    planId: nil,
                    skillId: nil,
                    planStepId: nil,
                    skillName: nil,
                    skillDirectoryPath: nil,
                    sourceKnowledgeItemId: nil,
                    sourceStepId: nil,
                    stepId: nil,
                    actionType: nil,
                    exitCode: nil,
                    sourceFilePath: "/tmp/openstaff/data/logs/2026-03-26/session-001-assist.log",
                    lineNumber: 12
                ),
                selectedExecutionReviewDetail: nil,
                selectedLearnedSkill: nil,
                selectedSkillDriftReport: nil,
                selectedSkillRepairPlan: nil
            ),
            workspaceSnapshot: DashboardDebugWorkspaceSnapshot(
                capturedAt: Date(timeIntervalSince1970: 1_742_868_200),
                repositoryRootPath: "/tmp/openstaff",
                entries: [
                    DashboardDebugWorkspaceEntry(
                        name: "data",
                        path: "/tmp/openstaff/data",
                        exists: false,
                        isDirectory: false,
                        isWritable: false,
                        fileCount: 0,
                        latestModifiedAt: nil,
                        latestFilePath: nil,
                        critical: true
                    )
                ]
            )
        )

        XCTAssertTrue(diagnostics.contains(where: { $0.source == "workspace" && $0.title == "数据目录不可写" }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "permissions" && $0.title == "辅助功能权限未授权" }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "mode_transition" && $0.severity == .error }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "quick_feedback" && $0.severity == .error }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "execution_log" && $0.severity == .error }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "workspace" && $0.title.contains("关键目录缺失") }))
    }

    func testWorkspaceSnapshotCaptureCountsFilesAndLatestFile() throws {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-debug-workspace-\(UUID().uuidString)", isDirectory: true)
        let rawEventsDirectory = root.appendingPathComponent("raw-events", isDirectory: true)
        try fileManager.createDirectory(at: rawEventsDirectory, withIntermediateDirectories: true)

        let firstFile = rawEventsDirectory.appendingPathComponent("a.jsonl", isDirectory: false)
        let secondFile = rawEventsDirectory.appendingPathComponent("b.jsonl", isDirectory: false)
        try "{}\n".write(to: firstFile, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.01)
        try "{\"event\":\"latest\"}\n".write(to: secondFile, atomically: true, encoding: .utf8)

        defer {
            try? fileManager.removeItem(at: root)
        }

        let snapshot = DashboardDebugWorkspaceSnapshot.capture(
            roots: [
                DashboardDebugWorkspaceRoot(
                    name: "raw-events",
                    url: rawEventsDirectory,
                    critical: false
                )
            ],
            fileManager: fileManager
        )

        let entry = try XCTUnwrap(snapshot.entry(named: "raw-events"))
        XCTAssertTrue(entry.exists)
        XCTAssertTrue(entry.isDirectory)
        XCTAssertEqual(entry.fileCount, 2)
        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(entry.latestFilePath)).standardizedFileURL.path,
            secondFile.standardizedFileURL.path
        )
    }

    func testDiagnosticsBuilderFlagsPreflightAndRejectedSkill() {
        let skill = LearnedSkillSummary(
            id: "pending|/tmp/skill-debug",
            skillName: "debug-skill",
            taskId: "task-002",
            sessionId: "session-002",
            knowledgeItemId: "knowledge-002",
            skillDirectoryPath: "/tmp/skill-debug",
            skillJSONPath: "/tmp/skill-debug/openstaff-skill.json",
            storageScope: .pending,
            llmOutputAccepted: false,
            createdAt: nil,
            review: LearnedSkillReviewSummary(
                decision: .rejected,
                timestamp: Date(timeIntervalSince1970: 1_742_868_300)
            ),
            preflight: SkillPreflightReport(
                skillName: "debug-skill",
                skillDirectoryPath: "/tmp/skill-debug",
                status: .failed,
                summary: "Missing locator anchors.",
                requiresTeacherConfirmation: false,
                isAutoRunnable: false,
                allowedAppBundleIds: [],
                issues: [
                    SkillPreflightIssue(
                        severity: .error,
                        code: .missingLocator,
                        message: "Step step-001 is missing a stable locator.",
                        stepId: "step-001"
                    )
                ],
                steps: []
            )
        )

        let diagnostics = DashboardDebugDiagnosticsBuilder.build(
            input: DashboardDebugDiagnosticsInput(
                selectedMode: .student,
                currentMode: .student,
                runningMode: .student,
                modeStatusSummary: "学生模式（运行中）",
                currentStatusCode: OrchestratorStatusCode.modeStable.rawValue,
                transitionMessage: nil,
                transitionAccepted: nil,
                unmetRequirements: [],
                permissionSnapshot: PermissionSnapshot(
                    accessibilityTrusted: true,
                    dataDirectoryWritable: true
                ),
                captureStatusText: nil,
                activeObservationSessionId: nil,
                capturedEventCount: 0,
                learningSessionState: LearningSessionState.initial(selectedMode: .student),
                quickFeedbackStatusMessage: nil,
                quickFeedbackSucceeded: true,
                teachingSkillStatusMessage: nil,
                teachingSkillStatusSucceeded: true,
                teachingSkillProcessing: false,
                skillActionStatusMessage: nil,
                skillActionSucceeded: true,
                skillActionProcessing: false,
                learningPrivacyStatusMessage: nil,
                learningPrivacyStatusSucceeded: true,
                executorBackendDescription: "Direct Accessibility Executor",
                usesHelperExecutorBackend: false,
                executorHelperPath: nil,
                isObservationCaptureRunning: false,
                currentCapabilities: ["planAutonomousTask"],
                selectedExecutionLog: nil,
                selectedExecutionReviewDetail: nil,
                selectedLearnedSkill: skill,
                selectedSkillDriftReport: nil,
                selectedSkillRepairPlan: nil
            ),
            workspaceSnapshot: DashboardDebugWorkspaceSnapshot(
                capturedAt: Date(timeIntervalSince1970: 1_742_868_301),
                repositoryRootPath: "/tmp/openstaff",
                entries: []
            )
        )

        XCTAssertTrue(diagnostics.contains(where: { $0.source == "skill_preflight" && $0.severity == .error }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "skill_bundle" && $0.severity == .warning }))
        XCTAssertTrue(diagnostics.contains(where: { $0.source == "skill_review" && $0.severity == .warning }))
    }
}
