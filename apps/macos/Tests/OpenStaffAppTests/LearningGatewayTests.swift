import Foundation
import XCTest
@testable import OpenStaffApp

final class LearningGatewayTests: XCTestCase {
    func testGatewayListsRulesAndAssemblyDecisionsThroughPublicContracts() throws {
        let fileManager = FileManager.default
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("openstaff-learning-gateway-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let learningRoot = workspaceRoot.appendingPathComponent("data/learning", isDirectory: true)
        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(preferencesRootDirectory: preferencesRoot, fileManager: fileManager)
        let assemblyStore = PolicyAssemblyDecisionStore(
            preferencesRootDirectory: preferencesRoot,
            fileManager: fileManager
        )

        let safariSignal = makeSignal(
            signalId: "signal-safari-001",
            turnId: "turn-safari-001",
            sessionId: "session-safari-001",
            taskId: "task-safari-001",
            stepId: "step-safari-001",
            scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
            timestamp: "2026-03-19T10:30:00Z",
            hint: "Search-heavy work should stay in Safari.",
            proposedAction: "prefer_safari"
        )
        try store.storeSignals([safariSignal])

        let safariRule = makeRule(
            ruleId: "rule-safari-001",
            signal: safariSignal,
            statement: "Search-heavy tasks should default to Safari.",
            teacherConfirmed: true
        )
        try store.storeRule(safariRule)

        let snapshot = makeProfileSnapshot(
            profileVersion: "profile-2026-03-19-001",
            rules: [safariRule],
            createdAt: "2026-03-19T10:35:00Z"
        )
        try store.storeProfileSnapshot(snapshot)

        let decision = PolicyAssemblyDecision(
            decisionId: "policy-assist-001",
            targetModule: .assist,
            inputRef: PolicyAssemblyInputReference(
                traceId: "trace-safari-001",
                sessionId: safariSignal.sessionId,
                taskId: safariSignal.taskId,
                knowledgeItemId: "knowledge-001",
                stepId: safariSignal.stepId
            ),
            profileVersion: snapshot.profileVersion,
            strategyVersion: "preference-aware-retrieval-v1",
            appliedRuleIds: [safariRule.ruleId],
            suppressedRuleIds: [],
            finalDecisionSummary: "Preferred the Safari-aligned candidate.",
            ruleEvaluations: [
                PolicyAssemblyRuleEvaluation(
                    ruleId: safariRule.ruleId,
                    targetId: "knowledge-001::step-001",
                    targetLabel: "Open results in Safari",
                    disposition: .applied,
                    matchScore: 1.0,
                    weight: 0.22,
                    delta: 0.22,
                    explanation: "App-scoped rule matched the task context."
                )
            ],
            finalWeights: [
                PolicyAssemblyFinalWeight(
                    weightId: "knowledge-001::step-001",
                    label: "Open results in Safari",
                    kind: .candidate,
                    baseValue: 0.71,
                    finalValue: 0.93,
                    selected: true,
                    appliedRuleIds: [safariRule.ruleId],
                    notes: ["Selected after applying Safari preference."]
                )
            ],
            timestamp: "2026-03-19T10:40:00Z"
        )
        try assemblyStore.store(decision)

        let gateway = FileSystemLearningGateway(
            repositoryRootDirectory: workspaceRoot,
            learningRootDirectory: learningRoot,
            preferencesRootDirectory: preferencesRoot,
            preferenceStore: store,
            assemblyStore: assemblyStore,
            exportRunner: ExportRunnerSpy(stdout: "{}"),
            nowProvider: { Date(timeIntervalSince1970: 1_773_920_400) }
        )

        let rulesResponse = try gateway.listRules(
            PreferencesListRulesRequest(
                filter: LearningGatewayRuleFilter(appBundleId: "com.apple.Safari")
            )
        )
        XCTAssertEqual(rulesResponse.method, .preferencesListRules)
        XCTAssertEqual(rulesResponse.rules.map(\.ruleId), ["rule-safari-001"])
        XCTAssertEqual(rulesResponse.latestProfileSnapshot?.profileVersion, snapshot.profileVersion)
        XCTAssertEqual(rulesResponse.latestProfileSnapshot?.profile.activeRuleIds, [safariRule.ruleId])
        XCTAssertEqual(rulesResponse.generatedAt, "2026-03-19T11:40:00Z")

        let decisionResponse = try gateway.listAssemblyDecisions(
            PreferencesListAssemblyDecisionsRequest(
                filter: LearningGatewayAssemblyDecisionFilter(
                    date: "2026-03-19",
                    targetModule: .assist,
                    sessionId: safariSignal.sessionId,
                    taskId: safariSignal.taskId,
                    traceId: "trace-safari-001"
                )
            )
        )
        XCTAssertEqual(decisionResponse.method, .preferencesListAssemblyDecisions)
        XCTAssertEqual(decisionResponse.decisions, [decision])
        XCTAssertEqual(decisionResponse.latestProfileSnapshot?.profileVersion, snapshot.profileVersion)
        XCTAssertEqual(decisionResponse.generatedAt, "2026-03-19T11:40:00Z")
    }

    func testGatewayExportBundleUsesPublicRequestAndMapsScriptResponse() throws {
        let fileManager = FileManager.default
        let workspaceRoot = fileManager.temporaryDirectory
            .appendingPathComponent("openstaff-learning-gateway-export-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceRoot) }

        let learningRoot = workspaceRoot.appendingPathComponent("data/learning", isDirectory: true)
        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PreferenceMemoryStore(preferencesRootDirectory: preferencesRoot, fileManager: fileManager)
        let assemblyStore = PolicyAssemblyDecisionStore(
            preferencesRootDirectory: preferencesRoot,
            fileManager: fileManager
        )
        let runner = ExportRunnerSpy(
            stdout: """
            {
              "bundleId": "bundle-001",
              "bundlePath": "/tmp/openstaff-learning-bundle",
              "counts": {
                "audit": { "files": 1, "records": 2 },
                "evidence": { "files": 1, "records": 3 },
                "profiles": { "files": 1, "records": 1 },
                "rules": { "files": 2, "records": 2 },
                "signals": { "files": 2, "records": 4 },
                "turns": { "files": 2, "records": 2 }
              },
              "indexes": {
                "auditIds": ["audit-001", "audit-002"],
                "evidenceIds": ["evidence-001", "evidence-002", "evidence-003"],
                "latestProfileUpdatedAt": "2026-03-19T10:35:00Z",
                "latestProfileVersion": "profile-2026-03-19-001",
                "profileVersions": ["profile-2026-03-19-001"],
                "ruleIds": ["rule-001", "rule-002"],
                "signalIds": ["signal-001", "signal-002", "signal-003", "signal-004"],
                "turnIds": ["turn-001", "turn-002"]
              },
              "issues": [
                {
                  "category": "audit",
                  "code": "LB-AUDIT-SUBSET",
                  "message": "audit file was trimmed to the selected dependency set.",
                  "path": "verification.json",
                  "severity": "warning"
                }
              ],
              "manifestPath": "/tmp/openstaff-learning-bundle/manifest.json",
              "passed": true,
              "verificationPath": "/tmp/openstaff-learning-bundle/verification.json"
            }
            """
        )
        let gateway = FileSystemLearningGateway(
            repositoryRootDirectory: workspaceRoot,
            learningRootDirectory: learningRoot,
            preferencesRootDirectory: preferencesRoot,
            preferenceStore: store,
            assemblyStore: assemblyStore,
            exportRunner: runner
        )

        let response = try gateway.exportBundle(
            PreferencesExportBundleRequest(
                outputDirectoryPath: "tmp/export-bundle",
                bundleId: "bundle-001",
                filter: LearningBundleExportFilter(
                    sessionIds: ["session-001"],
                    taskIds: ["task-001"],
                    turnIds: ["turn-001"]
                ),
                overwrite: true
            )
        )

        let request = try XCTUnwrap(runner.requests.first)
        XCTAssertEqual(request.relativeScriptPath, "scripts/learning/export_learning_bundle.py")
        XCTAssertEqual(request.repositoryRootDirectory, workspaceRoot.standardizedFileURL)
        XCTAssertEqual(
            request.arguments,
            [
                "--learning-root", learningRoot.standardizedFileURL.path,
                "--preferences-root", preferencesRoot.standardizedFileURL.path,
                "--output", workspaceRoot.appendingPathComponent("tmp/export-bundle", isDirectory: true).standardizedFileURL.path,
                "--json",
                "--bundle-id", "bundle-001",
                "--session-id", "session-001",
                "--task-id", "task-001",
                "--turn-id", "turn-001",
                "--overwrite"
            ]
        )

        XCTAssertEqual(response.method, .preferencesExportBundle)
        XCTAssertEqual(response.bundleId, "bundle-001")
        XCTAssertEqual(response.counts.turns, LearningBundleCategoryCount(files: 2, records: 2))
        XCTAssertEqual(response.indexes.latestProfileVersion, "profile-2026-03-19-001")
        XCTAssertEqual(response.issues.first?.code, "LB-AUDIT-SUBSET")
        XCTAssertTrue(response.passed)
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
            confidence: 0.92,
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
        teacherConfirmed: Bool = false
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
            riskLevel: .low,
            activationStatus: .active,
            teacherConfirmed: teacherConfirmed,
            createdAt: signal.timestamp,
            updatedAt: signal.timestamp
        )
    }

    private func makeProfileSnapshot(
        profileVersion: String,
        rules: [PreferenceRule],
        createdAt: String
    ) -> PreferenceProfileSnapshot {
        let directives = rules.map(PreferenceProfileDirective.init(rule:))
        let profile = PreferenceProfile(
            profileVersion: profileVersion,
            activeRuleIds: rules.map(\.ruleId),
            assistPreferences: directives,
            skillPreferences: [],
            repairPreferences: [],
            reviewPreferences: directives,
            plannerPreferences: [],
            generatedAt: createdAt
        )

        return PreferenceProfileSnapshot(
            profile: profile,
            sourceRuleIds: rules.map(\.ruleId),
            createdAt: createdAt
        )
    }
}

private final class ExportRunnerSpy: LearningGatewayExportScriptRunning {
    private(set) var requests: [LearningGatewayExportScriptRequest] = []
    private let stdout: String
    private let stderr: String

    init(stdout: String, stderr: String = "") {
        self.stdout = stdout
        self.stderr = stderr
    }

    func run(request: LearningGatewayExportScriptRequest) throws -> LearningGatewayExportScriptOutput {
        requests.append(request)
        return LearningGatewayExportScriptOutput(
            exitCode: 0,
            stdout: stdout,
            stderr: stderr
        )
    }
}
