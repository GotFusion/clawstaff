import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceRollbackServiceTests: XCTestCase {
    func testRuleRevocationPreviewAndApplyRebuildsProfile() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-rollback-rule-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let store = PreferenceMemoryStore(
            preferencesRootDirectory: workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true),
            fileManager: fileManager
        )
        let builder = PreferenceProfileBuilder()
        let service = PreferenceRollbackService(profileBuilder: builder)

        let keepSignal = makeSignal(
            signalId: "signal-keep-001",
            scope: .global(),
            type: .style,
            timestamp: "2026-03-19T09:00:00Z"
        )
        let revokeSignal = makeSignal(
            signalId: "signal-revoke-001",
            scope: .taskFamily("browser.navigation"),
            type: .procedure,
            timestamp: "2026-03-19T09:05:00Z"
        )

        try store.storeSignals([keepSignal, revokeSignal], actor: "test")
        try store.storeRule(makeRule(ruleId: "rule-keep-001", signal: keepSignal, statement: "Keep review copy concise."))
        try store.storeRule(makeRule(ruleId: "rule-revoke-001", signal: revokeSignal, statement: "Browser navigation should pin new tabs."))
        try builder.rebuildAndStore(
            using: store,
            actor: "test",
            profileVersion: "profile-before-revoke-001",
            generatedAt: "2026-03-19T09:10:00Z",
            note: "Initial active preference profile."
        )

        let preview = try service.previewRuleRevocation(
            ruleId: "rule-revoke-001",
            using: store,
            actor: "cli",
            timestamp: "2026-03-19T10:00:00Z",
            reason: "Teacher removed the tab pinning habit.",
            projectedProfileVersion: "preview-rule-revoke-001"
        )

        XCTAssertEqual(preview.operation, .ruleRevocation)
        XCTAssertEqual(preview.currentProfileVersion, "profile-before-revoke-001")
        XCTAssertEqual(preview.impactedRuleIds, ["rule-revoke-001"])
        XCTAssertEqual(preview.projectedSnapshot.profile.activeRuleIds, ["rule-keep-001"])

        let result = try service.applyRuleRevocation(
            ruleId: "rule-revoke-001",
            using: store,
            actor: "cli",
            timestamp: "2026-03-19T10:00:00Z",
            reason: "Teacher removed the tab pinning habit.",
            profileVersion: "profile-after-revoke-001"
        )

        XCTAssertEqual(result.snapshot.profileVersion, "profile-after-revoke-001")
        XCTAssertEqual(result.snapshot.profile.activeRuleIds, ["rule-keep-001"])
        XCTAssertEqual(try store.loadRule(ruleId: "rule-revoke-001")?.activationStatus, .revoked)
        XCTAssertEqual(try store.loadLatestProfileSnapshot()?.profileVersion, "profile-after-revoke-001")

        let auditEntries = try store.loadAuditEntries(
            matching: PreferenceAuditLogQuery(ruleId: "rule-revoke-001")
        )
        XCTAssertTrue(
            auditEntries.contains(where: {
                $0.action == .ruleRevoked
                    && $0.ruleId == "rule-revoke-001"
                    && $0.actor == "cli"
                    && $0.source.kind == .rollbackService
            })
        )
    }

    func testProfileRollbackReactivatesHistoricalRulesAndWritesLifecycleAudit() throws {
        let fileManager = FileManager.default
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-preference-rollback-profile-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let store = PreferenceMemoryStore(
            preferencesRootDirectory: workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true),
            fileManager: fileManager
        )
        let builder = PreferenceProfileBuilder()
        let service = PreferenceRollbackService(profileBuilder: builder)

        let oldSignal = makeSignal(
            signalId: "signal-old-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            type: .style,
            timestamp: "2026-03-19T11:00:00Z"
        )
        let newSignal = makeSignal(
            signalId: "signal-new-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            type: .style,
            timestamp: "2026-03-19T11:10:00Z"
        )

        try store.storeSignals([oldSignal, newSignal], actor: "test")
        let oldRule = makeRule(
            ruleId: "rule-old-001",
            signal: oldSignal,
            statement: "Safari tasks should keep responses concise."
        )
        let newRule = makeRule(
            ruleId: "rule-new-001",
            signal: newSignal,
            statement: "Safari tasks should include a detailed appendix."
        )

        try store.storeRule(oldRule, actor: "test")
        try builder.rebuildAndStore(
            using: store,
            actor: "test",
            profileVersion: "profile-old-001",
            generatedAt: "2026-03-19T11:05:00Z",
            note: "Older stable profile."
        )

        try store.storeRule(newRule, actor: "test")
        try store.supersedeRule(
            ruleId: oldRule.ruleId,
            supersededByRuleId: newRule.ruleId,
            actor: "teacher",
            reason: "Teacher switched to a more detailed Safari style.",
            timestamp: "2026-03-19T11:20:00Z"
        )
        try builder.rebuildAndStore(
            using: store,
            actor: "test",
            profileVersion: "profile-current-001",
            generatedAt: "2026-03-19T11:30:00Z",
            note: "Current active profile."
        )

        let preview = try service.previewProfileRollback(
            to: "profile-old-001",
            using: store,
            actor: "cli",
            timestamp: "2026-03-19T12:00:00Z",
            reason: "Restore the older concise Safari style.",
            projectedProfileVersion: "preview-profile-rollback-001"
        )

        XCTAssertEqual(preview.operation, .profileRollback)
        XCTAssertEqual(preview.currentProfileVersion, "profile-current-001")
        XCTAssertEqual(preview.targetProfileVersion, "profile-old-001")
        XCTAssertEqual(Set(preview.impactedRuleIds), Set(["rule-old-001", "rule-new-001"]))
        XCTAssertEqual(preview.projectedSnapshot.profile.activeRuleIds, ["rule-old-001"])
        XCTAssertTrue(preview.missingRuleIds.isEmpty)

        let result = try service.applyProfileRollback(
            to: "profile-old-001",
            using: store,
            actor: "cli",
            timestamp: "2026-03-19T12:00:00Z",
            reason: "Restore the older concise Safari style.",
            profileVersion: "profile-restored-001"
        )

        XCTAssertEqual(result.snapshot.profileVersion, "profile-restored-001")
        XCTAssertEqual(result.snapshot.profile.activeRuleIds, ["rule-old-001"])
        XCTAssertEqual(try store.loadRule(ruleId: "rule-old-001")?.activationStatus, .active)
        XCTAssertEqual(try store.loadRule(ruleId: "rule-new-001")?.activationStatus, .revoked)
        XCTAssertEqual(try store.loadLatestProfileSnapshot()?.profileVersion, "profile-restored-001")

        let oldRuleAudit = try store.loadAuditEntries(
            matching: PreferenceAuditLogQuery(ruleId: "rule-old-001")
        )
        XCTAssertTrue(oldRuleAudit.contains(where: { $0.action == .ruleCreated }))
        XCTAssertTrue(oldRuleAudit.contains(where: { $0.action == .ruleSuperseded }))
        XCTAssertTrue(oldRuleAudit.contains(where: { $0.action == .ruleRolledBack }))

        let rollbackAudit = try store.loadAuditEntries(
            matching: PreferenceAuditLogQuery(profileVersion: "profile-restored-001")
        )
        XCTAssertTrue(
            rollbackAudit.contains(where: {
                $0.action == .rollbackApplied
                    && $0.relatedProfileVersion == "profile-old-001"
                    && $0.actor == "cli"
            })
        )
    }

    private func makeSignal(
        signalId: String,
        scope: PreferenceSignalScopeReference,
        type: PreferenceSignalType,
        timestamp: String
    ) -> PreferenceSignal {
        PreferenceSignal(
            signalId: signalId,
            turnId: "turn-\(signalId)",
            traceId: "trace-\(signalId)",
            sessionId: "session-\(signalId)",
            taskId: "task-\(signalId)",
            stepId: "step-\(signalId)",
            type: type,
            evaluativeDecision: .pass,
            polarity: .reinforce,
            scope: scope,
            hint: "Hint for \(signalId).",
            confidence: 0.92,
            evidenceIds: ["evidence-\(signalId)"],
            proposedAction: "apply-\(signalId)",
            promotionStatus: .confirmed,
            timestamp: timestamp
        )
    }

    private func makeRule(
        ruleId: String,
        signal: PreferenceSignal,
        statement: String
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
            riskLevel: .medium,
            activationStatus: .active,
            teacherConfirmed: false,
            createdAt: signal.timestamp,
            updatedAt: signal.timestamp
        )
    }
}
