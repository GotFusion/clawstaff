import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceProfileBuilderTests: XCTestCase {
    func testBuilderAggregatesActiveRulesIntoModuleSpecificDirectives() {
        let builder = PreferenceProfileBuilder()
        let rules = [
            makeRule(
                ruleId: "rule-global-style-001",
                scope: .global(),
                type: .style,
                updatedAt: "2026-03-19T09:00:00Z"
            ),
            makeRule(
                ruleId: "rule-app-procedure-001",
                scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                type: .procedure,
                updatedAt: "2026-03-19T09:05:00Z"
            ),
            makeRule(
                ruleId: "rule-task-risk-001",
                scope: .taskFamily("browser.navigation"),
                type: .risk,
                updatedAt: "2026-03-19T09:10:00Z"
            ),
            makeRule(
                ruleId: "rule-skill-repair-001",
                scope: .skillFamily("browser.open_tab"),
                type: .repair,
                updatedAt: "2026-03-19T09:15:00Z"
            ),
            makeRule(
                ruleId: "rule-window-locator-001",
                scope: .windowPattern("Find", appBundleId: "com.apple.Safari", appName: "Safari"),
                type: .locator,
                updatedAt: "2026-03-19T09:20:00Z"
            ),
            makeRule(
                ruleId: "rule-global-outcome-001",
                scope: .global(),
                type: .outcome,
                updatedAt: "2026-03-19T09:25:00Z"
            )
        ]

        let result = builder.build(
            from: rules,
            profileVersion: "profile-2026-03-19-001",
            generatedAt: "2026-03-19T10:00:00Z",
            previousProfileVersion: "profile-2026-03-18-001",
            note: "Phase 11.3 profile assembly test."
        )

        XCTAssertEqual(
            result.profile.activeRuleIds,
            [
                "rule-app-procedure-001",
                "rule-global-outcome-001",
                "rule-global-style-001",
                "rule-skill-repair-001",
                "rule-task-risk-001",
                "rule-window-locator-001"
            ]
        )
        XCTAssertEqual(
            result.profile.assistPreferences.map(\.ruleId),
            ["rule-task-risk-001", "rule-app-procedure-001", "rule-global-style-001"]
        )
        XCTAssertEqual(
            result.profile.skillPreferences.map(\.ruleId),
            ["rule-window-locator-001", "rule-task-risk-001", "rule-app-procedure-001", "rule-global-style-001"]
        )
        XCTAssertEqual(
            result.profile.repairPreferences.map(\.ruleId),
            ["rule-window-locator-001", "rule-skill-repair-001"]
        )
        XCTAssertEqual(
            result.profile.reviewPreferences.map(\.ruleId),
            [
                "rule-window-locator-001",
                "rule-skill-repair-001",
                "rule-task-risk-001",
                "rule-app-procedure-001",
                "rule-global-outcome-001",
                "rule-global-style-001"
            ]
        )
        XCTAssertEqual(
            result.profile.plannerPreferences.map(\.ruleId),
            ["rule-skill-repair-001", "rule-task-risk-001", "rule-app-procedure-001"]
        )
        XCTAssertEqual(result.snapshot.sourceRuleIds, result.profile.activeRuleIds)
        XCTAssertEqual(result.snapshot.previousProfileVersion, "profile-2026-03-18-001")
        XCTAssertEqual(result.snapshot.note, "Phase 11.3 profile assembly test.")
        XCTAssertEqual(result.profile.totalDirectiveCount, 18)
        XCTAssertEqual(result.moduleSummaries.map { $0.module.rawValue }, ["assist", "skill", "repair", "review", "planner"])
        XCTAssertEqual(result.moduleSummaries.map(\.directiveCount), [3, 4, 2, 6, 3])
    }

    func testRebuildUsesStoreActiveRulesAndLinksPreviousProfileVersion() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-profile-builder-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let store = PreferenceMemoryStore(
            preferencesRootDirectory: workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true),
            fileManager: fileManager
        )

        let activeRule = makeRule(
            ruleId: "rule-active-procedure-001",
            scope: .app(bundleId: "com.apple.TextEdit", appName: "TextEdit"),
            type: .procedure,
            updatedAt: "2026-03-19T11:00:00Z"
        )
        let revokedRule = makeRule(
            ruleId: "rule-revoked-style-001",
            scope: .global(),
            type: .style,
            updatedAt: "2026-03-19T11:05:00Z",
            activationStatus: .revoked
        )

        try store.storeRule(activeRule)
        try store.storeRule(revokedRule)
        try store.storeProfileSnapshot(
            PreferenceProfileSnapshot(
                profile: PreferenceProfile(
                    profileVersion: "profile-previous-001",
                    activeRuleIds: [activeRule.ruleId],
                    assistPreferences: [PreferenceProfileDirective(rule: activeRule)],
                    skillPreferences: [PreferenceProfileDirective(rule: activeRule)],
                    repairPreferences: [],
                    reviewPreferences: [PreferenceProfileDirective(rule: activeRule)],
                    plannerPreferences: [PreferenceProfileDirective(rule: activeRule)],
                    generatedAt: "2026-03-19T11:10:00Z"
                ),
                sourceRuleIds: [activeRule.ruleId],
                createdAt: "2026-03-19T11:10:00Z"
            )
        )

        let builder = PreferenceProfileBuilder()
        let result = try builder.rebuild(
            using: store,
            profileVersion: "profile-current-001",
            generatedAt: "2026-03-19T11:20:00Z",
            note: "Rebuilt from current active rules."
        )

        XCTAssertEqual(result.profile.activeRuleIds, ["rule-active-procedure-001"])
        XCTAssertEqual(result.snapshot.previousProfileVersion, "profile-previous-001")
        XCTAssertEqual(result.profile.assistPreferences.map(\.ruleId), ["rule-active-procedure-001"])
        XCTAssertEqual(result.profile.skillPreferences.map(\.ruleId), ["rule-active-procedure-001"])
        XCTAssertEqual(result.profile.reviewPreferences.map(\.ruleId), ["rule-active-procedure-001"])
        XCTAssertEqual(result.profile.plannerPreferences.map(\.ruleId), ["rule-active-procedure-001"])
        XCTAssertTrue(result.profile.repairPreferences.isEmpty)
    }

    private func makeRule(
        ruleId: String,
        scope: PreferenceSignalScopeReference,
        type: PreferenceSignalType,
        updatedAt: String,
        activationStatus: PreferenceRuleActivationStatus = .active
    ) -> PreferenceRule {
        let signal = PreferenceSignal(
            signalId: "signal-\(ruleId)",
            turnId: "turn-\(ruleId)",
            traceId: "trace-\(ruleId)",
            sessionId: "session-\(ruleId)",
            taskId: "task-\(ruleId)",
            stepId: "step-\(ruleId)",
            type: type,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: scope,
            hint: "Preferred behavior for \(ruleId).",
            confidence: 0.9,
            evidenceIds: ["evidence-\(ruleId)"],
            proposedAction: "apply_\(ruleId)",
            promotionStatus: .confirmed,
            timestamp: updatedAt
        )

        return PreferenceRule(
            ruleId: ruleId,
            sourceSignalIds: [signal.signalId],
            scope: scope,
            type: signal.type,
            polarity: signal.polarity,
            statement: "Preference statement for \(ruleId).",
            hint: signal.hint,
            proposedAction: signal.proposedAction,
            evidence: [PreferenceRuleEvidence(signal: signal)],
            riskLevel: .medium,
            activationStatus: activationStatus,
            teacherConfirmed: false,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
