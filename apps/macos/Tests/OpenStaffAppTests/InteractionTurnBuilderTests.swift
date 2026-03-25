import XCTest
@testable import OpenStaffApp

final class InteractionTurnBuilderTests: XCTestCase {
    func testBuilderDerivesStableIdsAndDefaultLifecycleFields() {
        let appContext = InteractionTurnAppContext(
            appName: "Xcode",
            appBundleId: "com.apple.dt.Xcode",
            windowTitle: "Package.swift"
        )
        let observationRef = InteractionTurnObservationReference(
            sourceRecordPath: "data/source-record.json",
            rawEventLogPath: "data/raw-events/2026-03-10/session-001.jsonl",
            taskChunkPath: "data/task-chunks/2026-03-10/task-001.json",
            eventIds: ["evt-001"],
            appContext: appContext
        )
        let stepReference = InteractionTurnStepReference(
            stepId: "step-001",
            stepIndex: 1,
            instruction: "点击 Package.swift。",
            knowledgeItemId: "ki-task-001",
            knowledgeStepId: "step-001",
            skillStepId: "step-001",
            sourceEventIds: ["evt-001"]
        )
        let semanticRef = InteractionTurnSemanticTargetSetReference(
            sourcePath: "data/skills/example/openstaff-skill.json",
            sourceStepId: "step-001",
            preferredLocatorType: .coordinateFallback,
            semanticTargets: [
                SemanticTarget.coordinateFallback(
                    appBundleId: "com.apple.dt.Xcode",
                    windowTitle: "Package.swift",
                    coordinate: PointerLocation(x: 520, y: 40)
                )
            ]
        )

        let turn = InteractionTurnBuilder.build(
            InteractionTurnBuildInput(
                sessionId: "session-001",
                taskId: "task-001",
                stepId: "step-001",
                mode: .teaching,
                turnKind: .taskProgression,
                stepIndex: 1,
                intentSummary: "在 Xcode 中打开 Package.swift。",
                actionSummary: "点击 Package.swift。",
                actionKind: .guiAction,
                appContext: appContext,
                observationRef: observationRef,
                semanticTargetSetRef: semanticRef,
                stepReference: stepReference,
                sourceRefs: [
                    InteractionTurnSourceReference(
                        artifactKind: "knowledgeItem",
                        path: "data/knowledge/2026-03-10/task-001.json",
                        identifier: "ki-task-001"
                    )
                ],
                startedAt: "2026-03-18T10:00:00Z",
                endedAt: "2026-03-18T10:00:01Z"
            )
        )

        XCTAssertEqual(turn.turnId, "turn-teaching-taskProgression-task-001-step-001")
        XCTAssertEqual(turn.traceId, "trace-learning-teaching-task-001-step-001")
        XCTAssertEqual(turn.status, .captured)
        XCTAssertEqual(turn.learningState, .linked)
        XCTAssertEqual(turn.riskLevel, .high)
        XCTAssertEqual(turn.semanticTargetSetRef?.candidateCount, 1)
        XCTAssertNil(turn.buildDiagnostics)
    }

    func testBuilderElevatesReviewAndDangerSignals() {
        let appContext = InteractionTurnAppContext(
            appName: "System Settings",
            appBundleId: "com.apple.systempreferences"
        )
        let observationRef = InteractionTurnObservationReference(
            eventIds: ["evt-001"],
            appContext: appContext
        )
        let stepReference = InteractionTurnStepReference(
            stepId: "step-001",
            stepIndex: 1,
            instruction: "修改系统设置。",
            sourceEventIds: ["evt-001"]
        )
        let execution = InteractionTurnExecutionLink(
            traceId: "trace-001",
            component: "student.openclaw.runner.step",
            status: "failed",
            errorCode: "EXE-ACTION-BLOCKED"
        )
        let review = InteractionTurnReviewLink(
            reviewId: "feedback-001",
            source: "teacherReview",
            decision: TeacherQuickFeedbackAction.tooDangerous.rawValue,
            summary: "老师判定本次执行过于危险。",
            reviewedAt: "2026-03-18T10:05:00Z"
        )

        let turn = InteractionTurnBuilder.build(
            InteractionTurnBuildInput(
                sessionId: "session-002",
                taskId: "task-002",
                stepId: "step-001",
                mode: .student,
                turnKind: .skillExecution,
                stepIndex: 1,
                intentSummary: "修改系统设置。",
                actionSummary: "尝试打开系统偏好设置并修改配置。",
                actionKind: .nativeAction,
                appContext: appContext,
                observationRef: observationRef,
                stepReference: stepReference,
                execution: execution,
                review: review,
                sourceRefs: [],
                startedAt: "2026-03-18T10:00:00Z",
                endedAt: "2026-03-18T10:00:01Z"
            )
        )

        XCTAssertEqual(turn.status, .failed)
        XCTAssertEqual(turn.learningState, .reviewed)
        XCTAssertEqual(turn.riskLevel, .critical)
        XCTAssertEqual(
            Set(turn.buildDiagnostics?.map(\.code) ?? []),
            Set([
                .missingExecutionArtifacts,
                .missingKnowledgeItemLink,
                .missingObservationRawEventLog,
                .missingObservationSourceRecord,
                .missingObservationTaskChunk,
                .missingReviewRawReference
            ])
        )
    }

    func testBuildResultRecordsStructuredDiagnosticsWithoutFailingTurnCreation() {
        let appContext = InteractionTurnAppContext(
            appName: "Safari",
            appBundleId: "com.apple.Safari"
        )
        let result = InteractionTurnBuilder.buildResult(
            InteractionTurnBuildInput(
                sessionId: "session-003",
                taskId: "task-003",
                stepId: "step-001",
                mode: .assist,
                turnKind: .taskProgression,
                stepIndex: 1,
                intentSummary: "辅助模式预测下一步。",
                actionSummary: "建议点击 Merge 按钮。",
                actionKind: .guiAction,
                appContext: appContext,
                observationRef: InteractionTurnObservationReference(
                    appContext: appContext
                ),
                stepReference: InteractionTurnStepReference(
                    stepId: "step-001",
                    stepIndex: 1,
                    instruction: "点击 Merge。"
                ),
                sourceRefs: [],
                startedAt: "2026-03-18T10:10:00Z",
                endedAt: "2026-03-18T10:10:01Z"
            )
        )

        XCTAssertEqual(result.turn.turnId, "turn-assist-taskProgression-task-003-step-001")
        XCTAssertEqual(result.turn.buildDiagnostics?.count, result.diagnostics.count)
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == .missingSemanticTargetSet }))
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == .missingObservationEvidence }))
    }
}
