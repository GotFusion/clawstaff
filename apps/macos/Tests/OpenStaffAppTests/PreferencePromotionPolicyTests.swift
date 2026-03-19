import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferencePromotionPolicyTests: XCTestCase {
    func testPolicyLoadsFromEnvironmentOverride() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let policyURL = temporaryDirectory.appendingPathComponent("preference-governance.json", isDirectory: false)
        let payload = """
        {
          "schemaVersion": "openstaff.learning.preference-governance.v-test",
          "enabledScopeLevels": ["app"],
          "conflictPriority": ["lowerRisk", "moreSpecificScope"],
          "riskPolicies": {
            "low": {
              "promotionThreshold": {
                "minimumSignalCount": 2,
                "minimumSessionCount": 1,
                "minimumAverageConfidence": 0.5,
                "requiresTeacherConfirmation": false,
                "requiresNoRecentRejection": false,
                "allowAutomaticPromotion": true
              },
              "autoExecutionPolicy": "inheritSafetyInterlocks"
            },
            "medium": {
              "promotionThreshold": {
                "minimumSignalCount": 2,
                "minimumSessionCount": 1,
                "minimumAverageConfidence": null,
                "requiresTeacherConfirmation": false,
                "requiresNoRecentRejection": false,
                "allowAutomaticPromotion": true
              },
              "autoExecutionPolicy": "disabled"
            },
            "high": {
              "promotionThreshold": {
                "minimumSignalCount": 1,
                "minimumSessionCount": 1,
                "minimumAverageConfidence": null,
                "requiresTeacherConfirmation": true,
                "requiresNoRecentRejection": true,
                "allowAutomaticPromotion": true
              },
              "autoExecutionPolicy": "requiresTeacherConfirmation"
            },
            "critical": {
              "promotionThreshold": {
                "minimumSignalCount": 1,
                "minimumSessionCount": 1,
                "minimumAverageConfidence": null,
                "requiresTeacherConfirmation": true,
                "requiresNoRecentRejection": true,
                "allowAutomaticPromotion": false
              },
              "autoExecutionPolicy": "disabled"
            }
          },
          "signalTypePolicies": {
            "outcome": {"allowedScopeLevels": ["app"], "expiresAfterDays": 7, "notes": []},
            "procedure": {"allowedScopeLevels": ["app"], "expiresAfterDays": 14, "notes": []},
            "locator": {"allowedScopeLevels": ["app"], "expiresAfterDays": 21, "notes": []},
            "style": {"allowedScopeLevels": ["app"], "expiresAfterDays": null, "notes": []},
            "risk": {"allowedScopeLevels": ["app"], "expiresAfterDays": null, "notes": []},
            "repair": {"allowedScopeLevels": ["app"], "expiresAfterDays": 30, "notes": []}
          }
        }
        """
        try Data(payload.utf8).write(to: policyURL)

        let loaded = PreferencePromotionPolicy.loadDefaultOrFallback(
            environment: ["OPENSTAFF_PREFERENCE_GOVERNANCE_PATH": policyURL.path]
        )

        XCTAssertEqual(loaded.schemaVersion, "openstaff.learning.preference-governance.v-test")
        XCTAssertEqual(loaded.enabledScopeLevels, [.app])
        XCTAssertEqual(loaded.conflictPriority.prefix(2), [.lowerRisk, .moreSpecificScope])
        XCTAssertEqual(loaded.signalTypePolicies.locator.expiresAfterDays, 21)
    }

    func testConflictResolverCanUseConfiguredPriorityOrder() {
        let resolver = PreferenceConflictResolver(
            priorityOrder: [
                .lowerRisk,
                .moreSpecificScope,
                .recentTeacherConfirmation,
                .moreRecentlyUpdated,
                .stableRuleIdTieBreak
            ]
        )
        let globalLowRiskRule = makeRule(
            ruleId: "rule-global-low-001",
            scope: .global(),
            updatedAt: "2026-03-18T16:00:00Z",
            riskLevel: .low
        )
        let taskHighRiskRule = makeRule(
            ruleId: "rule-task-high-001",
            scope: .taskFamily("browser.navigation"),
            updatedAt: "2026-03-18T16:00:00Z",
            riskLevel: .high
        )

        let explanation = resolver.explainConflict(between: globalLowRiskRule, and: taskHighRiskRule)

        XCTAssertEqual(explanation.winnerRuleId, "rule-global-low-001")
        XCTAssertTrue(explanation.reasonCodes.contains(.lowerRisk))
    }

    private func makeRule(
        ruleId: String,
        scope: PreferenceSignalScopeReference,
        updatedAt: String,
        riskLevel: InteractionTurnRiskLevel
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
            confidence: 0.9,
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
            teacherConfirmed: false,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
