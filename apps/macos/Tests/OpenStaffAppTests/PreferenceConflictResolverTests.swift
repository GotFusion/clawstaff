import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceConflictResolverTests: XCTestCase {
    func testResolverPrefersMoreSpecificScopeBeforeBroaderRule() {
        let resolver = PreferenceConflictResolver()
        let globalRule = makeRule(
            ruleId: "rule-global-001",
            scope: .global(),
            updatedAt: "2026-03-18T09:00:00Z",
            riskLevel: .low
        )
        let taskRule = makeRule(
            ruleId: "rule-task-001",
            scope: .taskFamily("browser.navigation"),
            updatedAt: "2026-03-18T09:00:00Z",
            riskLevel: .high
        )

        let resolution = resolver.resolve([globalRule, taskRule])

        XCTAssertEqual(resolution.orderedRules.map(\.ruleId), ["rule-task-001", "rule-global-001"])
        XCTAssertEqual(resolution.winningRuleId, "rule-task-001")
        XCTAssertTrue(
            resolution.overrideExplanations.contains(where: {
                $0.winnerRuleId == "rule-task-001"
                    && $0.loserRuleId == "rule-global-001"
                    && $0.reasonCodes.contains(.moreSpecificScope)
            })
        )
    }

    func testResolverPrefersMoreRecentTeacherConfirmationWithinSameScope() {
        let resolver = PreferenceConflictResolver()
        let olderConfirmed = makeRule(
            ruleId: "rule-task-older-001",
            scope: .taskFamily("browser.navigation"),
            updatedAt: "2026-03-18T09:00:00Z",
            riskLevel: .medium,
            teacherConfirmed: true
        )
        let newerConfirmed = makeRule(
            ruleId: "rule-task-newer-001",
            scope: .taskFamily("browser.navigation"),
            updatedAt: "2026-03-18T09:05:00Z",
            riskLevel: .medium,
            teacherConfirmed: true
        )

        let explanation = resolver.explainConflict(between: olderConfirmed, and: newerConfirmed)

        XCTAssertEqual(explanation.winnerRuleId, "rule-task-newer-001")
        XCTAssertEqual(explanation.loserRuleId, "rule-task-older-001")
        XCTAssertTrue(explanation.reasonCodes.contains(.recentTeacherConfirmation))
    }

    func testResolverFallsBackToLowerRiskWhenScopeAndConfirmationTie() {
        let resolver = PreferenceConflictResolver()
        let mediumRiskRule = makeRule(
            ruleId: "rule-app-medium-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            updatedAt: "2026-03-18T09:00:00Z",
            riskLevel: .medium
        )
        let lowRiskRule = makeRule(
            ruleId: "rule-app-low-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            updatedAt: "2026-03-18T09:00:00Z",
            riskLevel: .low
        )

        let explanation = resolver.explainConflict(between: mediumRiskRule, and: lowRiskRule)

        XCTAssertEqual(explanation.winnerRuleId, "rule-app-low-001")
        XCTAssertTrue(explanation.reasonCodes.contains(.lowerRisk))
    }

    private func makeRule(
        ruleId: String,
        scope: PreferenceSignalScopeReference,
        updatedAt: String,
        riskLevel: InteractionTurnRiskLevel,
        teacherConfirmed: Bool = false
    ) -> PreferenceRule {
        let signal = PreferenceSignal(
            signalId: "signal-\(ruleId)",
            turnId: "turn-\(ruleId)",
            traceId: "trace-\(ruleId)",
            sessionId: "session-\(ruleId)",
            taskId: "task-\(ruleId)",
            stepId: "step-\(ruleId)",
            type: .procedure,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: scope,
            hint: "Keep the preferred behavior.",
            confidence: 0.88,
            evidenceIds: ["evidence-\(ruleId)"],
            proposedAction: "apply_preference",
            promotionStatus: .confirmed,
            timestamp: updatedAt
        )

        return PreferenceRule(
            ruleId: ruleId,
            sourceSignalIds: [signal.signalId],
            scope: scope,
            type: signal.type,
            polarity: signal.polarity,
            statement: "Preferred behavior for \(ruleId).",
            hint: signal.hint,
            proposedAction: signal.proposedAction,
            evidence: [PreferenceRuleEvidence(signal: signal)],
            riskLevel: riskLevel,
            activationStatus: .active,
            teacherConfirmed: teacherConfirmed,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
