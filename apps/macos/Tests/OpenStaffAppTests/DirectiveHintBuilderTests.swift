import Foundation
import XCTest
@testable import OpenStaffApp

final class DirectiveHintBuilderTests: XCTestCase {
    func testBuilderFansOutLocatorSignalsToSkillMapperRepairPlannerAndReview() throws {
        let signal = PreferenceSignal(
            signalId: "signal-locator-001",
            turnId: "turn-assist-taskProgression-task-001-step-001",
            traceId: "trace-learning-assist-task-001-step-001",
            sessionId: "session-001",
            taskId: "task-001",
            stepId: "step-001",
            type: .locator,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            hint: "Refresh semantic target candidates before the next run.",
            confidence: 0.88,
            evidenceIds: ["evidence-replay-001"],
            proposedAction: "relocalize",
            promotionStatus: .candidate,
            timestamp: "2026-03-18T10:00:00Z"
        )

        let hints = DirectiveHintBuilder.build(from: signal)

        XCTAssertEqual(hints.map(\.consumer), [.skillMapper, .repairPlanner, .reviewSuggestion])
        XCTAssertEqual(Set(hints.map(\.proposedAction)), ["relocalize"])
        XCTAssertEqual(Set(hints.map(\.signalType)), [.locator])
        XCTAssertTrue(hints.allSatisfy { $0.scope.level == .app })
    }

    func testBuilderSkipsEvaluativeOnlyRejectedAndOutcomeSignals() {
        let evaluativeOnly = PreferenceSignal(
            signalId: "signal-style-001",
            turnId: "turn-001",
            sessionId: "session-001",
            taskId: "task-001",
            stepId: "step-001",
            type: .style,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .global(),
            confidence: 0.7,
            evidenceIds: ["evidence-001"],
            promotionStatus: .candidate,
            timestamp: "2026-03-18T11:00:00Z"
        )
        let rejectedDirective = PreferenceSignal(
            signalId: "signal-risk-001",
            turnId: "turn-002",
            sessionId: "session-002",
            taskId: "task-002",
            stepId: "step-001",
            type: .risk,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .taskFamily("student.execution"),
            hint: "Require teacher confirmation before similar steps.",
            confidence: 0.92,
            evidenceIds: ["evidence-002"],
            proposedAction: "require_teacher_confirmation",
            promotionStatus: .rejected,
            timestamp: "2026-03-18T11:01:00Z"
        )
        let outcomeDirective = PreferenceSignal(
            signalId: "signal-outcome-001",
            turnId: "turn-003",
            sessionId: "session-003",
            taskId: "task-003",
            stepId: "step-001",
            type: .outcome,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .global(),
            hint: "Do not use this as a directive hint.",
            confidence: 0.83,
            evidenceIds: ["evidence-003"],
            proposedAction: "ignored_outcome_action",
            promotionStatus: .candidate,
            timestamp: "2026-03-18T11:02:00Z"
        )

        let hints = DirectiveHintBuilder.build(from: [evaluativeOnly, rejectedDirective, outcomeDirective])

        XCTAssertTrue(hints.isEmpty)
    }

    func testBuilderFansOutRiskAndStyleSignalsAndDedupesSameSignalConsumerPair() {
        let risk = PreferenceSignal(
            signalId: "signal-risk-accepted-001",
            turnId: "turn-student-skillExecution-task-002-step-001",
            traceId: "trace-learning-student-task-002-step-001",
            sessionId: "session-002",
            taskId: "task-002",
            stepId: "step-001",
            type: .risk,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: .taskFamily("student.execution"),
            hint: "Keep teacher confirmation enabled for similar high-risk steps.",
            confidence: 0.95,
            evidenceIds: ["evidence-benchmark-001"],
            proposedAction: "require_teacher_confirmation",
            promotionStatus: .confirmed,
            timestamp: "2026-03-18T10:02:00Z"
        )
        let style = PreferenceSignal(
            signalId: "signal-style-accepted-001",
            turnId: "turn-assist-taskProgression-task-003-step-004",
            traceId: "trace-learning-assist-task-003-step-004",
            sessionId: "session-003",
            taskId: "task-003",
            stepId: "step-004",
            type: .style,
            evaluativeDecision: .fail,
            polarity: .discourage,
            scope: .global(),
            hint: "Keep review text concise and conclusion-first.",
            confidence: 0.79,
            evidenceIds: ["evidence-style-001"],
            proposedAction: "shorten_review_copy",
            promotionStatus: .candidate,
            timestamp: "2026-03-18T10:20:00Z"
        )

        let hints = DirectiveHintBuilder.build(from: [risk, style, risk])

        XCTAssertEqual(hints.filter { $0.signalId == risk.signalId }.count, 3)
        XCTAssertEqual(hints.filter { $0.signalId == style.signalId }.count, 3)
        XCTAssertEqual(
            Set(hints.filter { $0.signalId == risk.signalId }.map(\.consumer)),
            [.assistRerank, .skillMapper, .reviewSuggestion]
        )
        XCTAssertEqual(
            Set(hints.filter { $0.signalId == style.signalId }.map(\.consumer)),
            [.assistRerank, .skillMapper, .reviewSuggestion]
        )
    }
}
