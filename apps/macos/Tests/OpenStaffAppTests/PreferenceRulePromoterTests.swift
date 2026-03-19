import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceRulePromoterTests: XCTestCase {
    func testLowRiskSingleSignalStaysCandidate() throws {
        let promoter = PreferenceRulePromoter()
        let signal = makeSignal(
            signalId: "signal-low-001",
            sessionId: "session-low-001",
            timestamp: "2026-03-18T09:00:00Z"
        )

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-low-001",
                statement: "Keep browser navigation concise.",
                signals: [signal],
                riskLevel: .low,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .candidate)
        XCTAssertNil(result.rule)
        XCTAssertEqual(
            Set(result.evaluation.reasonCodes),
            Set([.insufficientSignals, .insufficientSessions])
        )
    }

    func testLowRiskPromotionRequiresThreeSignalsAcrossTwoSessionsAndConfidenceFloor() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-low-001",
                sessionId: "session-low-001",
                timestamp: "2026-03-18T09:00:00Z",
                confidence: 0.90
            ),
            makeSignal(
                signalId: "signal-low-002",
                sessionId: "session-low-001",
                timestamp: "2026-03-18T09:05:00Z",
                confidence: 0.78
            ),
            makeSignal(
                signalId: "signal-low-003",
                sessionId: "session-low-002",
                timestamp: "2026-03-18T09:10:00Z",
                confidence: 0.77,
                hint: "Prefer a new tab before opening a new window.",
                proposedAction: "prefer_new_tab"
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-low-001",
                statement: "Browser navigation should prefer tabs before windows.",
                signals: signals,
                riskLevel: .low,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .promoted)
        let rule = try XCTUnwrap(result.rule)
        XCTAssertEqual(rule.ruleId, "rule-low-001")
        XCTAssertEqual(rule.sourceSignalIds, ["signal-low-001", "signal-low-002", "signal-low-003"])
        XCTAssertEqual(rule.scope, .taskFamily("browser.navigation"))
        XCTAssertEqual(rule.hint, "Prefer a new tab before opening a new window.")
        XCTAssertEqual(rule.proposedAction, "prefer_new_tab")
        XCTAssertEqual(result.evaluation.reasonCodes, [])
        XCTAssertEqual(result.evaluation.distinctSessionCount, 2)
        XCTAssertGreaterThanOrEqual(result.evaluation.averageConfidence, 0.75)
    }

    func testMediumRiskPromotionBlocksWhenLatestSignalIsRejected() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-medium-001",
                sessionId: "session-medium-001",
                timestamp: "2026-03-18T10:00:00Z"
            ),
            makeSignal(
                signalId: "signal-medium-002",
                sessionId: "session-medium-002",
                timestamp: "2026-03-18T10:05:00Z"
            ),
            makeSignal(
                signalId: "signal-medium-003",
                sessionId: "session-medium-003",
                timestamp: "2026-03-18T10:10:00Z"
            ),
            makeSignal(
                signalId: "signal-medium-004",
                sessionId: "session-medium-004",
                timestamp: "2026-03-18T10:15:00Z"
            ),
            makeSignal(
                signalId: "signal-medium-rejected-001",
                sessionId: "session-medium-004",
                timestamp: "2026-03-18T10:20:00Z",
                promotionStatus: .rejected
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-medium-001",
                statement: "Browser navigation should prefer tabs before windows.",
                signals: signals,
                riskLevel: .medium,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .candidate)
        XCTAssertNil(result.rule)
        XCTAssertTrue(result.evaluation.reasonCodes.contains(.recentRejectedSignal))
    }

    func testHighRiskPromotionRequiresTeacherConfirmation() throws {
        let promoter = PreferenceRulePromoter()
        let signal = makeSignal(
            signalId: "signal-high-001",
            sessionId: "session-high-001",
            timestamp: "2026-03-18T11:00:00Z",
            scope: .app(bundleId: "com.apple.Terminal", appName: "Terminal"),
            proposedAction: "require_teacher_confirmation"
        )

        let blockedResult = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-high-001",
                statement: "Terminal mutations require teacher confirmation.",
                signals: [signal],
                riskLevel: .high,
                teacherConfirmed: false
            )
        )
        XCTAssertEqual(blockedResult.outcome, .candidate)
        XCTAssertTrue(blockedResult.evaluation.reasonCodes.contains(.requiresTeacherConfirmation))

        let promotedResult = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-high-001",
                statement: "Terminal mutations require teacher confirmation.",
                signals: [signal],
                riskLevel: .high,
                teacherConfirmed: true
            )
        )
        XCTAssertEqual(promotedResult.outcome, .promoted)
        XCTAssertEqual(promotedResult.rule?.teacherConfirmed, true)
    }

    func testSkillFamilyScopeStaysCandidateInDefaultV0Policy() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-skill-001",
                sessionId: "session-skill-001",
                timestamp: "2026-03-18T12:00:00Z",
                scope: .skillFamily("browser.open_tab")
            ),
            makeSignal(
                signalId: "signal-skill-002",
                sessionId: "session-skill-001",
                timestamp: "2026-03-18T12:05:00Z",
                scope: .skillFamily("browser.open_tab")
            ),
            makeSignal(
                signalId: "signal-skill-003",
                sessionId: "session-skill-002",
                timestamp: "2026-03-18T12:10:00Z",
                scope: .skillFamily("browser.open_tab")
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-skill-001",
                statement: "The open-tab skill should prefer keyboard shortcuts.",
                signals: signals,
                riskLevel: .low,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .candidate)
        XCTAssertTrue(result.evaluation.reasonCodes.contains(.scopeNotEnabledByDefault))
    }

    private func makeSignal(
        signalId: String,
        sessionId: String,
        timestamp: String,
        scope: PreferenceSignalScopeReference = .taskFamily("browser.navigation"),
        confidence: Double = 0.85,
        hint: String = "Prefer a new tab before opening a new window.",
        proposedAction: String = "prefer_new_tab",
        promotionStatus: PreferenceSignalPromotionStatus = .candidate
    ) -> PreferenceSignal {
        PreferenceSignal(
            signalId: signalId,
            turnId: "turn-\(signalId)",
            traceId: "trace-\(signalId)",
            sessionId: sessionId,
            taskId: "task-\(signalId)",
            stepId: "step-\(signalId)",
            type: .procedure,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: scope,
            hint: hint,
            confidence: confidence,
            evidenceIds: ["evidence-\(signalId)"],
            proposedAction: proposedAction,
            promotionStatus: promotionStatus,
            timestamp: timestamp
        )
    }
}
