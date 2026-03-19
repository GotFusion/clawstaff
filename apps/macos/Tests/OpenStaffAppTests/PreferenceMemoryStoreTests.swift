import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceMemoryStoreTests: XCTestCase {
    func testStorePersistsSignalsRulesProfilesAndQueriesByContext() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-memory-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(preferencesRootDirectory: preferencesRoot, fileManager: fileManager)

        let globalSignal = makeSignal(
            signalId: "signal-global-001",
            turnId: "turn-global-001",
            sessionId: "session-global-001",
            taskId: "task-global-001",
            stepId: "step-global-001",
            scope: .global(),
            timestamp: "2026-03-18T09:00:00Z",
            hint: "Keep answers concise and conclusion-first.",
            proposedAction: "shorten_review_copy"
        )
        let appSignal = makeSignal(
            signalId: "signal-app-001",
            turnId: "turn-app-001",
            sessionId: "session-app-001",
            taskId: "task-app-001",
            stepId: "step-app-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            timestamp: "2026-03-18T09:10:00Z",
            hint: "Prefer Safari for search-heavy tasks.",
            proposedAction: "prefer_safari"
        )
        let taskSignal = makeSignal(
            signalId: "signal-task-001",
            turnId: "turn-task-001",
            sessionId: "session-task-001",
            taskId: "task-task-001",
            stepId: "step-task-001",
            scope: .taskFamily("browser.navigation"),
            timestamp: "2026-03-18T09:20:00Z",
            hint: "Prefer opening a new tab before a new window.",
            proposedAction: "prefer_new_tab"
        )
        let skillSignal = makeSignal(
            signalId: "signal-skill-001",
            turnId: "turn-skill-001",
            sessionId: "session-skill-001",
            taskId: "task-skill-001",
            stepId: "step-skill-001",
            scope: .skillFamily("browser.open_tab"),
            timestamp: "2026-03-18T09:30:00Z",
            hint: "Favor keyboard shortcuts for opening tabs.",
            proposedAction: "prefer_keyboard_shortcut"
        )

        let signalURLs = try store.storeSignals([globalSignal, appSignal, taskSignal, skillSignal])
        XCTAssertEqual(signalURLs.count, 4)
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: preferencesRoot
                    .appendingPathComponent("signals/index/by-id/signal-global-001.json", isDirectory: false)
                    .path
            )
        )

        let globalRule = makeRule(
            ruleId: "rule-global-001",
            signal: globalSignal,
            statement: "Review suggestions should stay concise and conclusion-first.",
            teacherConfirmed: true
        )
        let appRule = makeRule(
            ruleId: "rule-app-001",
            signal: appSignal,
            statement: "Search-heavy tasks should default to Safari."
        )
        let taskRule = makeRule(
            ruleId: "rule-task-001",
            signal: taskSignal,
            statement: "Browser navigation should favor opening tabs before windows."
        )
        let skillRule = makeRule(
            ruleId: "rule-skill-001",
            signal: skillSignal,
            statement: "The open-tab skill should prefer keyboard shortcuts."
        )

        try store.storeRule(globalRule)
        try store.storeRule(appRule)
        try store.storeRule(taskRule)
        try store.storeRule(skillRule)

        let appRules = try store.loadRules(
            matching: PreferenceRuleQuery(appBundleId: "com.apple.Safari")
        )
        XCTAssertEqual(appRules.map(\.ruleId), ["rule-app-001", "rule-global-001"])

        let taskRules = try store.loadRules(
            matching: PreferenceRuleQuery(taskFamily: "browser.navigation")
        )
        XCTAssertEqual(taskRules.map(\.ruleId), ["rule-task-001", "rule-global-001"])

        let skillRules = try store.loadRules(
            matching: PreferenceRuleQuery(skillFamily: "browser.open_tab")
        )
        XCTAssertEqual(skillRules.map(\.ruleId), ["rule-skill-001", "rule-global-001"])

        XCTAssertTrue(
            fileManager.fileExists(
                atPath: preferencesRoot
                    .appendingPathComponent("rules/index/global/global.json", isDirectory: false)
                    .path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: preferencesRoot
                    .appendingPathComponent("rules/index/by-app/com.apple.Safari.json", isDirectory: false)
                    .path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: preferencesRoot
                    .appendingPathComponent("rules/index/by-task-family/browser.navigation.json", isDirectory: false)
                    .path
            )
        )
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: preferencesRoot
                    .appendingPathComponent("rules/index/by-skill-family/browser.open_tab.json", isDirectory: false)
                    .path
            )
        )

        let profile = PreferenceProfile(
            profileVersion: "profile-2026-03-18-001",
            activeRuleIds: [globalRule.ruleId, appRule.ruleId, taskRule.ruleId],
            assistPreferences: [PreferenceProfileDirective(rule: globalRule), PreferenceProfileDirective(rule: appRule)],
            skillPreferences: [PreferenceProfileDirective(rule: taskRule), PreferenceProfileDirective(rule: skillRule)],
            repairPreferences: [],
            reviewPreferences: [PreferenceProfileDirective(rule: globalRule)],
            plannerPreferences: [PreferenceProfileDirective(rule: taskRule)],
            generatedAt: "2026-03-18T10:00:00Z"
        )
        let snapshot = PreferenceProfileSnapshot(
            profile: profile,
            sourceRuleIds: [globalRule.ruleId, appRule.ruleId, taskRule.ruleId, skillRule.ruleId],
            createdAt: "2026-03-18T10:00:00Z",
            note: "Initial phase-11 preference snapshot."
        )

        let profileURL = try store.storeProfileSnapshot(snapshot)
        XCTAssertTrue(fileManager.fileExists(atPath: profileURL.path))

        let latestProfile = try XCTUnwrap(store.loadLatestProfileSnapshot())
        XCTAssertEqual(latestProfile.profileVersion, "profile-2026-03-18-001")
        XCTAssertEqual(latestProfile.profile.activeRuleIds, [appRule.ruleId, globalRule.ruleId, taskRule.ruleId].sorted())
        XCTAssertEqual(latestProfile.profile.totalDirectiveCount, 6)
    }

    func testStoreSupportsSignalTraceabilitySupersedeRevokeAndAuditHistory() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-memory-audit-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(preferencesRootDirectory: preferencesRoot, fileManager: fileManager)

        let oldSignal = makeSignal(
            signalId: "signal-app-old-001",
            turnId: "turn-app-old-001",
            sessionId: "session-app-old-001",
            taskId: "task-app-old-001",
            stepId: "step-app-old-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            timestamp: "2026-03-18T11:00:00Z",
            hint: "Prefer Safari as the default search app.",
            proposedAction: "prefer_safari"
        )
        let newSignal = makeSignal(
            signalId: "signal-app-new-001",
            turnId: "turn-app-new-001",
            sessionId: "session-app-new-001",
            taskId: "task-app-new-001",
            stepId: "step-app-new-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            timestamp: "2026-03-18T11:10:00Z",
            hint: "Prefer Safari except when a task explicitly requires Chrome.",
            proposedAction: "prefer_safari_with_exception"
        )
        let revocableSignal = makeSignal(
            signalId: "signal-task-revocable-001",
            turnId: "turn-task-revocable-001",
            sessionId: "session-task-revocable-001",
            taskId: "task-task-revocable-001",
            stepId: "step-task-revocable-001",
            scope: .taskFamily("browser.navigation"),
            timestamp: "2026-03-18T11:20:00Z",
            hint: "Always pin tabs after opening them.",
            proposedAction: "auto_pin_tab"
        )

        try store.storeSignals([oldSignal, newSignal, revocableSignal], actor: "system")

        let oldRule = makeRule(
            ruleId: "rule-app-old-001",
            signal: oldSignal,
            statement: "Search-heavy tasks should default to Safari."
        )
        let newRule = makeRule(
            ruleId: "rule-app-new-001",
            signal: newSignal,
            statement: "Search-heavy tasks should default to Safari unless Chrome is explicitly required."
        )
        let revocableRule = makeRule(
            ruleId: "rule-task-revocable-001",
            signal: revocableSignal,
            statement: "Browser navigation should auto-pin newly opened tabs."
        )

        try store.storeRule(oldRule, actor: "system")
        try store.storeRule(newRule, actor: "system")
        try store.storeRule(revocableRule, actor: "system")

        let sourceSignals = try store.loadSignals(for: oldRule.ruleId)
        XCTAssertEqual(sourceSignals.map(\.signalId), ["signal-app-old-001"])

        let supersededRule = try store.supersedeRule(
            ruleId: oldRule.ruleId,
            supersededByRuleId: newRule.ruleId,
            actor: "teacher",
            reason: "A newer Safari preference captured the Chrome exception.",
            timestamp: "2026-03-18T12:00:00Z"
        )
        let revokedRule = try store.revokeRule(
            ruleId: revocableRule.ruleId,
            actor: "teacher",
            reason: "Teacher no longer wants tab pinning to happen automatically.",
            timestamp: "2026-03-18T12:05:00Z"
        )

        XCTAssertEqual(supersededRule.activationStatus, .superseded)
        XCTAssertEqual(supersededRule.supersededByRuleId, "rule-app-new-001")
        XCTAssertEqual(supersededRule.lifecycleReason, "A newer Safari preference captured the Chrome exception.")

        XCTAssertEqual(revokedRule.activationStatus, .revoked)
        XCTAssertEqual(revokedRule.lifecycleReason, "Teacher no longer wants tab pinning to happen automatically.")

        let activeSafariRules = try store.loadRules(
            matching: PreferenceRuleQuery(appBundleId: "com.apple.Safari")
        )
        XCTAssertEqual(activeSafariRules.map(\.ruleId), ["rule-app-new-001"])

        let allSafariRules = try store.loadRules(
            matching: PreferenceRuleQuery(appBundleId: "com.apple.Safari", includeInactive: true)
        )
        XCTAssertEqual(allSafariRules.map(\.ruleId), ["rule-app-new-001", "rule-app-old-001"])

        let taskRules = try store.loadRules(
            matching: PreferenceRuleQuery(taskFamily: "browser.navigation", includeInactive: true)
        )
        XCTAssertEqual(taskRules.map(\.activationStatus), [.revoked])

        let auditEntries = try store.loadAuditEntries(on: "2026-03-18")
        XCTAssertGreaterThanOrEqual(auditEntries.count, 5)
        XCTAssertTrue(
            auditEntries.contains(where: {
                $0.action == .ruleStatusChanged
                    && $0.ruleId == "rule-app-old-001"
                    && $0.relatedRuleId == "rule-app-new-001"
            })
        )
        XCTAssertTrue(
            auditEntries.contains(where: {
                $0.action == .ruleStatusChanged
                    && $0.ruleId == "rule-task-revocable-001"
                    && $0.newActivationStatus == .revoked
            })
        )
    }

    func testLoadRulesUsesConflictResolverOrderingWithinSameScope() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-memory-ordering-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(preferencesRootDirectory: preferencesRoot, fileManager: fileManager)

        let lowSignal = makeSignal(
            signalId: "signal-order-low-001",
            turnId: "turn-order-low-001",
            sessionId: "session-order-low-001",
            taskId: "task-order-low-001",
            stepId: "step-order-low-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            timestamp: "2026-03-18T13:00:00Z",
            hint: "Prefer Safari for search-heavy tasks.",
            proposedAction: "prefer_safari"
        )
        let mediumSignal = makeSignal(
            signalId: "signal-order-medium-001",
            turnId: "turn-order-medium-001",
            sessionId: "session-order-medium-001",
            taskId: "task-order-medium-001",
            stepId: "step-order-medium-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            timestamp: "2026-03-18T13:00:00Z",
            hint: "Prefer Safari for search-heavy tasks.",
            proposedAction: "prefer_safari"
        )

        try store.storeSignals([lowSignal, mediumSignal])
        try store.storeRule(
            makeRule(
                ruleId: "rule-order-medium-001",
                signal: mediumSignal,
                statement: "Search-heavy tasks should default to Safari.",
                riskLevel: .medium
            )
        )
        try store.storeRule(
            makeRule(
                ruleId: "rule-order-low-001",
                signal: lowSignal,
                statement: "Search-heavy tasks should default to Safari.",
                riskLevel: .low
            )
        )

        let safariRules = try store.loadRules(
            matching: PreferenceRuleQuery(appBundleId: "com.apple.Safari")
        )

        XCTAssertEqual(safariRules.map(\.ruleId), ["rule-order-low-001", "rule-order-medium-001"])
    }

    private func makeSignal(
        signalId: String,
        turnId: String,
        sessionId: String,
        taskId: String,
        stepId: String,
        scope: PreferenceSignalScopeReference,
        timestamp: String,
        hint: String,
        proposedAction: String
    ) -> PreferenceSignal {
        PreferenceSignal(
            signalId: signalId,
            turnId: turnId,
            traceId: "trace-\(turnId)",
            sessionId: sessionId,
            taskId: taskId,
            stepId: stepId,
            type: .style,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: scope,
            hint: hint,
            confidence: 0.91,
            evidenceIds: ["evidence-\(signalId)"],
            proposedAction: proposedAction,
            promotionStatus: .confirmed,
            timestamp: timestamp
        )
    }

    private func makeRule(
        ruleId: String,
        signal: PreferenceSignal,
        statement: String,
        teacherConfirmed: Bool = false,
        riskLevel: InteractionTurnRiskLevel = .medium
    ) -> PreferenceRule {
        PreferenceRule(
            ruleId: ruleId,
            sourceSignalIds: [signal.signalId],
            scope: signal.scope,
            type: signal.type,
            polarity: signal.polarity,
            statement: statement,
            hint: signal.hint,
            proposedAction: signal.proposedAction,
            evidence: [PreferenceRuleEvidence(signal: signal)],
            riskLevel: riskLevel,
            activationStatus: .active,
            teacherConfirmed: teacherConfirmed,
            createdAt: signal.timestamp,
            updatedAt: signal.timestamp
        )
    }
}
