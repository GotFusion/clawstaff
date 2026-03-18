import Foundation
import XCTest
@testable import OpenStaffApp

final class TurnLearningEligibilityTests: XCTestCase {
    func testTeachingTaskProgressionIsEligible() {
        let turn = makeTurn()

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, .eligible)
        XCTAssertEqual(eligibility.reasonCode, .mainlineTaskProgression)
        XCTAssertTrue(eligibility.isEligible)
    }

    func testStudentSkillExecutionIsEligible() {
        let turn = makeTurn(
            mode: .student,
            turnKind: .skillExecution,
            status: .succeeded,
            execution: InteractionTurnExecutionLink(
                traceId: "trace-student-001",
                component: "student.openclaw.runner.step",
                status: "succeeded"
            )
        )

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, .eligible)
        XCTAssertEqual(eligibility.reasonCode, .mainlineSkillExecution)
    }

    func testRepairTurnIsEligible() {
        let turn = makeTurn(
            turnKind: .repair,
            review: InteractionTurnReviewLink(
                reviewId: "feedback-001",
                source: "teacherReview",
                decision: TeacherQuickFeedbackAction.fixLocator.rawValue,
                summary: "老师要求修正 locator。",
                reviewedAt: "2026-03-18T10:05:00Z"
            )
        )

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, .eligible)
        XCTAssertEqual(eligibility.reasonCode, .mainlineRepair)
    }

    func testPrivacyExcludedTurnIsIneligible() {
        let turn = makeTurn(privacyTags: ["sensitive-excluded"])

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, .ineligible)
        XCTAssertEqual(eligibility.reasonCode, .privacyExcluded)
    }

    func testAssistPredictionWithoutConfirmationNeedsReview() {
        let turn = makeTurn(
            mode: .assist,
            observationRef: InteractionTurnObservationReference(
                eventIds: ["evt-001"],
                appContext: defaultAppContext,
                note: "Predicted suggestion has not been confirmed yet."
            ),
            review: nil,
            execution: nil
        )

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, TurnLearningEligibilityStatus.needsReview)
        XCTAssertEqual(eligibility.reasonCode, TurnLearningEligibilityReasonCode.assistPredictionOnly)
    }

    func testLogOnlyTurnIsIneligible() {
        let turn = makeTurn(
            intentSummary: "保留本轮 student review 的日志摘要。",
            actionSummary: "Log mirror for diagnostics.",
            observationRef: InteractionTurnObservationReference(
                appContext: defaultAppContext,
                note: "Log mirror for diagnostics."
            ),
            stepReference: InteractionTurnStepReference(
                stepId: "step-001",
                stepIndex: 1,
                instruction: "日志摘要：记录本轮 student review。"
            ),
            sourceRefs: [
                InteractionTurnSourceReference(
                    artifactKind: "studentLog",
                    path: "data/logs/session-001.log"
                ),
                InteractionTurnSourceReference(
                    artifactKind: "teacherFeedback",
                    path: "data/feedback/session-001.jsonl"
                )
            ]
        )

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, TurnLearningEligibilityStatus.ineligible)
        XCTAssertEqual(eligibility.reasonCode, TurnLearningEligibilityReasonCode.logOnly)
    }

    func testStatusOnlyTurnIsIneligible() {
        let turn = makeTurn(
            intentSummary: "系统状态播报当前辅助模式状态。",
            actionSummary: "状态播报：辅助模式保持稳定。",
            observationRef: InteractionTurnObservationReference(appContext: defaultAppContext),
            stepReference: InteractionTurnStepReference(
                stepId: "step-001",
                stepIndex: 1,
                instruction: "系统状态播报：辅助模式保持稳定。"
            ),
            sourceRefs: []
        )

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, TurnLearningEligibilityStatus.ineligible)
        XCTAssertEqual(eligibility.reasonCode, TurnLearningEligibilityReasonCode.statusOnly)
    }

    func testSyntheticFixtureIsIneligible() {
        let turn = makeTurn(
            observationRef: InteractionTurnObservationReference(
                eventIds: ["evt-001"],
                appContext: defaultAppContext,
                note: "Synthetic example for assist mode until real assist history is frozen into the repository."
            ),
            sourceRefs: [
                InteractionTurnSourceReference(
                    artifactKind: "exampleFixture",
                    path: "core/learning/examples/interaction-turns/assist-suggestion-sample.json"
                )
            ]
        )

        let eligibility = TurnLearningEligibility.classify(turn)

        XCTAssertEqual(eligibility.status, TurnLearningEligibilityStatus.ineligible)
        XCTAssertEqual(eligibility.reasonCode, TurnLearningEligibilityReasonCode.syntheticFixture)
    }

    func testHistoricalMainlineTurnsStayEligibleAcrossFiftySamples() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let turnsRoot = repoRoot.appendingPathComponent("data/learning/turns", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: turnsRoot,
            includingPropertiesForKeys: nil
        )

        var urls: [URL] = []
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.pathExtension == "json" {
                urls.append(candidate)
            }
        }

        XCTAssertGreaterThanOrEqual(urls.count, 50)

        let decoder = JSONDecoder()
        for url in urls.sorted(by: { $0.path < $1.path }).prefix(50) {
            let turn = try decoder.decode(
                InteractionTurn.self,
                from: sanitizedInteractionTurnData(from: url)
            )
            let eligibility = TurnLearningEligibility.classify(turn)
            XCTAssertEqual(
                eligibility.status,
                .eligible,
                "expected historical turn to stay eligible: \(url.lastPathComponent)"
            )
        }
    }

    private func makeTurn(
        mode: OpenStaffMode = .teaching,
        turnKind: InteractionTurnKind = .taskProgression,
        status: InteractionTurnStatus = .captured,
        intentSummary: String = "在 Xcode 中保存当前文件。",
        actionSummary: String = "点击 Save 按钮。",
        observationRef: InteractionTurnObservationReference? = nil,
        stepReference: InteractionTurnStepReference? = nil,
        review: InteractionTurnReviewLink? = nil,
        execution: InteractionTurnExecutionLink? = nil,
        sourceRefs: [InteractionTurnSourceReference]? = nil,
        privacyTags: [String] = []
    ) -> InteractionTurn {
        let observationRef = observationRef ?? InteractionTurnObservationReference(
            rawEventLogPath: "data/raw-events/2026-03-18/session-001.jsonl",
            taskChunkPath: "data/task-chunks/2026-03-18/task-001.json",
            eventIds: ["evt-001"],
            appContext: defaultAppContext
        )
        let stepReference = stepReference ?? InteractionTurnStepReference(
            stepId: "step-001",
            stepIndex: 1,
            instruction: "点击 Save 按钮。",
            knowledgeItemId: "ki-task-001",
            knowledgeStepId: "step-001",
            sourceEventIds: ["evt-001"]
        )
        let sourceRefs = sourceRefs ?? [
            InteractionTurnSourceReference(
                artifactKind: "knowledgeItem",
                path: "data/knowledge/2026-03-18/task-001.json",
                identifier: "ki-task-001"
            )
        ]

        return InteractionTurn(
            turnId: "turn-\(mode.rawValue)-\(turnKind.rawValue)-task-001-step-001",
            traceId: "trace-learning-\(mode.rawValue)-task-001-step-001",
            sessionId: "session-001",
            taskId: "task-001",
            stepId: "step-001",
            mode: mode,
            turnKind: turnKind,
            stepIndex: 1,
            intentSummary: intentSummary,
            actionSummary: actionSummary,
            actionKind: .guiAction,
            status: status,
            learningState: review == nil ? .linked : .reviewed,
            privacyTags: privacyTags,
            riskLevel: .low,
            appContext: defaultAppContext,
            observationRef: observationRef,
            semanticTargetSetRef: nil,
            stepReference: stepReference,
            execution: execution,
            review: review,
            sourceRefs: sourceRefs,
            startedAt: "2026-03-18T10:00:00Z",
            endedAt: "2026-03-18T10:00:01Z"
        )
    }

    private var defaultAppContext: InteractionTurnAppContext {
        InteractionTurnAppContext(
            appName: "Xcode",
            appBundleId: "com.apple.dt.Xcode",
            windowTitle: "Package.swift"
        )
    }

    private func sanitizedInteractionTurnData(from url: URL) throws -> Data {
        let rawData = try Data(contentsOf: url)
        guard var payload = try JSONSerialization.jsonObject(with: rawData) as? [String: Any] else {
            return rawData
        }

        payload.removeValue(forKey: "semanticTargetSetRef")
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
