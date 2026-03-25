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
        XCTAssertEqual(rule.governance?.autoExecutionPolicy, .inheritSafetyInterlocks)
        XCTAssertEqual(rule.governance?.expiresAfterDays, 90)
        XCTAssertEqual(rule.governance?.expiresAt, "2026-06-16T09:10:00Z")
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
        XCTAssertEqual(promotedResult.rule?.governance?.autoExecutionPolicy, .requiresTeacherConfirmation)
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

    func testProcedureRuleCannotPromoteFromGlobalScope() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-global-001",
                sessionId: "session-global-001",
                timestamp: "2026-03-18T13:00:00Z",
                scope: .global()
            ),
            makeSignal(
                signalId: "signal-global-002",
                sessionId: "session-global-001",
                timestamp: "2026-03-18T13:05:00Z",
                scope: .global()
            ),
            makeSignal(
                signalId: "signal-global-003",
                sessionId: "session-global-002",
                timestamp: "2026-03-18T13:10:00Z",
                scope: .global()
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-global-001",
                statement: "All workflows should prefer tabs before windows.",
                signals: signals,
                riskLevel: .low,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .candidate)
        XCTAssertNil(result.rule)
        XCTAssertTrue(result.evaluation.reasonCodes.contains(.scopeNotAllowedByGovernance))
        XCTAssertEqual(
            result.evaluation.governanceDecision.governance.allowedScopeLevels,
            [.app, .skillFamily, .taskFamily]
        )
    }

    func testLocatorRuleCarriesGovernanceExpirationMetadata() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-locator-001",
                sessionId: "session-locator-001",
                timestamp: "2026-03-18T14:00:00Z",
                scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                type: .locator
            ),
            makeSignal(
                signalId: "signal-locator-002",
                sessionId: "session-locator-001",
                timestamp: "2026-03-18T14:05:00Z",
                scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                type: .locator
            ),
            makeSignal(
                signalId: "signal-locator-003",
                sessionId: "session-locator-002",
                timestamp: "2026-03-18T14:10:00Z",
                scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                type: .locator
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-locator-001",
                statement: "Safari locator rules should stay close to the browser context.",
                signals: signals,
                riskLevel: .low,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .promoted)
        XCTAssertEqual(result.rule?.governance?.expiresAfterDays, 30)
        XCTAssertEqual(result.rule?.governance?.expiresAt, "2026-04-17T14:10:00Z")
    }

    func testMediumRiskPromotionKeepsRuleActiveButDisablesAutoExecution() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-medium-governance-001",
                sessionId: "session-medium-governance-001",
                timestamp: "2026-03-18T15:00:00Z",
                type: .risk
            ),
            makeSignal(
                signalId: "signal-medium-governance-002",
                sessionId: "session-medium-governance-002",
                timestamp: "2026-03-18T15:05:00Z",
                type: .risk
            ),
            makeSignal(
                signalId: "signal-medium-governance-003",
                sessionId: "session-medium-governance-003",
                timestamp: "2026-03-18T15:10:00Z",
                type: .risk
            ),
            makeSignal(
                signalId: "signal-medium-governance-004",
                sessionId: "session-medium-governance-004",
                timestamp: "2026-03-18T15:15:00Z",
                type: .risk
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-medium-governance-001",
                statement: "Risky steps should still require explicit review before auto execution.",
                signals: signals,
                riskLevel: .medium,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .promoted)
        XCTAssertEqual(result.rule?.governance?.autoExecutionPolicy, .disabled)
    }

    func testLowRiskPromotionDoesNotDoubleCountDuplicateSignalsFromSameTurn() throws {
        let promoter = PreferenceRulePromoter()
        let signals = [
            makeSignal(
                signalId: "signal-duplicate-001",
                turnId: "turn-duplicate-001",
                sessionId: "session-duplicate-001",
                timestamp: "2026-03-18T16:00:00Z",
                confidence: 0.90
            ),
            makeSignal(
                signalId: "signal-duplicate-002",
                turnId: "turn-duplicate-001",
                sessionId: "session-duplicate-001",
                timestamp: "2026-03-18T16:00:10Z",
                confidence: 0.91
            ),
            makeSignal(
                signalId: "signal-duplicate-003",
                turnId: "turn-duplicate-003",
                sessionId: "session-duplicate-002",
                timestamp: "2026-03-18T16:05:00Z",
                confidence: 0.92
            )
        ]

        let result = try promoter.promote(
            PreferenceRulePromotionDraft(
                ruleId: "rule-duplicate-001",
                statement: "Browser navigation should prefer tabs before windows.",
                signals: signals,
                riskLevel: .low,
                teacherConfirmed: false
            )
        )

        XCTAssertEqual(result.outcome, .candidate)
        XCTAssertTrue(result.evaluation.reasonCodes.contains(.insufficientSignals))
        XCTAssertEqual(result.evaluation.distinctSessionCount, 2)
    }

    private func makeSignal(
        signalId: String,
        turnId: String? = nil,
        sessionId: String,
        timestamp: String,
        scope: PreferenceSignalScopeReference = .taskFamily("browser.navigation"),
        type: PreferenceSignalType = .procedure,
        confidence: Double = 0.85,
        hint: String = "Prefer a new tab before opening a new window.",
        proposedAction: String = "prefer_new_tab",
        promotionStatus: PreferenceSignalPromotionStatus = .candidate
    ) -> PreferenceSignal {
        PreferenceSignal(
            signalId: signalId,
            turnId: turnId ?? "turn-\(signalId)",
            traceId: "trace-\(turnId ?? signalId)",
            sessionId: sessionId,
            taskId: "task-\(signalId)",
            stepId: "step-\(signalId)",
            type: type,
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
