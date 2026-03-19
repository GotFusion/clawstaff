import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceAwareStudentPlannerTests: XCTestCase {
    func testPreferenceAwarePlannerReranksKnowledgeItemsUsingPlannerProfile() {
        let menuDrivenItem = makeKnowledgeItem(
            knowledgeItemId: "knowledge-001",
            taskId: "task-open-tab-menu",
            goal: "在 Safari 打开新标签页",
            summary: "通过菜单逐步打开新标签页。",
            instructions: [
                "点击 File 菜单",
                "点击 New Tab"
            ],
            constraints: [
                KnowledgeConstraint(type: .manualConfirmationRequired, description: "菜单切换前需要确认当前页面状态。")
            ],
            addSemanticTargets: false
        )
        let shortcutItem = makeKnowledgeItem(
            knowledgeItemId: "knowledge-002",
            taskId: "task-open-tab-shortcut",
            goal: "在 Safari 打开新标签页",
            summary: "直接使用快捷键打开新标签页。",
            instructions: [
                "按下 Command+T 打开新标签页"
            ],
            addSemanticTargets: true
        )

        let input = StudentPlanningInput(
            goal: "在 Safari 打开新标签页",
            preferredKnowledgeItemId: nil,
            knowledgeItems: [menuDrivenItem, shortcutItem]
        )

        let baselinePlan = RuleBasedStudentTaskPlanner().plan(input: input)
        XCTAssertEqual(baselinePlan?.selectedKnowledgeItemId, "knowledge-001")

        let profile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-safari-shortcut-001",
                    type: .procedure,
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    hint: "Prefer keyboard shortcut execution for tab workflows.",
                    proposedAction: "prefer_keyboard_shortcut"
                )
            ]
        )

        let plan = PreferenceAwareStudentPlanner(
            preferenceProfile: profile
        ).plan(input: input)

        XCTAssertEqual(plan?.selectedKnowledgeItemId, "knowledge-002")
        XCTAssertEqual(plan?.strategy, .preferenceAwareRuleV1)
        XCTAssertEqual(plan?.preferenceDecision?.executionStyle, .assertive)
        XCTAssertEqual(plan?.preferenceDecision?.appliedRuleIds, ["rule-safari-shortcut-001"])
        XCTAssertTrue(plan?.preferenceDecision?.summary.contains("积极执行") == true)
    }

    func testPreferenceAwarePlannerEmitsConservativeDecisionAndLowerConfidence() throws {
        let item = makeKnowledgeItem(
            knowledgeItemId: "knowledge-010",
            taskId: "task-safe-save",
            goal: "在 Safari 中保存当前页面",
            summary: "通过稳妥步骤保存页面。",
            instructions: [
                "打开 File 菜单",
                "点击 Save As"
            ],
            addSemanticTargets: true
        )
        let profile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-safari-risk-001",
                    type: .risk,
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    hint: "Require confirmation and stay conservative before browser mutations.",
                    proposedAction: "require_teacher_confirmation"
                ),
                makeDirective(
                    ruleId: "rule-safari-repair-001",
                    type: .repair,
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    hint: "Retry repair before asking for re-teach.",
                    proposedAction: "repair_before_reteach"
                )
            ]
        )

        let plan = PreferenceAwareStudentPlanner(
            preferenceProfile: profile
        ).plan(
            input: StudentPlanningInput(
                goal: "在 Safari 中保存当前页面",
                preferredKnowledgeItemId: nil,
                knowledgeItems: [item]
            )
        )

        let decision = try XCTUnwrap(plan?.preferenceDecision)
        let firstStep = try XCTUnwrap(plan?.steps.first)
        XCTAssertEqual(plan?.strategy, .preferenceAwareRuleV1)
        XCTAssertEqual(decision.executionStyle, .conservative)
        XCTAssertEqual(decision.failureRecoveryPreference, .repairBeforeReteach)
        XCTAssertLessThan(firstStep.confidence, 0.8)
        XCTAssertTrue(decision.summary.contains("失败后优先 repair") == true)
    }

    func testPreferenceAwarePlannerCanPreferReteachBeforeRepair() {
        let item = makeKnowledgeItem(
            knowledgeItemId: "knowledge-020",
            taskId: "task-form-fill",
            goal: "填写表单并提交",
            summary: "用较短步骤填写表单。",
            instructions: [
                "点击姓名输入框并输入内容",
                "点击提交按钮"
            ],
            addSemanticTargets: false
        )
        let profile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-form-reteach-001",
                    type: .repair,
                    scope: .app(bundleId: "com.apple.Safari", appName: "Safari"),
                    hint: "For this workflow, reteach current step before attempting a repair.",
                    proposedAction: "reteachCurrentStep"
                )
            ]
        )

        let plan = PreferenceAwareStudentPlanner(
            preferenceProfile: profile
        ).plan(
            input: StudentPlanningInput(
                goal: "填写表单并提交",
                preferredKnowledgeItemId: nil,
                knowledgeItems: [item]
            )
        )

        XCTAssertEqual(plan?.preferenceDecision?.failureRecoveryPreference, .reteachBeforeRepair)
        XCTAssertEqual(plan?.preferenceDecision?.appliedRuleIds, ["rule-form-reteach-001"])
        XCTAssertTrue(plan?.preferenceDecision?.summary.contains("失败后优先 re-teach") == true)
    }

    private func makeKnowledgeItem(
        knowledgeItemId: String,
        taskId: String,
        goal: String,
        summary: String,
        instructions: [String],
        constraints: [KnowledgeConstraint] = [],
        addSemanticTargets: Bool
    ) -> KnowledgeItem {
        KnowledgeItem(
            knowledgeItemId: knowledgeItemId,
            taskId: taskId,
            sessionId: "session-001",
            goal: goal,
            summary: summary,
            steps: instructions.enumerated().map { index, instruction in
                KnowledgeStep(
                    stepId: String(format: "step-%03d", index + 1),
                    instruction: instruction,
                    sourceEventIds: ["evt-\(index + 1)"],
                    target: addSemanticTargets
                        ? KnowledgeStepTarget(
                            semanticTargets: [
                                SemanticTarget(
                                    locatorType: .roleAndTitle,
                                    appBundleId: "com.apple.Safari",
                                    windowTitlePattern: "^Main$",
                                    elementRole: "AXButton",
                                    elementTitle: "Action \(index + 1)",
                                    confidence: 0.92,
                                    source: .capture
                                )
                            ],
                            preferredLocatorType: .roleAndTitle
                        )
                        : nil
                )
            },
            context: KnowledgeContext(
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: "Main",
                windowId: nil
            ),
            constraints: constraints,
            source: KnowledgeSource(
                taskChunkSchemaVersion: "task.chunk.v0",
                startTimestamp: "2026-03-19T10:00:00Z",
                endTimestamp: "2026-03-19T10:00:10Z",
                eventCount: instructions.count,
                boundaryReason: .sessionEnd
            ),
            createdAt: "2026-03-19T10:00:10Z"
        )
    }

    private func makeProfile(
        directives: [PreferenceProfileDirective]
    ) -> PreferenceProfile {
        PreferenceProfile(
            profileVersion: "profile-2026-03-19-001",
            activeRuleIds: directives.map(\.ruleId),
            assistPreferences: [],
            skillPreferences: [],
            repairPreferences: [],
            reviewPreferences: [],
            plannerPreferences: directives,
            generatedAt: "2026-03-19T10:30:00Z"
        )
    }

    private func makeDirective(
        ruleId: String,
        type: PreferenceSignalType,
        scope: PreferenceSignalScopeReference,
        hint: String,
        proposedAction: String
    ) -> PreferenceProfileDirective {
        PreferenceProfileDirective(
            ruleId: ruleId,
            type: type,
            scope: scope,
            statement: hint,
            hint: hint,
            proposedAction: proposedAction,
            teacherConfirmed: true,
            updatedAt: "2026-03-19T10:20:00Z"
        )
    }
}
