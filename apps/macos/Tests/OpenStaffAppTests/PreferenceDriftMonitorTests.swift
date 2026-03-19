import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceDriftMonitorTests: XCTestCase {
    func testMonitorFlagsStaleOverrideTeacherRejectionAndStyleShift() throws {
        let fileManager = FileManager.default
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("openstaff-preference-drift-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(
            preferencesRootDirectory: preferencesRoot,
            fileManager: fileManager
        )
        let builder = PreferenceProfileBuilder()
        let decisionStore = PolicyAssemblyDecisionStore(
            preferencesRootDirectory: preferencesRoot,
            fileManager: fileManager
        )

        let staleSignal = makeSignal(
            signalId: "signal-stale-001",
            scope: .global(),
            type: .style,
            timestamp: "2026-01-10T09:00:00Z"
        )
        let highRiskSignal = makeSignal(
            signalId: "signal-high-risk-001",
            scope: .taskFamily("browser.navigation"),
            type: .risk,
            timestamp: "2026-03-01T09:00:00Z"
        )
        let styleSignal = makeSignal(
            signalId: "signal-style-active-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            type: .style,
            timestamp: "2026-03-05T09:00:00Z"
        )
        let siblingStyleSignal = makeSignal(
            signalId: "signal-style-sibling-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            type: .style,
            timestamp: "2026-03-18T09:00:00Z"
        )

        try store.storeSignals([staleSignal, highRiskSignal, styleSignal, siblingStyleSignal], actor: "test")

        try store.storeRule(
            makeRule(
                ruleId: "rule-stale-001",
                signal: staleSignal,
                statement: "Keep replies concise.",
                riskLevel: .low,
                activationStatus: .active
            ),
            actor: "test"
        )
        try store.storeRule(
            makeRule(
                ruleId: "rule-high-risk-001",
                signal: highRiskSignal,
                statement: "Browser mutations should remain confirmation-gated.",
                riskLevel: .high,
                activationStatus: .active
            ),
            actor: "test"
        )
        try store.storeRule(
            makeRule(
                ruleId: "rule-style-active-001",
                signal: styleSignal,
                statement: "Safari answers should stay concise.",
                riskLevel: .low,
                activationStatus: .active
            ),
            actor: "test"
        )
        try store.storeRule(
            makeRule(
                ruleId: "rule-style-sibling-001",
                signal: siblingStyleSignal,
                statement: "Safari answers should include a detailed appendix.",
                riskLevel: .low,
                activationStatus: .revoked
            ),
            actor: "teacher",
            auditContext: PreferenceRuleAuditContext(
                action: .ruleRevoked,
                source: .teacherAction(
                    referenceId: "review-style-001",
                    summary: "Teacher switched to a different Safari writing style."
                )
            ),
            note: "Teacher switched to a different Safari writing style."
        )

        try builder.rebuildAndStore(
            using: store,
            actor: "test",
            profileVersion: "profile-current-001",
            generatedAt: "2026-03-19T09:30:00Z",
            note: "Current active profile for drift monitoring."
        )

        for index in 0..<10 {
            let timestamp = String(
                format: "2026-03-%02dT10:00:00Z",
                10 + index
            )
            let suppressed = index < 6
            let decision = PolicyAssemblyDecision(
                decisionId: "decision-high-risk-\(index)",
                targetModule: .assist,
                inputRef: PolicyAssemblyInputReference(
                    traceId: "trace-high-risk-\(index)",
                    sessionId: "session-high-risk-\(index)",
                    taskId: "task-high-risk-\(index)"
                ),
                profileVersion: "profile-current-001",
                strategyVersion: "preference-aware-retrieval-v1",
                appliedRuleIds: suppressed ? [] : ["rule-high-risk-001"],
                suppressedRuleIds: suppressed ? ["rule-high-risk-001"] : [],
                finalDecisionSummary: suppressed
                    ? "High-risk rule was overridden by a newer path."
                    : "High-risk rule remained active.",
                ruleEvaluations: [
                    PolicyAssemblyRuleEvaluation(
                        ruleId: "rule-high-risk-001",
                        disposition: suppressed ? .suppressed : .applied,
                        delta: suppressed ? -0.2 : 0.3,
                        explanation: suppressed
                            ? "Rule was suppressed by a competing candidate."
                            : "Rule matched the current action."
                    )
                ],
                finalWeights: [],
                timestamp: timestamp
            )
            try decisionStore.store(decision)
        }

        for index in 0..<3 {
            try store.auditLogStore.append(
                PreferenceAuditLogEntry(
                    auditId: "audit-style-reject-\(index)",
                    action: .ruleUpdated,
                    timestamp: String(format: "2026-03-1%dT11:00:00Z", index + 6),
                    actor: "teacher",
                    source: .teacherAction(
                        referenceId: "teacher-review-\(index)",
                        summary: "Teacher rejected the current Safari style."
                    ),
                    ruleId: "rule-style-active-001",
                    affectedRuleIds: ["rule-style-active-001"],
                    note: "Teacher rejected the current Safari style as too terse."
                )
            )
        }

        let report = try PreferenceDriftMonitor().analyze(
            using: store,
            generatedAt: "2026-03-19T12:00:00Z"
        )

        XCTAssertEqual(report.profileVersion, "profile-current-001")
        XCTAssertTrue(report.dataAvailability.usageMetricsEvaluated)

        let highRiskStats = try XCTUnwrap(
            report.ruleStats.first(where: { $0.ruleId == "rule-high-risk-001" })
        )
        XCTAssertEqual(highRiskStats.recentRelevantDecisionCount, 10)
        XCTAssertEqual(highRiskStats.recentOverrideCount, 6)
        XCTAssertEqual(highRiskStats.recentOverrideRate, 0.6)

        XCTAssertTrue(
            report.findings.contains(where: {
                $0.ruleId == "rule-stale-001" && $0.kind == .longTimeNoHit
            })
        )
        XCTAssertTrue(
            report.findings.contains(where: {
                $0.ruleId == "rule-high-risk-001" && $0.kind == .overrideRateElevated
            })
        )
        XCTAssertTrue(
            report.findings.contains(where: {
                $0.ruleId == "rule-high-risk-001" && $0.kind == .highRiskBehaviorMismatch
            })
        )
        XCTAssertTrue(
            report.findings.contains(where: {
                $0.ruleId == "rule-style-active-001" && $0.kind == .teacherRejectedRepeatedly
            })
        )
        XCTAssertTrue(
            report.findings.contains(where: {
                $0.ruleId == "rule-style-active-001" && $0.kind == .stylePreferenceChanged
            })
        )
    }

    func testMonitorSkipsUsageBasedFindingsWithoutAssemblyLogs() throws {
        let fileManager = FileManager.default
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("openstaff-preference-drift-nodata-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(
            preferencesRootDirectory: preferencesRoot,
            fileManager: fileManager
        )
        let builder = PreferenceProfileBuilder()

        let staleSignal = makeSignal(
            signalId: "signal-stale-no-assembly-001",
            scope: .global(),
            type: .procedure,
            timestamp: "2026-01-10T09:00:00Z"
        )

        try store.storeSignals([staleSignal], actor: "test")
        try store.storeRule(
            makeRule(
                ruleId: "rule-stale-no-assembly-001",
                signal: staleSignal,
                statement: "Prefer the previous browser flow.",
                riskLevel: .medium,
                activationStatus: .active
            ),
            actor: "test"
        )
        try builder.rebuildAndStore(
            using: store,
            actor: "test",
            profileVersion: "profile-no-assembly-001",
            generatedAt: "2026-03-19T09:30:00Z"
        )

        let report = try PreferenceDriftMonitor().analyze(
            using: store,
            generatedAt: "2026-03-19T12:00:00Z"
        )

        XCTAssertFalse(report.dataAvailability.usageMetricsEvaluated)
        XCTAssertFalse(
            report.findings.contains(where: {
                $0.kind == .longTimeNoHit || $0.kind == .overrideRateElevated
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
            confidence: 0.93,
            evidenceIds: ["evidence-\(signalId)"],
            proposedAction: "apply-\(signalId)",
            promotionStatus: .confirmed,
            timestamp: timestamp
        )
    }

    private func makeRule(
        ruleId: String,
        signal: PreferenceSignal,
        statement: String,
        riskLevel: InteractionTurnRiskLevel,
        activationStatus: PreferenceRuleActivationStatus
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
            activationStatus: activationStatus,
            teacherConfirmed: true,
            createdAt: signal.timestamp,
            updatedAt: signal.timestamp
        )
    }
}
