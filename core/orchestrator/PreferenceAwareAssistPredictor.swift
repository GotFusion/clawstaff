import Foundation

public struct PreferenceAwareAssistPredictor: AssistNextActionPredicting {
    public let retriever: AssistKnowledgeRetriever
    public let preferenceProfile: PreferenceProfile?
    public let minimumScore: Double
    public let evidenceLimit: Int
    public let stepPreferenceWeight: Double
    public let appPreferenceWeight: Double
    public let riskPreferenceWeight: Double

    public init(
        retriever: AssistKnowledgeRetriever = AssistKnowledgeRetriever(),
        preferenceProfile: PreferenceProfile? = nil,
        minimumScore: Double = 0.18,
        evidenceLimit: Int = 3,
        stepPreferenceWeight: Double = 0.16,
        appPreferenceWeight: Double = 0.08,
        riskPreferenceWeight: Double = 0.14
    ) {
        self.retriever = retriever
        self.preferenceProfile = preferenceProfile
        self.minimumScore = minimumScore
        self.evidenceLimit = max(1, evidenceLimit)
        self.stepPreferenceWeight = max(0, stepPreferenceWeight)
        self.appPreferenceWeight = max(0, appPreferenceWeight)
        self.riskPreferenceWeight = max(0, riskPreferenceWeight)
    }

    public func predict(input: AssistPredictionInput) -> AssistSuggestion? {
        let retrieval = retriever.retrieve(input: input)
        guard let fallbackPrimary = retrieval.matches.first else {
            return nil
        }

        let rerank = rerank(matches: retrieval.matches, input: input)
        let primary = rerank.matches.first ?? RankedAssistEvidence(
            evidence: fallbackPrimary,
            baseScore: fallbackPrimary.score,
            finalScore: fallbackPrimary.score,
            ruleHits: [],
            loweredReasons: [],
            originalIndex: 0
        )
        guard primary.finalScore >= minimumScore else {
            return nil
        }

        let selectedEvidence = selectEvidence(from: rerank.matches, primary: primary)
        let reason = buildReason(
            primary: primary,
            evidence: selectedEvidence,
            input: input,
            preferenceDecision: rerank.decision
        )
        let predictorVersion = rerank.decision == nil
            ? AssistPredictionStrategy.retrievalV1.rawValue
            : AssistPredictionStrategy.preferenceAwareRetrievalV1.rawValue

        let action = AssistSuggestedAction(
            type: inferActionType(from: primary.evidence.stepInstruction),
            instruction: primary.evidence.stepInstruction,
            reason: reason
        )

        return AssistSuggestion(
            suggestionId: "assist-\(primary.evidence.taskId)-\(primary.evidence.stepId)",
            knowledgeItemId: primary.evidence.knowledgeItemId,
            taskId: primary.evidence.taskId,
            stepId: primary.evidence.stepId,
            action: action,
            confidence: primary.finalScore,
            evidence: selectedEvidence.map(\.evidence),
            predictorVersion: predictorVersion,
            preferenceDecision: rerank.decision
        )
    }

    private func rerank(
        matches: [AssistPredictionEvidence],
        input: AssistPredictionInput
    ) -> PreferenceRerankResult {
        guard let profile = preferenceProfile, !profile.assistPreferences.isEmpty else {
            return PreferenceRerankResult(
                matches: matches.enumerated().map { index, evidence in
                    RankedAssistEvidence(
                        evidence: evidence,
                        baseScore: evidence.score,
                        finalScore: evidence.score,
                        ruleHits: [],
                        loweredReasons: [],
                        originalIndex: index
                    )
                },
                decision: nil
            )
        }

        let evaluated = matches.enumerated().map { index, evidence in
            evaluateCandidate(
                evidence: evidence,
                input: input,
                directives: profile.assistPreferences,
                originalIndex: index
            )
        }

        let sorted = evaluated.sorted(by: rankedEvidenceSort)
        guard let selected = sorted.first else {
            return PreferenceRerankResult(matches: [], decision: nil)
        }

        let selectedRuleIds = uniqueRuleIds(from: selected.ruleHits)
        let candidateExplanations = sorted.map { candidate in
            let loweredReasons = buildLoweredReasons(
                candidate: candidate,
                selected: selected,
                selectedRuleIds: selectedRuleIds
            )
            return AssistPreferenceCandidateExplanation(
                knowledgeItemId: candidate.evidence.knowledgeItemId,
                taskId: candidate.evidence.taskId,
                stepId: candidate.evidence.stepId,
                stepInstruction: candidate.evidence.stepInstruction,
                baseScore: rounded(candidate.baseScore),
                finalScore: rounded(candidate.finalScore),
                appliedRuleIds: uniqueRuleIds(from: candidate.ruleHits),
                ruleHits: candidate.ruleHits.sorted(by: ruleHitSort),
                loweredReasons: loweredReasons,
                summary: buildCandidateSummary(candidate: candidate, loweredReasons: loweredReasons)
            )
        }

        let appliedRuleIds = Array(
            Set(candidateExplanations.flatMap(\.appliedRuleIds))
        ).sorted()
        let hasMeaningfulRerank = candidateExplanations.contains { explanation in
            !explanation.appliedRuleIds.isEmpty || !explanation.loweredReasons.isEmpty
        }

        let decision: AssistPreferenceRerankDecision?
        if hasMeaningfulRerank {
            decision = AssistPreferenceRerankDecision(
                profileVersion: profile.profileVersion,
                selectedKnowledgeItemId: selected.evidence.knowledgeItemId,
                selectedStepId: selected.evidence.stepId,
                selectedBaseScore: rounded(selected.baseScore),
                selectedFinalScore: rounded(selected.finalScore),
                appliedRuleIds: appliedRuleIds,
                summary: buildDecisionSummary(
                    selected: selected,
                    candidateExplanations: candidateExplanations,
                    appliedRuleIds: appliedRuleIds
                ),
                candidateExplanations: candidateExplanations
            )
        } else {
            decision = nil
        }

        let enriched = zip(sorted, candidateExplanations).map { pair in
            RankedAssistEvidence(
                evidence: pair.0.evidence,
                baseScore: pair.0.baseScore,
                finalScore: pair.0.finalScore,
                ruleHits: pair.0.ruleHits,
                loweredReasons: pair.1.loweredReasons,
                originalIndex: pair.0.originalIndex
            )
        }

        return PreferenceRerankResult(matches: enriched, decision: decision)
    }

    private func evaluateCandidate(
        evidence: AssistPredictionEvidence,
        input: AssistPredictionInput,
        directives: [PreferenceProfileDirective],
        originalIndex: Int
    ) -> RankedAssistEvidence {
        var ruleHits: [AssistPreferenceRuleHit] = []

        for directive in directives {
            ruleHits.append(contentsOf: evaluateDirective(directive, for: evidence, input: input))
        }

        let delta = ruleHits.reduce(0) { partial, hit in
            partial + hit.delta
        }
        let finalScore = applyPreferenceDelta(baseScore: evidence.score, delta: delta)

        return RankedAssistEvidence(
            evidence: evidence,
            baseScore: evidence.score,
            finalScore: rounded(finalScore),
            ruleHits: ruleHits.filter { abs($0.delta) >= 0.01 },
            loweredReasons: [],
            originalIndex: originalIndex
        )
    }

    private func evaluateDirective(
        _ directive: PreferenceProfileDirective,
        for evidence: AssistPredictionEvidence,
        input: AssistPredictionInput
    ) -> [AssistPreferenceRuleHit] {
        let scopeScore = scopeMatchScore(for: directive.scope, evidence: evidence, input: input)
        guard scopeScore > 0 else {
            return []
        }

        var hits: [AssistPreferenceRuleHit] = []

        if directive.type == .risk {
            let riskScore = estimatedRiskScore(for: evidence)
            let cautionStrength = cautionStrength(for: directive)
            let rawMatch = max(0.1, scopeScore * cautionStrength)
            let delta = rounded((0.62 - riskScore) * riskPreferenceWeight * rawMatch)
            if abs(delta) >= 0.01 {
                let explanation: String
                if delta >= 0 {
                    explanation = "规则 \(directive.ruleId) 偏好更稳妥的动作，当前候选风险较低。"
                } else {
                    explanation = "规则 \(directive.ruleId) 要求对高风险动作更谨慎，因此压低该候选。"
                }
                hits.append(
                    AssistPreferenceRuleHit(
                        ruleId: directive.ruleId,
                        dimension: .riskPreference,
                        weight: rounded(riskPreferenceWeight),
                        matchScore: rounded(rawMatch),
                        delta: delta,
                        explanation: explanation
                    )
                )
            }
            return hits
        }

        let prefersMatch = directivePrefersMatchingCandidate(directive)
        let sign = prefersMatch ? 1.0 : -1.0

        let stepScore = stepPreferenceScore(for: directive, evidence: evidence, input: input) * scopeScore
        if stepScore >= 0.2 {
            let delta = rounded(sign * stepPreferenceWeight * min(1.0, stepScore))
            let explanation: String
            if prefersMatch {
                explanation = "规则 \(directive.ruleId) 的步骤偏好与当前候选匹配。"
            } else {
                explanation = "规则 \(directive.ruleId) 不鼓励这类步骤表达，因此压低该候选。"
            }
            hits.append(
                AssistPreferenceRuleHit(
                    ruleId: directive.ruleId,
                    dimension: .stepPreference,
                    weight: rounded(stepPreferenceWeight),
                    matchScore: rounded(stepScore),
                    delta: delta,
                    explanation: explanation
                )
            )
        }

        let appScore = appPreferenceScore(for: directive.scope, evidence: evidence, input: input)
        if appScore > 0 {
            let delta = rounded(sign * appPreferenceWeight * appScore)
            let explanation: String
            if prefersMatch {
                explanation = "规则 \(directive.ruleId) 命中了应用上下文偏好。"
            } else {
                explanation = "规则 \(directive.ruleId) 不偏好当前应用上下文，因此压低该候选。"
            }
            hits.append(
                AssistPreferenceRuleHit(
                    ruleId: directive.ruleId,
                    dimension: .appPreference,
                    weight: rounded(appPreferenceWeight),
                    matchScore: rounded(appScore),
                    delta: delta,
                    explanation: explanation
                )
            )
        }

        return hits
    }

    private func buildLoweredReasons(
        candidate: RankedAssistEvidence,
        selected: RankedAssistEvidence,
        selectedRuleIds: [String]
    ) -> [String] {
        if candidate.evidence.knowledgeItemId == selected.evidence.knowledgeItemId,
           candidate.evidence.stepId == selected.evidence.stepId {
            return []
        }

        var reasons = candidate.ruleHits
            .filter { $0.delta < 0 }
            .sorted(by: ruleHitSort)
            .map(\.explanation)

        if reasons.isEmpty,
           !selectedRuleIds.isEmpty,
           candidate.finalScore < selected.finalScore {
            reasons.append("未命中主候选命中的偏好规则 \(selectedRuleIds.joined(separator: "、"))。")
        }

        return reasons
    }

    private func buildCandidateSummary(
        candidate: RankedAssistEvidence,
        loweredReasons: [String]
    ) -> String {
        let appliedRuleIds = uniqueRuleIds(from: candidate.ruleHits)
        let scoreSegment = "基础分 \(rounded(candidate.baseScore)) -> 重排后 \(rounded(candidate.finalScore))"

        if appliedRuleIds.isEmpty {
            if loweredReasons.isEmpty {
                return "未命中 assist 偏好规则，\(scoreSegment)。"
            }
            return "未命中正向规则，\(scoreSegment)；\(loweredReasons.joined(separator: "；"))"
        }

        if loweredReasons.isEmpty {
            return "命中规则 \(appliedRuleIds.joined(separator: "、"))，\(scoreSegment)。"
        }

        return "命中规则 \(appliedRuleIds.joined(separator: "、"))，\(scoreSegment)；\(loweredReasons.joined(separator: "；"))"
    }

    private func buildDecisionSummary(
        selected: RankedAssistEvidence,
        candidateExplanations: [AssistPreferenceCandidateExplanation],
        appliedRuleIds: [String]
    ) -> String {
        let target = selected.evidence.targetDescription ?? conciseInstruction(selected.evidence.stepInstruction)
        guard !appliedRuleIds.isEmpty else {
            return "沿用基础检索，最终仍选择「\(target)」。"
        }

        if let lowered = candidateExplanations.first(where: {
            ($0.knowledgeItemId != selected.evidence.knowledgeItemId || $0.stepId != selected.evidence.stepId)
                && !$0.loweredReasons.isEmpty
        }), let firstReason = lowered.loweredReasons.first {
            return "最终选择「\(target)」，命中规则 \(appliedRuleIds.joined(separator: "、"))；同时压低了「\(conciseInstruction(lowered.stepInstruction))」：\(firstReason)"
        }

        return "最终选择「\(target)」，命中规则 \(appliedRuleIds.joined(separator: "、"))。"
    }

    private func buildReason(
        primary: RankedAssistEvidence,
        evidence: [RankedAssistEvidence],
        input: AssistPredictionInput,
        preferenceDecision: AssistPreferenceRerankDecision?
    ) -> String {
        let target = primary.evidence.targetDescription ?? conciseInstruction(primary.evidence.stepInstruction)
        let historyCount = evidence.count

        let environment: String
        if let windowTitle = input.currentWindowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !windowTitle.isEmpty {
            environment = "在“\(windowTitle)”窗口里"
        } else if let appName = input.currentAppName?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty {
            environment = "在 \(appName) 中"
        } else {
            environment = "在类似场景下"
        }

        let sequenceHint = input.recentStepInstructions.isEmpty ? "" : "完成类似前序步骤后"
        let prefix = sequenceHint.isEmpty ? "过去你\(environment)通常会" : "过去你\(environment)\(sequenceHint)通常会"

        let baseReason: String
        if historyCount > 1 {
            baseReason = "\(prefix)执行「\(target)」，参考了 \(historyCount) 条历史知识。"
        } else {
            baseReason = "\(prefix)执行「\(target)」，来源知识 \(primary.evidence.knowledgeItemId)。"
        }

        guard let preferenceDecision else {
            return baseReason
        }

        if let lowered = preferenceDecision.candidateExplanations.first(where: {
            ($0.knowledgeItemId != primary.evidence.knowledgeItemId || $0.stepId != primary.evidence.stepId)
                && !$0.loweredReasons.isEmpty
        }), let firstReason = lowered.loweredReasons.first {
            return "\(baseReason) 偏好重排命中 \(preferenceDecision.appliedRuleIds.joined(separator: "、"))，并压低了「\(conciseInstruction(lowered.stepInstruction))」：\(firstReason)"
        }

        return "\(baseReason) 偏好重排命中 \(preferenceDecision.appliedRuleIds.joined(separator: "、"))。"
    }

    private func selectEvidence(
        from matches: [RankedAssistEvidence],
        primary: RankedAssistEvidence
    ) -> [RankedAssistEvidence] {
        let primaryKey = normalized(primary.evidence.targetDescription ?? primary.evidence.stepInstruction)
        let grouped = matches.filter { candidate in
            normalized(candidate.evidence.targetDescription ?? candidate.evidence.stepInstruction) == primaryKey
        }
        let source = grouped.isEmpty ? [primary] : grouped
        return Array(source.prefix(evidenceLimit))
    }

    private func scopeMatchScore(
        for scope: PreferenceSignalScopeReference,
        evidence: AssistPredictionEvidence,
        input: AssistPredictionInput
    ) -> Double {
        switch scope.level {
        case .global:
            return 0.72
        case .app:
            return appPreferenceScore(for: scope, evidence: evidence, input: input)
        case .taskFamily:
            return taskFamilyMatchScore(scope.taskFamily, evidence: evidence, input: input)
        case .skillFamily:
            return 0
        case .windowPattern:
            return windowPreferenceScore(windowPattern: scope.windowPattern, evidence: evidence, input: input)
        }
    }

    private func appPreferenceScore(
        for scope: PreferenceSignalScopeReference,
        evidence: AssistPredictionEvidence,
        input: AssistPredictionInput
    ) -> Double {
        let scopeBundle = normalized(scope.appBundleId)
        let scopeName = normalized(scope.appName)
        let currentBundle = normalized(input.currentAppBundleId)
        let currentName = normalized(input.currentAppName)
        let evidenceBundle = normalized(evidence.appBundleId)
        let evidenceName = normalized(evidence.appName)

        if !scopeBundle.isEmpty {
            if scopeBundle == currentBundle || scopeBundle == evidenceBundle {
                return 1.0
            }
        }

        if !scopeName.isEmpty {
            if scopeName == currentName || scopeName == evidenceName {
                return 0.78
            }
        }

        return 0
    }

    private func taskFamilyMatchScore(
        _ taskFamily: String?,
        evidence: AssistPredictionEvidence,
        input: AssistPredictionInput
    ) -> Double {
        let ruleFamily = normalized(taskFamily)
        guard !ruleFamily.isEmpty else {
            return 0
        }

        let currentFamily = normalized(input.currentTaskFamily)
        if !currentFamily.isEmpty {
            if ruleFamily == currentFamily {
                return 1.0
            }
            if ruleFamily.contains(currentFamily) || currentFamily.contains(ruleFamily) {
                return 0.82
            }
        }

        let candidateText = normalized([
            input.currentTaskGoal,
            evidence.goal,
            evidence.stepInstruction,
            evidence.targetDescription
        ].compactMap { $0 }.joined(separator: " "))
        return max(
            tokenOverlapScore(ruleFamily, candidateText),
            bigramSimilarity(ruleFamily, candidateText) * 0.85
        )
    }

    private func windowPreferenceScore(
        windowPattern: String?,
        evidence: AssistPredictionEvidence,
        input: AssistPredictionInput
    ) -> Double {
        guard let windowPattern else {
            return 0
        }

        let currentWindow = input.currentWindowTitle ?? evidence.windowTitle ?? ""
        guard !currentWindow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return 0
        }

        if let regex = try? NSRegularExpression(pattern: windowPattern, options: [.caseInsensitive]) {
            let range = NSRange(currentWindow.startIndex..<currentWindow.endIndex, in: currentWindow)
            if regex.firstMatch(in: currentWindow, options: [], range: range) != nil {
                return 1.0
            }
        }

        let lhs = normalized(windowPattern)
        let rhs = normalized(currentWindow)
        if lhs.isEmpty || rhs.isEmpty {
            return 0
        }
        if lhs == rhs {
            return 0.92
        }
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return 0.8
        }
        return max(0, bigramSimilarity(lhs, rhs) - 0.2)
    }

    private func stepPreferenceScore(
        for directive: PreferenceProfileDirective,
        evidence: AssistPredictionEvidence,
        input: AssistPredictionInput
    ) -> Double {
        let ruleText = normalized([
            directive.statement,
            directive.hint,
            directive.proposedAction,
            directive.scope.taskFamily,
            directive.scope.windowPattern
        ].compactMap { $0 }.joined(separator: " "))
        guard !ruleText.isEmpty else {
            return 0
        }

        let candidateText = normalized([
            evidence.stepInstruction,
            evidence.targetDescription,
            evidence.goal,
            input.currentTaskGoal,
            input.currentTaskFamily
        ].compactMap { $0 }.joined(separator: " "))
        guard !candidateText.isEmpty else {
            return 0
        }

        var score = max(
            tokenOverlapScore(ruleText, candidateText),
            bigramSimilarity(ruleText, candidateText)
        )

        let actionType = inferActionType(from: evidence.stepInstruction)
        switch preferredActionMode(for: directive, normalizedRuleText: ruleText) {
        case .shortcut:
            if actionType == .shortcut {
                score = max(score, 0.98)
            } else {
                score *= 0.28
            }
        case .click:
            if actionType == .click {
                score = max(score, 0.88)
            } else {
                score *= 0.42
            }
        case .input:
            if actionType == .input {
                score = max(score, 0.88)
            } else {
                score *= 0.42
            }
        case .unspecified:
            break
        }

        let targetText = normalized(evidence.targetDescription)
        if !targetText.isEmpty, ruleText.contains(targetText) {
            score = max(score, 0.9)
        }

        return min(1.0, score)
    }

    private func estimatedRiskScore(for evidence: AssistPredictionEvidence) -> Double {
        let text = normalized([
            evidence.stepInstruction,
            evidence.targetDescription,
            evidence.goal
        ].compactMap { $0 }.joined(separator: " "))

        var score: Double
        switch inferActionType(from: evidence.stepInstruction) {
        case .click:
            score = 0.18
        case .input:
            score = 0.28
        case .shortcut:
            score = 0.32
        case .generic:
            score = 0.24
        }

        if containsAnyToken(text, tokens: ["search", "open", "focus", "view", "find", "navigate", "search", "搜索", "打开", "查看", "定位"]) {
            score = min(score, 0.2)
        }
        if containsAnyToken(text, tokens: ["save", "download", "run", "execute", "edit", "修改", "保存", "下载", "运行", "执行"]) {
            score = max(score, 0.42)
        }
        if containsAnyToken(text, tokens: ["merge", "submit", "send", "publish", "push", "commit", "合并", "提交", "发送", "发布"]) {
            score = max(score, 0.68)
        }
        if containsAnyToken(text, tokens: ["delete", "remove", "trash", "quit", "close", "reset", "kill", "sudo", "rm", "删除", "移除", "退出", "关闭", "重置", "终止"]) {
            score = max(score, 0.84)
        }

        return min(0.98, max(0.05, score))
    }

    private func cautionStrength(for directive: PreferenceProfileDirective) -> Double {
        let text = normalized([
            directive.statement,
            directive.hint,
            directive.proposedAction
        ].compactMap { $0 }.joined(separator: " "))
        if containsAnyToken(text, tokens: ["confirmation", "confirm", "danger", "blocked", "cautious", "require", "风险", "确认", "高风险", "谨慎", "阻止"]) {
            return 1.0
        }
        return 0.72
    }

    private func preferredActionMode(
        for directive: PreferenceProfileDirective,
        normalizedRuleText: String
    ) -> PreferredActionMode {
        let action = normalized(directive.proposedAction)
        if containsAnyToken(action, tokens: ["shortcut", "keyboard", "hotkey", "command", "cmd"]) {
            return .shortcut
        }
        if containsAnyToken(action, tokens: ["click", "button", "toolbar"]) {
            return .click
        }
        if containsAnyToken(action, tokens: ["input", "type", "text"]) {
            return .input
        }

        let mentionsShortcut = containsAnyToken(
            normalizedRuleText,
            tokens: ["shortcut", "shortcuts", "keyboard", "cmd", "command", "hotkey", "快捷键"]
        )
        let mentionsClick = containsAnyToken(
            normalizedRuleText,
            tokens: ["click", "button", "toolbar", "点击", "按钮", "工具栏"]
        )
        let mentionsInput = containsAnyToken(
            normalizedRuleText,
            tokens: ["input", "type", "text", "输入", "填写"]
        )

        if mentionsShortcut && !mentionsClick && !mentionsInput {
            return .shortcut
        }
        if mentionsClick && !mentionsShortcut && !mentionsInput {
            return .click
        }
        if mentionsInput && !mentionsShortcut && !mentionsClick {
            return .input
        }
        return .unspecified
    }

    private func directivePrefersMatchingCandidate(_ directive: PreferenceProfileDirective) -> Bool {
        let text = normalized([
            directive.statement,
            directive.hint,
            directive.proposedAction
        ].compactMap { $0 }.joined(separator: " "))

        if containsAnyToken(text, tokens: ["avoid", "never", "disable", "discourage", "forbid", "don't", "不要", "避免", "禁止", "不要用"]) {
            return false
        }
        return true
    }

    private func uniqueRuleIds(from hits: [AssistPreferenceRuleHit]) -> [String] {
        Array(Set(hits.map(\.ruleId))).sorted()
    }

    private func ruleHitSort(lhs: AssistPreferenceRuleHit, rhs: AssistPreferenceRuleHit) -> Bool {
        let lhsMagnitude = abs(lhs.delta)
        let rhsMagnitude = abs(rhs.delta)
        if lhsMagnitude == rhsMagnitude {
            if lhs.dimension == rhs.dimension {
                return lhs.ruleId < rhs.ruleId
            }
            return lhs.dimension.rawValue < rhs.dimension.rawValue
        }
        return lhsMagnitude > rhsMagnitude
    }

    private func rankedEvidenceSort(lhs: RankedAssistEvidence, rhs: RankedAssistEvidence) -> Bool {
        if lhs.finalScore == rhs.finalScore {
            if lhs.baseScore == rhs.baseScore {
                if lhs.evidence.knowledgeItemId == rhs.evidence.knowledgeItemId {
                    return lhs.originalIndex < rhs.originalIndex
                }
                return lhs.evidence.knowledgeItemId < rhs.evidence.knowledgeItemId
            }
            return lhs.baseScore > rhs.baseScore
        }
        return lhs.finalScore > rhs.finalScore
    }

    private func inferActionType(from instruction: String) -> AssistActionType {
        let normalizedInstruction = normalized(instruction)
        if containsAnyToken(normalizedInstruction, tokens: ["shortcut", "command", "cmd", "快捷键"]) {
            return .shortcut
        }
        if containsAnyToken(normalizedInstruction, tokens: ["input", "type", "输入", "填写"]) {
            return .input
        }
        if containsAnyToken(normalizedInstruction, tokens: ["click", "点击", "tap"]) {
            return .click
        }
        return .generic
    }

    private func conciseInstruction(_ instruction: String) -> String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 48 else {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: 48)
        return "\(trimmed[..<index])..."
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

    private func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))

        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else {
            return 0
        }

        let overlap = lhsTokens.intersection(rhsTokens)
        return Double(overlap.count) / Double(min(lhsTokens.count, rhsTokens.count))
    }

    private func bigramSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsBigrams = bigrams(for: lhs)
        let rhsBigrams = bigrams(for: rhs)

        guard !lhsBigrams.isEmpty, !rhsBigrams.isEmpty else {
            return lhs == rhs && !lhs.isEmpty ? 1.0 : 0
        }

        let lhsSet = Set(lhsBigrams)
        let rhsSet = Set(rhsBigrams)
        let intersectionCount = lhsSet.intersection(rhsSet).count
        let unionCount = lhsSet.union(rhsSet).count
        guard unionCount > 0 else {
            return 0
        }
        return Double(intersectionCount) / Double(unionCount)
    }

    private func bigrams(for value: String) -> [String] {
        let characters = Array(value)
        guard characters.count > 1 else {
            return value.isEmpty ? [] : [value]
        }

        return (0..<(characters.count - 1)).map { index in
            String(characters[index...index + 1])
        }
    }

    private func containsAnyToken(
        _ value: String,
        tokens: [String]
    ) -> Bool {
        tokens.contains { token in
            value.localizedCaseInsensitiveContains(token)
        }
    }

    private func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }

    private func applyPreferenceDelta(
        baseScore: Double,
        delta: Double
    ) -> Double {
        if delta >= 0 {
            return min(0.995, baseScore + (delta * (1 - baseScore)))
        }
        return max(0, baseScore + (delta * max(0.2, baseScore)))
    }
}

private struct RankedAssistEvidence {
    let evidence: AssistPredictionEvidence
    let baseScore: Double
    let finalScore: Double
    let ruleHits: [AssistPreferenceRuleHit]
    let loweredReasons: [String]
    let originalIndex: Int
}

private struct PreferenceRerankResult {
    let matches: [RankedAssistEvidence]
    let decision: AssistPreferenceRerankDecision?
}

private enum PreferredActionMode {
    case shortcut
    case click
    case input
    case unspecified
}
