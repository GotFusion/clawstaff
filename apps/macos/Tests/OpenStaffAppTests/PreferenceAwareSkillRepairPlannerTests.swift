import Foundation
import XCTest
@testable import OpenStaffApp

final class PreferenceAwareSkillRepairPlannerTests: XCTestCase {
    func testPreferenceAwarePlannerReordersFirstRepairActionPerProfile() throws {
        let report = makeReport()
        let payload = makePayload(taskFamily: "browser.navigation", skillFamily: "browser.open_tab")

        let basePlan = SkillRepairPlanner().buildPlan(report: report)
        XCTAssertEqual(basePlan.actions.first?.type, .updateSkillLocator)

        let replayProfile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-repair-replay-001",
                    scope: .taskFamily("browser.navigation"),
                    hint: "Prefer replay and relocalize before editing the skill bundle.",
                    proposedAction: "relocalize"
                )
            ]
        )
        let reteachProfile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-repair-reteach-001",
                    scope: .taskFamily("browser.navigation"),
                    hint: "When this workflow drifts, go straight to re-teach.",
                    proposedAction: "reteachCurrentStep"
                )
            ]
        )

        let replayPlan = PreferenceAwareSkillRepairPlanner(
            preferenceProfile: replayProfile
        ).buildPlan(report: report, payload: payload)
        let reteachPlan = PreferenceAwareSkillRepairPlanner(
            preferenceProfile: reteachProfile
        ).buildPlan(report: report, payload: payload)

        XCTAssertEqual(replayPlan.actions.first?.type, .relocalize)
        XCTAssertEqual(reteachPlan.actions.first?.type, .reteachCurrentStep)
        XCTAssertEqual(replayPlan.preferenceDecision?.appliedRuleIds, ["rule-repair-replay-001"])
        XCTAssertEqual(reteachPlan.preferenceDecision?.appliedRuleIds, ["rule-repair-reteach-001"])
    }

    func testPreferenceAwarePlannerAddsRuleSourceAndExplanation() throws {
        let report = makeReport()
        let payload = makePayload(taskFamily: "browser.navigation", skillFamily: "browser.open_tab")
        let profile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-window-locator-001",
                    type: .locator,
                    scope: .windowPattern("Find", appBundleId: "com.apple.Safari", appName: "Safari"),
                    hint: "Refresh semantic anchors before fallback replay.",
                    proposedAction: "refresh_skill_locator"
                )
            ]
        )

        let plan = PreferenceAwareSkillRepairPlanner(
            preferenceProfile: profile
        ).buildPlan(report: report, payload: payload)

        let firstAction = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(firstAction.type, .updateSkillLocator)
        XCTAssertEqual(firstAction.appliedRuleIds, ["rule-window-locator-001"])
        XCTAssertNotNil(firstAction.preferenceReason)
        XCTAssertTrue(firstAction.preferenceReason?.contains("rule-window-locator-001") == true)
        XCTAssertTrue(plan.summary.contains("rule-window-locator-001"))
        XCTAssertTrue(plan.preferenceDecision?.summary.contains("优先「更新 skill locator」") == true)
    }

    func testPreferenceAwarePlannerIgnoresUnmatchedScope() {
        let report = makeReport()
        let payload = makePayload(taskFamily: "browser.navigation", skillFamily: "browser.open_tab")
        let profile = makeProfile(
            directives: [
                makeDirective(
                    ruleId: "rule-other-skill-001",
                    scope: .skillFamily("finder.rename"),
                    hint: "Different skill family should not affect this repair plan.",
                    proposedAction: "reteachCurrentStep"
                )
            ]
        )

        let plan = PreferenceAwareSkillRepairPlanner(
            preferenceProfile: profile
        ).buildPlan(report: report, payload: payload)

        XCTAssertNil(plan.preferenceDecision)
        XCTAssertEqual(plan.actions.first?.type, .updateSkillLocator)
        XCTAssertNil(plan.actions.first?.appliedRuleIds)
    }

    private func makeReport() -> SkillDriftReport {
        SkillDriftReport(
            skillName: "openstaff-browser-open-tab",
            knowledgeItemId: "knowledge-001",
            taskId: "task-001",
            sessionId: "session-001",
            detectedAt: "2026-03-19T10:20:00Z",
            snapshot: ReplayEnvironmentSnapshot(
                capturedAt: "2026-03-19T10:19:00Z",
                appName: "Safari",
                appBundleId: "com.apple.Safari",
                windowTitle: "Find",
                windowId: "window-1",
                windowSignature: WindowSignature(
                    signature: "signature-find-window",
                    normalizedTitle: "find",
                    role: "AXWindow",
                    subrole: "AXStandardWindow",
                    sizeBucket: "12x8"
                )
            ),
            status: .driftDetected,
            dominantDriftKind: .uiTextChanged,
            currentRepairVersion: 2,
            findings: [
                SkillDriftFinding(
                    stepId: "step-001",
                    instruction: "Click Save",
                    status: .failed,
                    driftKind: .uiTextChanged,
                    confidence: 0.88,
                    failureReason: .textAnchorChanged,
                    message: "Button text changed from Save to Submit."
                ),
                SkillDriftFinding(
                    stepId: "step-002",
                    instruction: "Click toolbar item",
                    status: .failed,
                    driftKind: .elementPositionChanged,
                    confidence: 0.79,
                    failureReason: .coordinateFallbackOnly,
                    message: "Only coordinate fallback remained."
                ),
                SkillDriftFinding(
                    stepId: "step-003",
                    instruction: "Open dialog",
                    status: .failed,
                    driftKind: .windowStructureChanged,
                    confidence: 0.82,
                    failureReason: .windowMismatch,
                    message: "Window hierarchy changed."
                )
            ],
            stats: [
                SkillDriftStat(kind: .uiTextChanged, count: 1),
                SkillDriftStat(kind: .elementPositionChanged, count: 1),
                SkillDriftStat(kind: .windowStructureChanged, count: 1)
            ],
            summary: "Detected mixed drift across three steps."
        )
    }

    private func makePayload(
        taskFamily: String,
        skillFamily: String
    ) -> SkillBundlePayload {
        SkillBundlePayload(
            schemaVersion: "openstaff.openclaw-skill.v1",
            skillName: "openstaff-browser-open-tab",
            knowledgeItemId: "knowledge-001",
            taskId: "task-001",
            sessionId: "session-001",
            llmOutputAccepted: true,
            createdAt: "2026-03-19T10:00:00Z",
            mappedOutput: SkillBundleMappedOutput(
                objective: "Open a browser tab",
                context: SkillBundleContext(
                    appName: "Safari",
                    appBundleId: "com.apple.Safari",
                    windowTitle: "Find"
                ),
                executionPlan: SkillBundleExecutionPlan(
                    requiresTeacherConfirmation: false,
                    steps: [
                        SkillBundleExecutionStep(
                            stepId: "step-001",
                            actionType: "click",
                            instruction: "Click Save",
                            target: "Save",
                            sourceEventIds: ["evt-001"]
                        )
                    ],
                    completionCriteria: SkillBundleCompletionCriteria(
                        expectedStepCount: 1,
                        requiredFrontmostAppBundleId: "com.apple.Safari"
                    )
                ),
                safetyNotes: [],
                confidence: 0.9
            ),
            provenance: SkillBundleProvenance(
                skillBuild: SkillBundleSkillBuild(
                    repairVersion: 2,
                    preferenceProfileVersion: "profile-2026-03-19-001",
                    appliedPreferenceRuleIds: ["rule-window-locator-001"],
                    preferenceSummary: "Repair planner prefers locator-first fixes.",
                    taskFamily: taskFamily,
                    skillFamily: skillFamily
                ),
                stepMappings: []
            )
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
            repairPreferences: directives,
            reviewPreferences: [],
            plannerPreferences: [],
            generatedAt: "2026-03-19T10:15:00Z"
        )
    }

    private func makeDirective(
        ruleId: String,
        type: PreferenceSignalType = .repair,
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
            updatedAt: "2026-03-19T10:10:00Z"
        )
    }
}
