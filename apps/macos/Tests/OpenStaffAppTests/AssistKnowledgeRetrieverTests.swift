import Foundation
import XCTest
@testable import OpenStaffApp

final class AssistKnowledgeRetrieverTests: XCTestCase {
    func testRetrieverRanksCandidatesUsingWindowGoalAndRecentSequence() {
        let input = AssistPredictionInput(
            completedStepCount: 1,
            currentAppName: "Safari",
            currentAppBundleId: "com.apple.Safari",
            currentWindowTitle: "OpenStaff - GitHub",
            currentTaskGoal: "处理 Pull Requests",
            recentStepInstructions: ["点击 Pull Requests"],
            knowledgeItems: [
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-002",
                    taskId: "task-merge-002",
                    createdAt: "2026-03-13T12:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-001",
                    taskId: "task-merge-001",
                    createdAt: "2026-03-13T11:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-issue-001",
                    taskId: "task-issue-001",
                    createdAt: "2026-03-13T10:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Issues", "New Issue"]
                )
            ]
        )

        let matches = AssistKnowledgeRetriever(maxResults: 5).retrieve(input: input).matches

        XCTAssertGreaterThanOrEqual(matches.count, 2)
        XCTAssertEqual(matches[0].knowledgeItemId, "ki-merge-002")
        XCTAssertEqual(matches[0].targetDescription, "Merge")
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .app }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .window }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .recentSequence }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .goal }))
        XCTAssertTrue(matches[0].matchedSignals.contains(where: { $0.type == .historicalPreference }))
        XCTAssertEqual(matches[1].knowledgeItemId, "ki-merge-001")
        XCTAssertGreaterThan(matches[0].score, matches[2].score)
    }

    func testPredictorReturnsEvidenceAndReadableReason() {
        let input = AssistPredictionInput(
            completedStepCount: 1,
            currentAppName: "Safari",
            currentAppBundleId: "com.apple.Safari",
            currentWindowTitle: "OpenStaff - GitHub",
            currentTaskGoal: "处理 Pull Requests",
            recentStepInstructions: ["点击 Pull Requests"],
            knowledgeItems: [
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-002",
                    taskId: "task-merge-002",
                    createdAt: "2026-03-13T12:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-merge-001",
                    taskId: "task-merge-001",
                    createdAt: "2026-03-13T11:00:00Z",
                    goal: "在 Safari 中处理 Pull Requests",
                    windowTitle: "OpenStaff - GitHub",
                    stepTitles: ["Pull Requests", "Merge"]
                )
            ]
        )

        let suggestion = RetrievalBasedAssistPredictor(
            retriever: AssistKnowledgeRetriever(maxResults: 5),
            evidenceLimit: 3
        ).predict(input: input)

        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.predictorVersion, AssistPredictionStrategy.retrievalV1.rawValue)
        XCTAssertEqual(suggestion?.action.type, .click)
        XCTAssertEqual(suggestion?.knowledgeItemId, "ki-merge-002")
        XCTAssertEqual(suggestion?.evidence.count, 2)
        XCTAssertTrue(suggestion?.action.reason.contains("OpenStaff - GitHub") == true)
        XCTAssertTrue(suggestion?.action.reason.contains("参考了 2 条历史知识") == true)
        XCTAssertTrue(suggestion?.action.reason.contains("Merge") == true)
    }

    func testPreferenceAwarePredictorReranksSameRetrievalResultsDifferentlyPerProfile() {
        let input = AssistPredictionInput(
            completedStepCount: 1,
            currentAppName: "Safari",
            currentAppBundleId: "com.apple.Safari",
            currentWindowTitle: "OpenStaff - GitHub",
            currentTaskGoal: "在 Safari 中打开新标签页",
            currentTaskFamily: "browser.navigation",
            recentStepInstructions: ["点击 Pull Requests"],
            knowledgeItems: [
                makeKnowledgeItem(
                    knowledgeItemId: "ki-click-tab-002",
                    taskId: "task-click-tab-002",
                    createdAt: "2026-03-13T12:00:00Z",
                    goal: "在 Safari 中打开新标签页",
                    windowTitle: "OpenStaff - GitHub",
                    stepInstructions: ["点击 Pull Requests", "点击 新标签页按钮"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-shortcut-tab-001",
                    taskId: "task-shortcut-tab-001",
                    createdAt: "2026-03-13T11:00:00Z",
                    goal: "在 Safari 中打开新标签页",
                    windowTitle: "OpenStaff - GitHub",
                    stepInstructions: ["点击 Pull Requests", "快捷键 Command+T 打开新标签页"]
                )
            ]
        )

        let baseline = RetrievalBasedAssistPredictor(
            retriever: AssistKnowledgeRetriever(maxResults: 5),
            evidenceLimit: 3
        ).predict(input: input)

        let shortcutProfile = makeAssistProfile(
            profileVersion: "profile-shortcut-001",
            directives: [
                makeDirective(
                    ruleId: "rule-app-shortcut-001",
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    type: .procedure,
                    statement: "Prefer keyboard shortcuts for opening tabs in Safari.",
                    hint: "Use shortcuts instead of toolbar clicks when opening a new tab.",
                    proposedAction: "prefer_keyboard_shortcut"
                )
            ]
        )
        let clickProfile = makeAssistProfile(
            profileVersion: "profile-click-001",
            directives: [
                makeDirective(
                    ruleId: "rule-app-click-001",
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    type: .procedure,
                    statement: "Prefer clicking the toolbar tab button in Safari.",
                    hint: "Use the toolbar button instead of shortcuts for a new tab.",
                    proposedAction: "prefer_toolbar_click"
                )
            ]
        )

        let shortcutSuggestion = PreferenceAwareAssistPredictor(
            retriever: AssistKnowledgeRetriever(maxResults: 5),
            preferenceProfile: shortcutProfile,
            evidenceLimit: 3
        ).predict(input: input)
        let clickSuggestion = PreferenceAwareAssistPredictor(
            retriever: AssistKnowledgeRetriever(maxResults: 5),
            preferenceProfile: clickProfile,
            evidenceLimit: 3
        ).predict(input: input)

        XCTAssertEqual(baseline?.knowledgeItemId, "ki-click-tab-002")
        XCTAssertEqual(shortcutSuggestion?.knowledgeItemId, "ki-shortcut-tab-001")
        XCTAssertEqual(clickSuggestion?.knowledgeItemId, "ki-click-tab-002")
        XCTAssertEqual(
            shortcutSuggestion?.predictorVersion,
            AssistPredictionStrategy.preferenceAwareRetrievalV1.rawValue
        )
        XCTAssertEqual(
            shortcutSuggestion?.preferenceDecision?.appliedRuleIds,
            ["rule-app-shortcut-001"]
        )
    }

    func testPreferenceAwarePredictorOutputsRuleIdsAndLoweredCandidateReasons() throws {
        let input = AssistPredictionInput(
            completedStepCount: 1,
            currentAppName: "Safari",
            currentAppBundleId: "com.apple.Safari",
            currentWindowTitle: "OpenStaff - GitHub",
            currentTaskGoal: "在 Safari 中打开新标签页",
            recentStepInstructions: ["点击 Pull Requests"],
            knowledgeItems: [
                makeKnowledgeItem(
                    knowledgeItemId: "ki-click-tab-002",
                    taskId: "task-click-tab-002",
                    createdAt: "2026-03-13T12:00:00Z",
                    goal: "在 Safari 中打开新标签页",
                    windowTitle: "OpenStaff - GitHub",
                    stepInstructions: ["点击 Pull Requests", "点击 新标签页按钮"]
                ),
                makeKnowledgeItem(
                    knowledgeItemId: "ki-shortcut-tab-001",
                    taskId: "task-shortcut-tab-001",
                    createdAt: "2026-03-13T11:00:00Z",
                    goal: "在 Safari 中打开新标签页",
                    windowTitle: "OpenStaff - GitHub",
                    stepInstructions: ["点击 Pull Requests", "快捷键 Command+T 打开新标签页"]
                )
            ]
        )

        let profile = makeAssistProfile(
            profileVersion: "profile-shortcut-001",
            directives: [
                makeDirective(
                    ruleId: "rule-app-shortcut-001",
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    type: .procedure,
                    statement: "Prefer keyboard shortcuts for opening tabs in Safari.",
                    hint: "Use shortcuts instead of toolbar clicks when opening a new tab.",
                    proposedAction: "prefer_keyboard_shortcut"
                ),
                makeDirective(
                    ruleId: "rule-risk-001",
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    type: .risk,
                    statement: "Keep tab-opening flows low risk and easy to review.",
                    hint: "Require extra caution for actions that mutate browser state.",
                    proposedAction: "require_teacher_confirmation"
                )
            ]
        )

        let suggestion = PreferenceAwareAssistPredictor(
            retriever: AssistKnowledgeRetriever(maxResults: 5),
            preferenceProfile: profile,
            evidenceLimit: 3
        ).predict(input: input)

        let preferenceDecision = try XCTUnwrap(suggestion?.preferenceDecision)
        let lowered = preferenceDecision.candidateExplanations.first(where: {
            $0.knowledgeItemId == "ki-click-tab-002"
        })

        XCTAssertEqual(preferenceDecision.profileVersion, "profile-shortcut-001")
        XCTAssertEqual(
            preferenceDecision.appliedRuleIds,
            ["rule-app-shortcut-001", "rule-risk-001"]
        )
        XCTAssertFalse(try XCTUnwrap(lowered).loweredReasons.isEmpty)
        XCTAssertTrue(suggestion?.action.reason.contains("rule-app-shortcut-001") == true)
    }

    private func makeKnowledgeItem(
        knowledgeItemId: String,
        taskId: String,
        createdAt: String,
        goal: String,
        windowTitle: String,
        stepTitles: [String]? = nil,
        stepInstructions: [String]? = nil
    ) -> KnowledgeItem {
        let resolvedInstructions: [String]
        if let stepInstructions {
            resolvedInstructions = stepInstructions
        } else if let stepTitles {
            resolvedInstructions = stepTitles.map { "点击 \($0)" }
        } else {
            resolvedInstructions = []
        }

        return KnowledgeItem(
            knowledgeItemId: knowledgeItemId,
            taskId: taskId,
            sessionId: "session-\(knowledgeItemId)",
            goal: goal,
            summary: "summary",
            steps: resolvedInstructions.enumerated().map { index, instruction in
                let title = titleFromInstruction(instruction)
                return KnowledgeStep(
                    stepId: String(format: "step-%03d", index + 1),
                    instruction: instruction,
                    sourceEventIds: ["evt-\(knowledgeItemId)-\(index + 1)"],
                    target: KnowledgeStepTarget(
                        coordinate: PointerLocation(x: 200 + index, y: 300 + index),
                        semanticTargets: [
                            SemanticTarget(
                                locatorType: .roleAndTitle,
                                appBundleId: "com.apple.Safari",
                                windowTitlePattern: SemanticTarget.exactWindowTitlePattern(for: windowTitle),
                                elementRole: "AXButton",
                                elementTitle: title,
                                elementIdentifier: title.lowercased().replacingOccurrences(of: " ", with: "-"),
                                confidence: 0.92,
                                source: .capture
                            )
                        ],
                        preferredLocatorType: .roleAndTitle
                    )
                )
            },
            context: KnowledgeContext(
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: windowTitle,
                windowId: "1"
            ),
            constraints: [],
            source: KnowledgeSource(
                taskChunkSchemaVersion: "knowledge.task-chunk.v0",
                startTimestamp: "2026-03-13T10:00:00Z",
                endTimestamp: "2026-03-13T10:00:02Z",
                eventCount: resolvedInstructions.count,
                boundaryReason: .sessionEnd
            ),
            createdAt: createdAt
        )
    }

    private func makeAssistProfile(
        profileVersion: String,
        directives: [PreferenceProfileDirective]
    ) -> PreferenceProfile {
        PreferenceProfile(
            profileVersion: profileVersion,
            activeRuleIds: directives.map(\.ruleId),
            assistPreferences: directives,
            skillPreferences: [],
            repairPreferences: [],
            reviewPreferences: [],
            plannerPreferences: [],
            generatedAt: "2026-03-19T10:00:00Z"
        )
    }

    private func makeDirective(
        ruleId: String,
        scope: PreferenceSignalScopeReference,
        type: PreferenceSignalType,
        statement: String,
        hint: String?,
        proposedAction: String?
    ) -> PreferenceProfileDirective {
        PreferenceProfileDirective(
            ruleId: ruleId,
            type: type,
            scope: scope,
            statement: statement,
            hint: hint,
            proposedAction: proposedAction,
            teacherConfirmed: true,
            updatedAt: "2026-03-19T10:00:00Z"
        )
    }

    private func titleFromInstruction(_ instruction: String) -> String {
        let prefixes = ["点击 ", "快捷键 ", "输入 "]
        for prefix in prefixes where instruction.hasPrefix(prefix) {
            return String(instruction.dropFirst(prefix.count))
        }
        return instruction
    }
}
