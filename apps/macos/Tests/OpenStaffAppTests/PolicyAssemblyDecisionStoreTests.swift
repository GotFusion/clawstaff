import Foundation
import XCTest
@testable import OpenStaffApp

final class PolicyAssemblyDecisionStoreTests: XCTestCase {
    func testStorePersistsDecisionAndSupportsScopedQueries() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("openstaff-policy-assembly-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let preferencesRoot = root.appendingPathComponent("data/preferences", isDirectory: true)
        let store = PolicyAssemblyDecisionStore(
            preferencesRootDirectory: preferencesRoot,
            fileManager: fileManager
        )

        let decision = PolicyAssemblyDecision(
            decisionId: "policy-assist-trace-001-step-001",
            targetModule: .assist,
            inputRef: PolicyAssemblyInputReference(
                traceId: "trace-001",
                sessionId: "session-001",
                taskId: "task-001",
                knowledgeItemId: "knowledge-001",
                stepId: "step-001"
            ),
            profileVersion: "profile-001",
            strategyVersion: "preference-aware-retrieval-v1",
            appliedRuleIds: ["rule-a"],
            suppressedRuleIds: ["rule-b"],
            finalDecisionSummary: "Selected the shortcut candidate.",
            ruleEvaluations: [
                PolicyAssemblyRuleEvaluation(
                    ruleId: "rule-a",
                    targetId: "knowledge-001::step-001",
                    targetLabel: "快捷键 Command+T 打开新标签页",
                    disposition: .applied,
                    matchScore: 1.0,
                    weight: 0.16,
                    delta: 0.16,
                    explanation: "Shortcut rule matched current candidate."
                )
            ],
            finalWeights: [
                PolicyAssemblyFinalWeight(
                    weightId: "knowledge-001::step-001",
                    label: "快捷键 Command+T 打开新标签页",
                    kind: .candidate,
                    baseValue: 0.82,
                    finalValue: 0.98,
                    selected: true,
                    appliedRuleIds: ["rule-a"],
                    notes: ["Selected candidate won after preference rerank."]
                )
            ],
            timestamp: "2026-03-19T10:35:00+08:00"
        )

        let fileURL = try store.store(decision)
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
        XCTAssertTrue(fileURL.path.contains("/assembly/2026-03-19/assist/session-001/"))

        let loaded = try XCTUnwrap(store.load(decisionId: decision.decisionId))
        XCTAssertEqual(loaded, decision)

        let queried = try store.loadDecisions(
            matching: PolicyAssemblyDecisionQuery(
                date: "2026-03-19",
                targetModule: .assist,
                sessionId: "session-001",
                taskId: "task-001",
                traceId: "trace-001"
            )
        )
        XCTAssertEqual(queried, [decision])
    }

    func testFeatureFlagParsesExpectedEnabledValues() {
        XCTAssertTrue(
            PolicyAssemblyDecisionFeatureFlag.isEnabled(
                environment: [PolicyAssemblyDecisionFeatureFlag.environmentKey: "1"]
            )
        )
        XCTAssertTrue(
            PolicyAssemblyDecisionFeatureFlag.isEnabled(
                environment: [PolicyAssemblyDecisionFeatureFlag.environmentKey: "enabled"]
            )
        )
        XCTAssertFalse(
            PolicyAssemblyDecisionFeatureFlag.isEnabled(
                environment: [PolicyAssemblyDecisionFeatureFlag.environmentKey: "0"]
            )
        )
        XCTAssertFalse(
            PolicyAssemblyDecisionFeatureFlag.isEnabled(environment: [:])
        )
    }
}
