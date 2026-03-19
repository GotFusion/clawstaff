import Foundation

public struct SkillRepairPreferenceRuleHit: Codable, Equatable, Sendable {
    public let ruleId: String
    public let signalType: PreferenceSignalType
    public let scopeLevel: PreferenceSignalScope
    public let matchScore: Double
    public let priorityDelta: Double
    public let explanation: String

    public init(
        ruleId: String,
        signalType: PreferenceSignalType,
        scopeLevel: PreferenceSignalScope,
        matchScore: Double,
        priorityDelta: Double,
        explanation: String
    ) {
        self.ruleId = ruleId
        self.signalType = signalType
        self.scopeLevel = scopeLevel
        self.matchScore = matchScore
        self.priorityDelta = priorityDelta
        self.explanation = explanation
    }
}

public struct SkillRepairCandidateExplanation: Codable, Equatable, Sendable {
    public let actionId: String
    public let actionType: SkillRepairActionType
    public let actionTitle: String
    public let basePriority: Double
    public let finalPriority: Double
    public let appliedRuleIds: [String]
    public let ruleHits: [SkillRepairPreferenceRuleHit]
    public let summary: String

    public init(
        actionId: String,
        actionType: SkillRepairActionType,
        actionTitle: String,
        basePriority: Double,
        finalPriority: Double,
        appliedRuleIds: [String],
        ruleHits: [SkillRepairPreferenceRuleHit],
        summary: String
    ) {
        self.actionId = actionId
        self.actionType = actionType
        self.actionTitle = actionTitle
        self.basePriority = basePriority
        self.finalPriority = finalPriority
        self.appliedRuleIds = Array(Set(appliedRuleIds)).sorted()
        self.ruleHits = ruleHits.sorted(by: Self.ruleHitSort)
        self.summary = summary
    }

    private static func ruleHitSort(
        lhs: SkillRepairPreferenceRuleHit,
        rhs: SkillRepairPreferenceRuleHit
    ) -> Bool {
        let lhsMagnitude = abs(lhs.priorityDelta)
        let rhsMagnitude = abs(rhs.priorityDelta)
        if lhsMagnitude == rhsMagnitude {
            return lhs.ruleId < rhs.ruleId
        }
        return lhsMagnitude > rhsMagnitude
    }
}

public struct SkillRepairPreferenceDecision: Codable, Equatable, Sendable {
    public let profileVersion: String
    public let selectedActionId: String
    public let selectedActionType: SkillRepairActionType
    public let appliedRuleIds: [String]
    public let summary: String
    public let candidateExplanations: [SkillRepairCandidateExplanation]

    public init(
        profileVersion: String,
        selectedActionId: String,
        selectedActionType: SkillRepairActionType,
        appliedRuleIds: [String],
        summary: String,
        candidateExplanations: [SkillRepairCandidateExplanation]
    ) {
        self.profileVersion = profileVersion
        self.selectedActionId = selectedActionId
        self.selectedActionType = selectedActionType
        self.appliedRuleIds = Array(Set(appliedRuleIds)).sorted()
        self.summary = summary
        self.candidateExplanations = candidateExplanations
    }
}

public struct PreferenceAwareSkillRepairPlanner: Sendable {
    public let basePlanner: SkillRepairPlanner
    public let preferenceProfile: PreferenceProfile?
    public let preferenceWeight: Double

    public init(
        basePlanner: SkillRepairPlanner = SkillRepairPlanner(),
        preferenceProfile: PreferenceProfile? = nil,
        preferenceWeight: Double = 0.34
    ) {
        self.basePlanner = basePlanner
        self.preferenceProfile = preferenceProfile
        self.preferenceWeight = max(0, preferenceWeight)
    }

    public func buildPlan(
        report: SkillDriftReport,
        payload: SkillBundlePayload? = nil
    ) -> SkillRepairPlan {
        let basePlan = basePlanner.buildPlan(report: report)
        guard basePlan.status == .actionRequired,
              !basePlan.actions.isEmpty,
              let profile = preferenceProfile,
              !profile.repairPreferences.isEmpty else {
            return basePlan
        }

        let context = RepairPreferenceContext(report: report, payload: payload)
        let rankedActions = basePlan.actions.enumerated().map { index, action in
            evaluate(
                action: action,
                baseIndex: index,
                directives: profile.repairPreferences,
                report: report,
                context: context
            )
        }

        let sortedActions = rankedActions.sorted(by: rankedActionSort)
        guard let selected = sortedActions.first else {
            return basePlan
        }

        let candidateExplanations = sortedActions.map { candidate in
            buildCandidateExplanation(candidate)
        }
        let appliedRuleIds = Array(
            Set(candidateExplanations.flatMap(\.appliedRuleIds))
        ).sorted()

        guard !appliedRuleIds.isEmpty else {
            return basePlan
        }

        let decisionSummary = buildDecisionSummary(
            selected: selected,
            profileVersion: profile.profileVersion
        )
        let decision = SkillRepairPreferenceDecision(
            profileVersion: profile.profileVersion,
            selectedActionId: selected.action.actionId,
            selectedActionType: selected.action.type,
            appliedRuleIds: appliedRuleIds,
            summary: decisionSummary,
            candidateExplanations: candidateExplanations
        )
        let summary = "\(basePlan.summary) \(decisionSummary)"
        let actions = zip(sortedActions, candidateExplanations).map { candidate, explanation in
            SkillRepairAction(
                actionId: candidate.action.actionId,
                type: candidate.action.type,
                title: candidate.action.title,
                description: candidate.action.description,
                reason: candidate.action.reason,
                affectedStepIds: candidate.action.affectedStepIds,
                shouldIncrementRepairVersion: candidate.action.shouldIncrementRepairVersion,
                appliedRuleIds: explanation.appliedRuleIds.isEmpty ? nil : explanation.appliedRuleIds,
                preferenceReason: explanation.appliedRuleIds.isEmpty ? nil : explanation.summary
            )
        }

        return SkillRepairPlan(
            skillName: basePlan.skillName,
            status: basePlan.status,
            dominantDriftKind: basePlan.dominantDriftKind,
            currentRepairVersion: basePlan.currentRepairVersion,
            recommendedRepairVersion: basePlan.recommendedRepairVersion,
            summary: summary,
            actions: actions,
            preferenceDecision: decision
        )
    }

    private func evaluate(
        action: SkillRepairAction,
        baseIndex: Int,
        directives: [PreferenceProfileDirective],
        report: SkillDriftReport,
        context: RepairPreferenceContext
    ) -> RankedSkillRepairAction {
        let basePriority = rounded(1.0 - (Double(baseIndex) * 0.05))
        let ruleHits = directives.compactMap { directive in
            evaluateDirective(
                directive,
                action: action,
                report: report,
                context: context
            )
        }
        let priorityDelta = ruleHits.reduce(0.0) { partial, hit in
            partial + hit.priorityDelta
        }

        return RankedSkillRepairAction(
            action: action,
            baseIndex: baseIndex,
            basePriority: basePriority,
            finalPriority: rounded(basePriority + priorityDelta),
            ruleHits: ruleHits.sorted(by: ruleHitSort)
        )
    }

    private func evaluateDirective(
        _ directive: PreferenceProfileDirective,
        action: SkillRepairAction,
        report: SkillDriftReport,
        context: RepairPreferenceContext
    ) -> SkillRepairPreferenceRuleHit? {
        let scopeScore = scopeMatchScore(for: directive.scope, context: context)
        guard scopeScore > 0 else {
            return nil
        }

        let interpretation = interpretedPreference(for: directive)
        let affinity = interpretation.affinity(for: action.type, dominantDriftKind: report.dominantDriftKind)
        guard abs(affinity) >= 0.08 else {
            return nil
        }

        let teacherMultiplier = directive.teacherConfirmed ? 1.0 : 0.82
        let priorityDelta = rounded(scopeScore * affinity * preferenceWeight * teacherMultiplier)
        guard abs(priorityDelta) >= 0.01 else {
            return nil
        }

        let explanation = buildRuleHitExplanation(
            directive: directive,
            action: action,
            interpretation: interpretation,
            priorityDelta: priorityDelta
        )
        return SkillRepairPreferenceRuleHit(
            ruleId: directive.ruleId,
            signalType: directive.type,
            scopeLevel: directive.scope.level,
            matchScore: rounded(scopeScore),
            priorityDelta: priorityDelta,
            explanation: explanation
        )
    }

    private func buildCandidateExplanation(
        _ candidate: RankedSkillRepairAction
    ) -> SkillRepairCandidateExplanation {
        let appliedRuleIds = uniqueRuleIds(from: candidate.ruleHits)
        let summary: String
        if let topHit = candidate.ruleHits.first {
            summary = "命中规则 \(appliedRuleIds.joined(separator: "、"))，\(topHit.explanation)"
        } else {
            summary = "未命中 repair 偏好规则，沿用默认顺序。"
        }

        return SkillRepairCandidateExplanation(
            actionId: candidate.action.actionId,
            actionType: candidate.action.type,
            actionTitle: candidate.action.title,
            basePriority: candidate.basePriority,
            finalPriority: candidate.finalPriority,
            appliedRuleIds: appliedRuleIds,
            ruleHits: candidate.ruleHits,
            summary: summary
        )
    }

    private func buildDecisionSummary(
        selected: RankedSkillRepairAction,
        profileVersion: String
    ) -> String {
        let appliedRuleIds = uniqueRuleIds(from: selected.ruleHits)
        guard let topHit = selected.ruleHits.first else {
            return "偏好 profile \(profileVersion) 已加载，但当前 repair 顺序未命中规则。"
        }

        return "偏好 profile \(profileVersion) 命中 \(appliedRuleIds.joined(separator: "、"))，因此优先「\(selected.action.title)」：\(topHit.explanation)"
    }

    private func scopeMatchScore(
        for scope: PreferenceSignalScopeReference,
        context: RepairPreferenceContext
    ) -> Double {
        switch scope.level {
        case .global:
            return 0.72
        case .app:
            return appScopeScore(scope: scope, context: context)
        case .taskFamily:
            return familyScopeScore(ruleFamily: scope.taskFamily, currentFamily: context.taskFamily)
        case .skillFamily:
            return familyScopeScore(ruleFamily: scope.skillFamily, currentFamily: context.skillFamily)
        case .windowPattern:
            return windowScopeScore(scope: scope, context: context)
        }
    }

    private func appScopeScore(
        scope: PreferenceSignalScopeReference,
        context: RepairPreferenceContext
    ) -> Double {
        let scopedBundle = normalized(scope.appBundleId)
        let scopedName = normalized(scope.appName)
        let currentBundle = normalized(context.appBundleId)
        let currentName = normalized(context.appName)

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
        currentFamily: String?
    ) -> Double {
        let lhs = normalized(ruleFamily)
        let rhs = normalized(currentFamily)
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }

        if lhs == rhs {
            return 1.0
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.84
        }
        return 0
    }

    private func windowScopeScore(
        scope: PreferenceSignalScopeReference,
        context: RepairPreferenceContext
    ) -> Double {
        let appScore = appScopeScore(scope: scope, context: context)
        if scope.appBundleId != nil || scope.appName != nil, appScore <= 0 {
            return 0
        }

        guard let pattern = scope.windowPattern,
              let currentWindow = context.windowTitle,
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

    private func interpretedPreference(
        for directive: PreferenceProfileDirective
    ) -> RepairDirectiveInterpretation {
        let actionText = normalized(directive.proposedAction)
        let text = normalized([
            directive.proposedAction,
            directive.hint,
            directive.statement
        ].compactMap { $0 }.joined(separator: " "))

        if containsAnyToken(
            actionText,
            tokens: [
                "repair before reteach",
                "repair_before_reteach"
            ]
        ) {
            return .repairBeforeReteach
        }

        if containsAnyToken(
            actionText,
            tokens: [
                "reteachcurrentstep",
                "reteach",
                "re teach",
                "re-teach"
            ]
        ) {
            return .reteachFirst
        }

        if containsAnyToken(
            actionText,
            tokens: [
                "updateskilllocator",
                "update skill locator",
                "refresh skill locator",
                "refresh_skill_locator",
                "repair locator",
                "repair_locator"
            ]
        ) {
            return .locatorFirst
        }

        if containsAnyToken(
            actionText,
            tokens: [
                "relocalize",
                "replay",
                "retry",
                "rerun",
                "re-run"
            ]
        ) {
            return .replayFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "repair before reteach",
                "repair_before_reteach",
                "retry locator repair before asking for re teach",
                "retry locator repair before asking for reteach",
                "先修",
                "先修 locator"
            ]
        ) {
            return .repairBeforeReteach
        }

        if containsAnyToken(
            text,
            tokens: [
                "reteach",
                "re teach",
                "re-teach",
                "teach again",
                "重新示教",
                "重新教学"
            ]
        ) {
            return .reteachFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "updateskilllocator",
                "update skill locator",
                "refresh skill locator",
                "refresh semantic",
                "repair locator",
                "text anchor",
                "semantic anchor",
                "locator",
                "anchor",
                "刷新 locator",
                "修 locator"
            ]
        ) {
            return .locatorFirst
        }

        if containsAnyToken(
            text,
            tokens: [
                "relocalize",
                "replay",
                "retry",
                "rerun",
                "re-run",
                "verify again",
                "重新定位",
                "回放",
                "重放"
            ]
        ) {
            return .replayFirst
        }

        switch directive.type {
        case .locator:
            return .locatorFirst
        case .repair:
            return .repairBeforeReteach
        case .outcome, .procedure, .style, .risk:
            return .unspecified
        }
    }

    private func buildRuleHitExplanation(
        directive: PreferenceProfileDirective,
        action: SkillRepairAction,
        interpretation: RepairDirectiveInterpretation,
        priorityDelta: Double
    ) -> String {
        let direction = priorityDelta >= 0 ? "抬高" : "压低"
        let preferenceText = interpretation.userFacingSummary(action: action.type)
        return "规则 \(directive.ruleId) \(preferenceText)，因此\(direction)当前修法优先级。"
    }

    private func uniqueRuleIds(
        from hits: [SkillRepairPreferenceRuleHit]
    ) -> [String] {
        Array(Set(hits.map(\.ruleId))).sorted()
    }

    private func rankedActionSort(
        lhs: RankedSkillRepairAction,
        rhs: RankedSkillRepairAction
    ) -> Bool {
        if lhs.finalPriority == rhs.finalPriority {
            if lhs.basePriority == rhs.basePriority {
                if lhs.action.type == rhs.action.type {
                    return lhs.baseIndex < rhs.baseIndex
                }
                return lhs.action.type.rawValue < rhs.action.type.rawValue
            }
            return lhs.basePriority > rhs.basePriority
        }
        return lhs.finalPriority > rhs.finalPriority
    }

    private func ruleHitSort(
        lhs: SkillRepairPreferenceRuleHit,
        rhs: SkillRepairPreferenceRuleHit
    ) -> Bool {
        let lhsMagnitude = abs(lhs.priorityDelta)
        let rhsMagnitude = abs(rhs.priorityDelta)
        if lhsMagnitude == rhsMagnitude {
            return lhs.ruleId < rhs.ruleId
        }
        return lhsMagnitude > rhsMagnitude
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func normalized(_ value: String?) -> String {
        guard let value else {
            return ""
        }

        let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else {
            return ""
        }

        let filteredScalars = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }

        return String(filteredScalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func containsAnyToken(
        _ text: String,
        tokens: [String]
    ) -> Bool {
        tokens.contains { token in
            text.contains(normalized(token))
        }
    }

    private func tokenOverlapScore(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return 0
        }

        let sharedCount = lhsTokens.intersection(rhsTokens).count
        let denominator = max(lhsTokens.count, rhsTokens.count)
        guard denominator > 0 else {
            return 0
        }
        return Double(sharedCount) / Double(denominator)
    }

    private func bigramSimilarity(
        _ lhs: String,
        _ rhs: String
    ) -> Double {
        let lhsBigrams = bigrams(for: lhs)
        let rhsBigrams = bigrams(for: rhs)
        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return 0
        }

        let sharedCount = lhsBigrams.intersection(rhsBigrams).count
        let denominator = max(lhsBigrams.count, rhsBigrams.count)
        guard denominator > 0 else {
            return 0
        }
        return Double(sharedCount) / Double(denominator)
    }

    private func bigrams(for text: String) -> Set<String> {
        let characters = Array(text.replacingOccurrences(of: " ", with: ""))
        guard characters.count > 1 else {
            return []
        }

        var values = Set<String>()
        for index in 0..<(characters.count - 1) {
            values.insert(String([characters[index], characters[index + 1]]))
        }
        return values
    }
}

private struct RepairPreferenceContext: Sendable {
    let appBundleId: String?
    let appName: String?
    let windowTitle: String?
    let taskFamily: String?
    let skillFamily: String?

    init(
        report: SkillDriftReport,
        payload: SkillBundlePayload?
    ) {
        self.appBundleId = payload?.mappedOutput.context.appBundleId ?? report.snapshot.appBundleId
        self.appName = payload?.mappedOutput.context.appName ?? report.snapshot.appName
        self.windowTitle = report.snapshot.windowTitle ?? payload?.mappedOutput.context.windowTitle
        self.taskFamily = payload?.provenance?.skillBuild?.taskFamily
        self.skillFamily = payload?.provenance?.skillBuild?.skillFamily
    }
}

private struct RankedSkillRepairAction {
    let action: SkillRepairAction
    let baseIndex: Int
    let basePriority: Double
    let finalPriority: Double
    let ruleHits: [SkillRepairPreferenceRuleHit]
}

private enum RepairDirectiveInterpretation {
    case locatorFirst
    case replayFirst
    case reteachFirst
    case repairBeforeReteach
    case unspecified

    func affinity(
        for action: SkillRepairActionType,
        dominantDriftKind: SkillDriftKind
    ) -> Double {
        switch self {
        case .locatorFirst:
            switch action {
            case .updateSkillLocator:
                return 1.0
            case .relocalize:
                if dominantDriftKind == .elementPositionChanged {
                    return 0.7
                }
                return 0.16
            case .reteachCurrentStep:
                return -0.28
            }
        case .replayFirst:
            switch action {
            case .relocalize:
                return 1.0
            case .updateSkillLocator:
                return 0.12
            case .reteachCurrentStep:
                return -0.3
            }
        case .reteachFirst:
            switch action {
            case .reteachCurrentStep:
                return 1.0
            case .updateSkillLocator, .relocalize:
                return -0.26
            }
        case .repairBeforeReteach:
            switch action {
            case .updateSkillLocator, .relocalize:
                return 0.88
            case .reteachCurrentStep:
                return -0.52
            }
        case .unspecified:
            return 0
        }
    }

    func userFacingSummary(action: SkillRepairActionType) -> String {
        switch self {
        case .locatorFirst:
            if action == .updateSkillLocator {
                return "偏好先修 locator"
            }
            return "偏好把 locator 修复排在前面"
        case .replayFirst:
            if action == .relocalize {
                return "偏好先 replay / relocalize"
            }
            return "偏好优先 replay / relocalize 而非当前修法"
        case .reteachFirst:
            if action == .reteachCurrentStep {
                return "偏好直接重新示教"
            }
            return "偏好把重新示教排在当前修法之前"
        case .repairBeforeReteach:
            if action == .reteachCurrentStep {
                return "偏好先修再示教"
            }
            return "偏好先做 repair 再考虑重新示教"
        case .unspecified:
            return "提供了泛化 repair 偏好"
        }
    }
}

public extension PreferenceAwareSkillRepairPlanner {
    func buildPolicyAssemblyDecision(
        report: SkillDriftReport,
        payload: SkillBundlePayload?,
        plan: SkillRepairPlan
    ) -> PolicyAssemblyDecision {
        let inputRef = PolicyAssemblyInputReference(
            sessionId: report.sessionId,
            taskId: report.taskId,
            knowledgeItemId: report.knowledgeItemId,
            skillName: report.skillName,
            skillDirectoryPath: report.skillDirectoryPath
        )

        guard let decision = plan.preferenceDecision else {
            let profileVersion = payload?.provenance?.skillBuild?.preferenceProfileVersion
            let suppressedRuleIds = Array(
                Set(plan.actions.dropFirst().flatMap { $0.appliedRuleIds ?? [] })
            ).sorted()
            let finalWeights = plan.actions.enumerated().map { index, action in
                PolicyAssemblyFinalWeight(
                    weightId: action.actionId,
                    label: action.title,
                    kind: .action,
                    finalValue: max(0.2, 1.0 - (Double(index) * 0.05)),
                    selected: index == 0,
                    appliedRuleIds: action.appliedRuleIds ?? [],
                    notes: [action.preferenceReason ?? action.reason]
                )
            }

            return PolicyAssemblyDecision(
                decisionId: "policy-repair-\(report.sessionId)-\(report.skillName)",
                targetModule: .repair,
                inputRef: inputRef,
                profileVersion: profileVersion,
                strategyVersion: "repair-heuristic-v1",
                appliedRuleIds: plan.actions.first?.appliedRuleIds ?? [],
                suppressedRuleIds: suppressedRuleIds,
                finalDecisionSummary: plan.summary,
                ruleEvaluations: [],
                finalWeights: finalWeights,
                timestamp: report.detectedAt
            )
        }

        let selectedCandidate = decision.candidateExplanations.first { candidate in
            candidate.actionId == decision.selectedActionId
        }
        let appliedRuleIds = Array(
            Set(selectedCandidate?.ruleHits.filter { $0.priorityDelta > 0 }.map { $0.ruleId } ?? [])
        ).sorted()
        let suppressedRuleIds = Array(
            Set(
                decision.candidateExplanations.flatMap { candidate in
                    if candidate.actionId == decision.selectedActionId {
                        return candidate.ruleHits
                            .filter { $0.priorityDelta < 0 }
                            .map { $0.ruleId }
                    }
                    return candidate.ruleHits.map { $0.ruleId }
                }
            )
        ).sorted()
        let finalWeights = decision.candidateExplanations.map { candidate in
            PolicyAssemblyFinalWeight(
                weightId: candidate.actionId,
                label: candidate.actionTitle,
                kind: .action,
                baseValue: candidate.basePriority,
                finalValue: candidate.finalPriority,
                selected: candidate.actionId == decision.selectedActionId,
                appliedRuleIds: candidate.ruleHits
                    .filter { $0.priorityDelta > 0 }
                    .map { $0.ruleId },
                notes: [candidate.summary]
            )
        }
        let ruleEvaluations = decision.candidateExplanations.flatMap { candidate in
            candidate.ruleHits.map { hit in
                PolicyAssemblyRuleEvaluation(
                    ruleId: hit.ruleId,
                    targetId: candidate.actionId,
                    targetLabel: candidate.actionTitle,
                    disposition: candidate.actionId == decision.selectedActionId && hit.priorityDelta > 0
                        ? .applied
                        : .suppressed,
                    matchScore: hit.matchScore,
                    delta: hit.priorityDelta,
                    explanation: hit.explanation
                )
            }
        }

        return PolicyAssemblyDecision(
            decisionId: "policy-repair-\(report.sessionId)-\(decision.selectedActionId)",
            targetModule: .repair,
            inputRef: inputRef,
            profileVersion: decision.profileVersion,
            strategyVersion: "preference-aware-repair-v1",
            appliedRuleIds: appliedRuleIds,
            suppressedRuleIds: suppressedRuleIds,
            finalDecisionSummary: decision.summary,
            ruleEvaluations: ruleEvaluations,
            finalWeights: finalWeights,
            timestamp: report.detectedAt
        )
    }
}
