import Foundation

public struct PreferenceAwareStudentPlanner: StudentTaskPlanning {
    public let basePlanner: RuleBasedStudentTaskPlanner
    public let preferenceProfile: PreferenceProfile?
    public let preferenceWeight: Double

    public init(
        basePlanner: RuleBasedStudentTaskPlanner = RuleBasedStudentTaskPlanner(),
        preferenceProfile: PreferenceProfile? = nil,
        preferenceWeight: Double = 16.0
    ) {
        self.basePlanner = basePlanner
        self.preferenceProfile = preferenceProfile
        self.preferenceWeight = max(0, preferenceWeight)
    }

    public func plan(input: StudentPlanningInput) -> StudentExecutionPlan? {
        guard !input.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let profile = preferenceProfile,
              !profile.plannerPreferences.isEmpty else {
            return basePlanner.plan(input: input)
        }

        let candidates = input.knowledgeItems
            .filter { !$0.steps.isEmpty }
            .map { evaluateCandidate(item: $0, input: input, directives: profile.plannerPreferences) }
            .sorted(by: rankedCandidateSort)

        guard let selected = candidates.first else {
            return nil
        }

        let positiveRuleHits = selected.ruleHits.filter { $0.scoreDelta > 0 }
        guard !positiveRuleHits.isEmpty else {
            return basePlanner.plan(input: input)
        }

        let executionStyle = resolveExecutionStyle(for: selected)
        let failureRecoveryPreference = resolveFailureRecoveryPreference(for: selected)
        let steps = buildSteps(for: selected, executionStyle: executionStyle)
        let decision = StudentPlanningPreferenceDecision(
            profileVersion: profile.profileVersion,
            selectedKnowledgeItemId: selected.item.knowledgeItemId,
            executionStyle: executionStyle,
            failureRecoveryPreference: failureRecoveryPreference,
            appliedRuleIds: positiveRuleHits.map(\.ruleId),
            ruleHits: positiveRuleHits,
            summary: buildDecisionSummary(
                selected: selected,
                executionStyle: executionStyle,
                failureRecoveryPreference: failureRecoveryPreference,
                profileVersion: profile.profileVersion
            )
        )

        return StudentExecutionPlan(
            planId: "student-plan-\(selected.item.taskId)",
            goal: input.goal,
            selectedKnowledgeItemId: selected.item.knowledgeItemId,
            selectedTaskId: selected.item.taskId,
            strategy: .preferenceAwareRuleV1,
            plannerVersion: "preference-aware-rule-v1",
            steps: steps,
            preferenceDecision: decision
        )
    }

    private func evaluateCandidate(
        item: KnowledgeItem,
        input: StudentPlanningInput,
        directives: [PreferenceProfileDirective]
    ) -> RankedStudentCandidate {
        let context = StudentPlanningCandidateContext(
            item: item,
            goal: input.goal,
            preferredKnowledgeItemId: input.preferredKnowledgeItemId
        )
        let ruleAssessments = directives.compactMap { directive in
            evaluateDirective(directive, context: context)
        }
        let scoreDelta = ruleAssessments.reduce(0.0) { partial, assessment in
            partial + assessment.hit.scoreDelta
        }

        return RankedStudentCandidate(
            item: item,
            baseScore: context.baseScore,
            finalScore: rounded(context.baseScore + scoreDelta),
            ruleHits: ruleAssessments.map(\.hit),
            safetyScore: context.safetyScore,
            directnessScore: context.directnessScore,
            repairReadinessScore: context.repairReadinessScore,
            conservativeVote: ruleAssessments.reduce(0.0) { $0 + $1.conservativeVote },
            assertiveVote: ruleAssessments.reduce(0.0) { $0 + $1.assertiveVote },
            repairVote: ruleAssessments.reduce(0.0) { $0 + $1.repairVote },
            reteachVote: ruleAssessments.reduce(0.0) { $0 + $1.reteachVote }
        )
    }

    private func evaluateDirective(
        _ directive: PreferenceProfileDirective,
        context: StudentPlanningCandidateContext
    ) -> StudentPlanningRuleAssessment? {
        let scopeScore = scopeMatchScore(for: directive.scope, context: context)
        guard scopeScore > 0 else {
            return nil
        }

        let interpretation = interpretDirective(directive)
        let affinity = interpretation.affinity(for: context)
        guard abs(affinity) >= 0.08 else {
            return nil
        }

        let teacherMultiplier = directive.teacherConfirmed ? 1.0 : 0.82
        let scoreDelta = rounded(scopeScore * affinity * preferenceWeight * teacherMultiplier)
        guard abs(scoreDelta) >= 0.35 else {
            return nil
        }

        let explanation = buildRuleHitExplanation(
            directive: directive,
            interpretation: interpretation,
            context: context,
            scoreDelta: scoreDelta
        )

        return StudentPlanningRuleAssessment(
            hit: StudentPlanningRuleHit(
                ruleId: directive.ruleId,
                signalType: directive.type,
                scopeLevel: directive.scope.level,
                matchScore: rounded(scopeScore),
                scoreDelta: scoreDelta,
                explanation: explanation
            ),
            conservativeVote: interpretation.executionStyle == .conservative ? abs(scoreDelta) : 0,
            assertiveVote: interpretation.executionStyle == .assertive ? abs(scoreDelta) : 0,
            repairVote: interpretation.failureRecovery == .repairBeforeReteach ? abs(scoreDelta) : 0,
            reteachVote: interpretation.failureRecovery == .reteachBeforeRepair ? abs(scoreDelta) : 0
        )
    }

    private func buildSteps(
        for candidate: RankedStudentCandidate,
        executionStyle: StudentExecutionStyle
    ) -> [StudentPlannedStep] {
        candidate.item.steps.enumerated().map { index, step in
            let planStepId = String(format: "plan-step-%03d", index + 1)
            let skillId = "openstaff-skill-\(candidate.item.taskId)-\(step.stepId)"
            let confidence = stepConfidence(
                index: index,
                executionStyle: executionStyle,
                safetyScore: candidate.safetyScore,
                directnessScore: candidate.directnessScore
            )

            return StudentPlannedStep(
                planStepId: planStepId,
                skillId: skillId,
                instruction: step.instruction,
                sourceKnowledgeItemId: candidate.item.knowledgeItemId,
                sourceStepId: step.stepId,
                confidence: confidence
            )
        }
    }

    private func stepConfidence(
        index: Int,
        executionStyle: StudentExecutionStyle,
        safetyScore: Double,
        directnessScore: Double
    ) -> Double {
        let start: Double
        let decay: Double
        let contextualLift: Double

        switch executionStyle {
        case .conservative:
            start = 0.74
            decay = 0.05
            contextualLift = max(0, safetyScore - 0.5) * 0.14
        case .assertive:
            start = 0.86
            decay = 0.03
            contextualLift = max(0, directnessScore - 0.45) * 0.1
        }

        let raw = start - Double(index) * decay + contextualLift
        return rounded(clamp(raw, min: 0.48, max: 0.96))
    }

    private func resolveExecutionStyle(
        for candidate: RankedStudentCandidate
    ) -> StudentExecutionStyle {
        if candidate.conservativeVote == 0, candidate.assertiveVote == 0 {
            return candidate.safetyScore >= candidate.directnessScore ? .conservative : .assertive
        }
        return candidate.conservativeVote >= candidate.assertiveVote ? .conservative : .assertive
    }

    private func resolveFailureRecoveryPreference(
        for candidate: RankedStudentCandidate
    ) -> StudentFailureRecoveryPreference {
        if candidate.repairVote == 0, candidate.reteachVote == 0 {
            return candidate.repairReadinessScore >= 0.45 ? .repairBeforeReteach : .reteachBeforeRepair
        }
        return candidate.repairVote >= candidate.reteachVote ? .repairBeforeReteach : .reteachBeforeRepair
    }

    private func buildDecisionSummary(
        selected: RankedStudentCandidate,
        executionStyle: StudentExecutionStyle,
        failureRecoveryPreference: StudentFailureRecoveryPreference,
        profileVersion: String
    ) -> String {
        let ruleIds = Array(Set(selected.ruleHits.filter { $0.scoreDelta > 0 }.map(\.ruleId))).sorted()
        let styleText = executionStyle == .conservative ? "保守执行" : "积极执行"
        let recoveryText = failureRecoveryPreference == .repairBeforeReteach
            ? "失败后优先 repair"
            : "失败后优先 re-teach"
        let candidateSummary = "选中知识条目 \(selected.item.knowledgeItemId)，最终分 \(selected.finalScore)"
        return "命中 profile \(profileVersion) 的规则 \(ruleIds.joined(separator: "、"))，planner 采用\(styleText)，并在执行失败时\(recoveryText)。\(candidateSummary)。"
    }

    private func buildRuleHitExplanation(
        directive: PreferenceProfileDirective,
        interpretation: StudentPlannerDirectiveInterpretation,
        context: StudentPlanningCandidateContext,
        scoreDelta: Double
    ) -> String {
        let candidate = context.item.knowledgeItemId
        let summary: String

        switch directive.type {
        case .procedure:
            summary = interpretation.executionStyle == .assertive
                ? "更贴近偏好的快捷键/直接路径"
                : "更贴近偏好的稳妥步骤顺序"
        case .risk:
            summary = interpretation.executionStyle == .conservative
                ? "风险约束更低，适合保守执行"
                : "路径更直接，适合积极执行"
        case .repair:
            summary = interpretation.failureRecovery == .repairBeforeReteach
                ? "更适合先 repair 再决定是否 re-teach"
                : "更适合直接 re-teach"
        case .outcome, .locator, .style:
            summary = "与当前 student planner 约束更匹配"
        }

        return "规则 \(directive.ruleId) 命中 \(directive.scope.level.rawValue) 作用域，候选 \(candidate) 因为\(summary)，得分调整 \(scoreDelta)。"
    }

    private func interpretDirective(
        _ directive: PreferenceProfileDirective
    ) -> StudentPlannerDirectiveInterpretation {
        let normalizedText = normalized([
            directive.statement,
            directive.hint,
            directive.proposedAction
        ].compactMap { $0 }.joined(separator: " "))

        let executionStyle: StudentExecutionStyle?
        switch directive.type {
        case .risk:
            if containsAny(
                normalizedText,
                keywords: ["direct", "assertive", "aggressive", "积极", "直接", "快速", "skip confirmation"]
            ) {
                executionStyle = .assertive
            } else {
                executionStyle = .conservative
            }
        case .procedure:
            if containsAny(
                normalizedText,
                keywords: ["shortcut", "keyboard", "cmd", "command", "热键", "快捷键", "键盘", "直接"]
            ) {
                executionStyle = .assertive
            } else if containsAny(
                normalizedText,
                keywords: ["step by step", "逐步", "稳妥", "先确认", "menu", "菜单"]
            ) {
                executionStyle = .conservative
            } else {
                executionStyle = .assertive
            }
        case .repair:
            executionStyle = nil
        case .outcome, .locator, .style:
            executionStyle = nil
        }

        let failureRecovery: StudentFailureRecoveryPreference?
        switch directive.type {
        case .repair:
            if containsAny(
                normalizedText,
                keywords: [
                    "repair before reteach",
                    "repair_before_reteach",
                    "retry repair before asking for re teach",
                    "先修复再重教",
                    "先 repair 再 re teach"
                ]
            ) {
                failureRecovery = .repairBeforeReteach
            } else if containsAny(
                normalizedText,
                keywords: ["reteach", "re teach", "reteachcurrentstep", "重新示教", "重教", "重录"]
            ) {
                failureRecovery = .reteachBeforeRepair
            } else {
                failureRecovery = .repairBeforeReteach
            }
        default:
            failureRecovery = nil
        }

        return StudentPlannerDirectiveInterpretation(
            type: directive.type,
            executionStyle: executionStyle,
            failureRecovery: failureRecovery,
            normalizedText: normalizedText
        )
    }

    private func scopeMatchScore(
        for scope: PreferenceSignalScopeReference,
        context: StudentPlanningCandidateContext
    ) -> Double {
        switch scope.level {
        case .global:
            return 0.72
        case .app:
            return appScopeScore(scope: scope, context: context)
        case .taskFamily:
            return familyScopeScore(ruleFamily: scope.taskFamily, contextText: context.familyContextText)
        case .skillFamily:
            return familyScopeScore(ruleFamily: scope.skillFamily, contextText: context.familyContextText)
        case .windowPattern:
            return windowScopeScore(scope: scope, context: context)
        }
    }

    private func appScopeScore(
        scope: PreferenceSignalScopeReference,
        context: StudentPlanningCandidateContext
    ) -> Double {
        let scopedBundle = normalized(scope.appBundleId)
        let scopedName = normalized(scope.appName)
        let currentBundle = normalized(context.item.context.appBundleId)
        let currentName = normalized(context.item.context.appName)

        if !scopedBundle.isEmpty, scopedBundle == currentBundle {
            return 1.0
        }
        if !scopedName.isEmpty, scopedName == currentName {
            return 0.82
        }
        return 0
    }

    private func familyScopeScore(
        ruleFamily: String?,
        contextText: String
    ) -> Double {
        let lhs = normalized(ruleFamily)
        let rhs = normalized(contextText)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }

        if lhs == rhs {
            return 1.0
        }
        if rhs.contains(lhs) || lhs.contains(rhs) {
            return 0.88
        }

        return max(
            tokenOverlapScore(lhs, rhs),
            bigramSimilarity(lhs, rhs) * 0.84
        )
    }

    private func windowScopeScore(
        scope: PreferenceSignalScopeReference,
        context: StudentPlanningCandidateContext
    ) -> Double {
        let appScore = appScopeScore(scope: scope, context: context)
        if scope.appBundleId != nil || scope.appName != nil, appScore <= 0 {
            return 0
        }

        guard let pattern = scope.windowPattern,
              let currentWindow = context.item.context.windowTitle,
              !currentWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(currentWindow.startIndex..<currentWindow.endIndex, in: currentWindow)
            if regex.firstMatch(in: currentWindow, options: [], range: range) != nil {
                return 1.0
            }
        }

        let lhs = normalized(pattern)
        let rhs = normalized(currentWindow)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }
        if lhs == rhs {
            return 0.92
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.8
        }
        return max(0, bigramSimilarity(lhs, rhs) - 0.18)
    }

    private func rankedCandidateSort(
        lhs: RankedStudentCandidate,
        rhs: RankedStudentCandidate
    ) -> Bool {
        if lhs.finalScore == rhs.finalScore {
            if lhs.safetyScore == rhs.safetyScore {
                return lhs.item.knowledgeItemId < rhs.item.knowledgeItemId
            }
            return lhs.safetyScore > rhs.safetyScore
        }
        return lhs.finalScore > rhs.finalScore
    }

    private func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    private func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[_\.\-/]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    private func containsAny(
        _ value: String,
        keywords: [String]
    ) -> Bool {
        let normalizedValue = normalized(value)
        return keywords.contains { keyword in
            normalizedValue.contains(normalized(keyword))
        }
    }

    private func tokenOverlapScore(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let leftTokens = Set(lhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        let rightTokens = Set(rhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }

        let intersection = leftTokens.intersection(rightTokens)
        guard !intersection.isEmpty else {
            return 0
        }

        let denominator = Double(max(leftTokens.count, rightTokens.count))
        return rounded(Double(intersection.count) / denominator)
    }

    private func bigramSimilarity(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let left = bigrams(for: lhs)
        let right = bigrams(for: rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return 0
        }

        let shared = left.intersection(right)
        let denominator = Double(max(left.count, right.count))
        return rounded(Double(shared.count) / denominator)
    }

    private func bigrams(for value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else {
            return value.isEmpty ? [] : [value]
        }

        var result = Set<String>()
        for index in 0..<(characters.count - 1) {
            result.insert(String(characters[index...index + 1]))
        }
        return result
    }

    private func uniqueRuleIds(from hits: [StudentPlanningRuleHit]) -> [String] {
        Array(Set(hits.map(\.ruleId))).sorted()
    }
}

extension PreferenceAwareStudentPlanner: StudentPlanningPolicyAssemblyProviding {
    public func buildPolicyAssemblyDecision(
        input: StudentLoopInput,
        plan: StudentExecutionPlan
    ) -> PolicyAssemblyDecision? {
        guard let profile = preferenceProfile,
              !profile.plannerPreferences.isEmpty,
              let planDecision = plan.preferenceDecision else {
            return nil
        }

        let candidates = input.knowledgeItems
            .filter { !$0.steps.isEmpty }
            .map {
                evaluateCandidate(
                    item: $0,
                    input: StudentPlanningInput(
                        goal: input.goal,
                        preferredKnowledgeItemId: input.preferredKnowledgeItemId,
                        knowledgeItems: input.knowledgeItems
                    ),
                    directives: profile.plannerPreferences
                )
            }
            .sorted(by: rankedCandidateSort)

        guard let selected = candidates.first else {
            return nil
        }

        let inputRef = PolicyAssemblyInputReference(
            traceId: input.traceId,
            sessionId: input.sessionId,
            taskId: input.taskId ?? plan.selectedTaskId,
            knowledgeItemId: plan.selectedKnowledgeItemId
        )
        let appliedRuleIds = uniqueRuleIds(
            from: selected.ruleHits.filter { $0.scoreDelta > 0 }
        )
        let suppressedRuleIds = uniqueRuleIds(
            from: candidates.flatMap { candidate in
                if candidate.item.knowledgeItemId == selected.item.knowledgeItemId {
                    return candidate.ruleHits.filter { $0.scoreDelta < 0 }
                }
                return candidate.ruleHits
            }
        )
        let finalWeights = candidates.map { candidate in
            let isSelected = candidate.item.knowledgeItemId == selected.item.knowledgeItemId
            return PolicyAssemblyFinalWeight(
                weightId: candidate.item.knowledgeItemId,
                label: candidate.item.taskId,
                kind: .candidate,
                baseValue: candidate.baseScore,
                finalValue: candidate.finalScore,
                selected: isSelected,
                appliedRuleIds: uniqueRuleIds(from: candidate.ruleHits.filter { $0.scoreDelta > 0 }),
                notes: [policyAssemblyCandidateSummary(candidate, selected: selected)]
            )
        }
        let ruleEvaluations = candidates.flatMap { candidate in
            candidate.ruleHits.map { hit in
                PolicyAssemblyRuleEvaluation(
                    ruleId: hit.ruleId,
                    targetId: candidate.item.knowledgeItemId,
                    targetLabel: candidate.item.taskId,
                    disposition: candidate.item.knowledgeItemId == selected.item.knowledgeItemId && hit.scoreDelta > 0
                        ? .applied
                        : .suppressed,
                    matchScore: hit.matchScore,
                    delta: hit.scoreDelta,
                    explanation: hit.explanation
                )
            }
        }

        return PolicyAssemblyDecision(
            decisionId: "policy-student-\(input.traceId)-\(selected.item.knowledgeItemId)",
            targetModule: .student,
            inputRef: inputRef,
            profileVersion: planDecision.profileVersion,
            strategyVersion: plan.plannerVersion,
            appliedRuleIds: appliedRuleIds,
            suppressedRuleIds: suppressedRuleIds,
            finalDecisionSummary: planDecision.summary,
            ruleEvaluations: ruleEvaluations,
            finalWeights: finalWeights,
            timestamp: input.timestamp
        )
    }

    private func policyAssemblyCandidateSummary(
        _ candidate: RankedStudentCandidate,
        selected: RankedStudentCandidate
    ) -> String {
        let appliedRuleIds = uniqueRuleIds(from: candidate.ruleHits.filter { $0.scoreDelta > 0 })
        let suppressedRuleIds = uniqueRuleIds(from: candidate.ruleHits.filter { $0.scoreDelta < 0 })
        let scoreSegment = "base \(candidate.baseScore) -> final \(candidate.finalScore)"

        if candidate.item.knowledgeItemId == selected.item.knowledgeItemId {
            return "选中候选 \(candidate.item.knowledgeItemId)，命中规则 \(appliedRuleIds.joined(separator: "、"))，\(scoreSegment)。"
        }
        if !appliedRuleIds.isEmpty {
            return "候选 \(candidate.item.knowledgeItemId) 命中规则 \(appliedRuleIds.joined(separator: "、"))，但最终权重不及选中项，\(scoreSegment)。"
        }
        if !suppressedRuleIds.isEmpty {
            return "候选 \(candidate.item.knowledgeItemId) 仅命中压低规则 \(suppressedRuleIds.joined(separator: "、"))，\(scoreSegment)。"
        }
        return "候选 \(candidate.item.knowledgeItemId) 未命中偏好规则，\(scoreSegment)。"
    }
}

private struct StudentPlanningRuleAssessment {
    let hit: StudentPlanningRuleHit
    let conservativeVote: Double
    let assertiveVote: Double
    let repairVote: Double
    let reteachVote: Double
}

private struct RankedStudentCandidate {
    let item: KnowledgeItem
    let baseScore: Double
    let finalScore: Double
    let ruleHits: [StudentPlanningRuleHit]
    let safetyScore: Double
    let directnessScore: Double
    let repairReadinessScore: Double
    let conservativeVote: Double
    let assertiveVote: Double
    let repairVote: Double
    let reteachVote: Double
}

private struct StudentPlannerDirectiveInterpretation {
    let type: PreferenceSignalType
    let executionStyle: StudentExecutionStyle?
    let failureRecovery: StudentFailureRecoveryPreference?
    let normalizedText: String

    func affinity(for context: StudentPlanningCandidateContext) -> Double {
        switch type {
        case .procedure:
            if executionStyle == .assertive {
                return ((context.directnessScore * 2) - 1) * 0.9
            }
            return ((context.safetyScore * 2) - 1) * 0.65
        case .risk:
            if executionStyle == .assertive {
                return ((context.directnessScore * 2) - 1) * 0.72
            }
            return ((context.safetyScore * 2) - 1) * 0.88
        case .repair:
            if failureRecovery == .reteachBeforeRepair {
                return ((context.reteachReadinessScore * 2) - 1) * 0.76
            }
            return ((context.repairReadinessScore * 2) - 1) * 0.78
        case .outcome, .locator, .style:
            return max(
                (context.textSimilarity(to: normalizedText) * 0.45) - 0.18,
                0
            )
        }
    }
}

private struct StudentPlanningCandidateContext {
    let item: KnowledgeItem
    let baseScore: Double
    let safetyScore: Double
    let directnessScore: Double
    let repairReadinessScore: Double
    let reteachReadinessScore: Double
    let familyContextText: String
    let candidateText: String

    init(
        item: KnowledgeItem,
        goal: String,
        preferredKnowledgeItemId: String?
    ) {
        self.item = item

        let normalizedGoal = StudentPlanningCandidateContext.normalized(goal)
        self.baseScore = StudentPlanningCandidateContext.baseScore(
            item: item,
            normalizedGoal: normalizedGoal,
            preferredKnowledgeItemId: preferredKnowledgeItemId
        )

        let instructions = item.steps.map(\.instruction)
        let shortcutScore = StudentPlanningCandidateContext.shortcutAffinity(for: instructions)
        let shortPathScore = StudentPlanningCandidateContext.shortPathScore(stepCount: item.steps.count)
        let riskyKeywordScore = StudentPlanningCandidateContext.riskyKeywordScore(
            text: ([item.goal, item.summary] + instructions).joined(separator: " ")
        )
        let manualConstraintPenalty = item.constraints.contains(where: { $0.type == .manualConfirmationRequired }) ? 0.28 : 0
        let coordinateConstraintPenalty = item.constraints.contains(where: { $0.type == .coordinateTargetMayDrift }) ? 0.18 : 0
        let repairCoverageScore = StudentPlanningCandidateContext.repairCoverageScore(for: item)
        let reteachSimplicityScore = StudentPlanningCandidateContext.reteachSimplicityScore(
            stepCount: item.steps.count,
            shortcutScore: shortcutScore
        )

        self.directnessScore = StudentPlanningCandidateContext.rounded(
            StudentPlanningCandidateContext.clamp(
                (shortcutScore * 0.58) + (shortPathScore * 0.42),
                min: 0,
                max: 1
            )
        )
        self.safetyScore = StudentPlanningCandidateContext.rounded(
            StudentPlanningCandidateContext.clamp(
                1.0 - riskyKeywordScore - manualConstraintPenalty - coordinateConstraintPenalty,
                min: 0.08,
                max: 1.0
            )
        )
        self.repairReadinessScore = StudentPlanningCandidateContext.rounded(
            StudentPlanningCandidateContext.clamp(
                (repairCoverageScore * 0.72) + (self.safetyScore * 0.28),
                min: 0,
                max: 1
            )
        )
        self.reteachReadinessScore = StudentPlanningCandidateContext.rounded(
            StudentPlanningCandidateContext.clamp(
                (reteachSimplicityScore * 0.7) + ((1.0 - repairCoverageScore) * 0.3),
                min: 0,
                max: 1
            )
        )

        self.familyContextText = [
            item.taskId,
            item.goal,
            item.summary,
            item.context.appName,
            item.context.appBundleId
        ]
        .appending(contentsOf: instructions)
        .joined(separator: " ")

        self.candidateText = [
            item.knowledgeItemId,
            item.taskId,
            item.goal,
            item.summary,
            item.context.appName,
            item.context.appBundleId,
            item.context.windowTitle ?? ""
        ]
        .appending(contentsOf: instructions)
        .joined(separator: " ")
    }

    func textSimilarity(to value: String) -> Double {
        let lhs = Self.normalized(candidateText)
        let rhs = Self.normalized(value)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }

        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.92
        }

        return max(
            Self.tokenOverlapScore(lhs, rhs),
            Self.bigramSimilarity(lhs, rhs)
        )
    }

    private static func baseScore(
        item: KnowledgeItem,
        normalizedGoal: String,
        preferredKnowledgeItemId: String?
    ) -> Double {
        var value = 0.0

        if preferredKnowledgeItemId == item.knowledgeItemId {
            value += 100
        }
        if normalizedGoal.contains(normalized(item.context.appName)) {
            value += 20
        }
        if normalizedGoal.contains(normalized(item.context.appBundleId)) {
            value += 18
        }
        if normalizedGoal.contains(normalized(item.goal)) {
            value += 12
        }
        if let firstStep = item.steps.first?.instruction,
           normalizedGoal.contains(normalized(firstStep)) {
            value += 8
        }

        value += Double(min(item.steps.count, 5))
        return value
    }

    private static func shortcutAffinity(for instructions: [String]) -> Double {
        guard !instructions.isEmpty else {
            return 0
        }

        let shortcutMatches = instructions.filter { instruction in
            containsAny(
                normalized(instruction),
                keywords: ["cmd", "command", "shortcut", "keyboard", "⌘", "快捷键", "键盘", "热键"]
            )
        }.count

        return rounded(Double(shortcutMatches) / Double(instructions.count))
    }

    private static func shortPathScore(stepCount: Int) -> Double {
        switch stepCount {
        case ...2:
            return 1.0
        case 3:
            return 0.82
        case 4:
            return 0.68
        case 5:
            return 0.56
        default:
            return 0.4
        }
    }

    private static func riskyKeywordScore(text: String) -> Double {
        let normalizedText = normalized(text)
        if containsAny(
            normalizedText,
            keywords: ["delete", "remove", "reset", "支付", "删除", "重置", "关闭账号", "付款"]
        ) {
            return 0.42
        }
        if containsAny(
            normalizedText,
            keywords: ["confirm", "确认", "submit", "保存", "send", "发送"]
        ) {
            return 0.14
        }
        return 0
    }

    private static func repairCoverageScore(for item: KnowledgeItem) -> Double {
        guard !item.steps.isEmpty else {
            return 0
        }

        let readySteps = item.steps.filter { step in
            guard let target = step.target else {
                return false
            }

            return !target.semanticTargets.isEmpty
                || target.preferredLocatorType != nil
        }.count

        let ratio = Double(readySteps) / Double(item.steps.count)
        return rounded(ratio)
    }

    private static func reteachSimplicityScore(
        stepCount: Int,
        shortcutScore: Double
    ) -> Double {
        let shortness = shortPathScore(stepCount: stepCount)
        return rounded(clamp((shortness * 0.76) + ((1.0 - shortcutScore) * 0.24), min: 0, max: 1))
    }

    private static func containsAny(
        _ value: String,
        keywords: [String]
    ) -> Bool {
        keywords.contains { keyword in
            value.contains(normalized(keyword))
        }
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[_\.\-/]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
    }

    private static func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let leftTokens = Set(lhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        let rightTokens = Set(rhs.split(separator: " ").map(String.init).filter { !$0.isEmpty })
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else {
            return 0
        }

        let intersection = leftTokens.intersection(rightTokens)
        guard !intersection.isEmpty else {
            return 0
        }

        return rounded(Double(intersection.count) / Double(max(leftTokens.count, rightTokens.count)))
    }

    private static func bigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = bigrams(for: lhs)
        let right = bigrams(for: rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return 0
        }

        let shared = left.intersection(right)
        return rounded(Double(shared.count) / Double(max(left.count, right.count)))
    }

    private static func bigrams(for value: String) -> Set<String> {
        let characters = Array(value)
        guard characters.count >= 2 else {
            return value.isEmpty ? [] : [value]
        }

        var result = Set<String>()
        for index in 0..<(characters.count - 1) {
            result.insert(String(characters[index...index + 1]))
        }
        return result
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

private extension Array where Element == String {
    func appending(contentsOf values: [String]) -> [String] {
        var copy = self
        copy.append(contentsOf: values)
        return copy
    }
}
