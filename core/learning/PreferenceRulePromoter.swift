import Foundation

public enum PreferenceRulePromotionReasonCode: String, Codable, CaseIterable, Sendable {
    case insufficientSignals
    case insufficientSessions
    case insufficientAverageConfidence
    case requiresTeacherConfirmation
    case recentRejectedSignal
    case automaticPromotionDisabled
    case scopeNotEnabledByDefault
    case scopeNotAllowedByGovernance
}

public struct PreferenceRulePromotionEvaluation: Codable, Equatable, Sendable {
    public let riskLevel: InteractionTurnRiskLevel
    public let threshold: PreferencePromotionThreshold
    public let qualifyingSignalIds: [String]
    public let rejectedSignalIds: [String]
    public let distinctSessionCount: Int
    public let averageConfidence: Double
    public let teacherConfirmed: Bool
    public let latestAcceptedAt: String?
    public let latestRejectedAt: String?
    public let scopeLevel: PreferenceSignalScope?
    public let governanceDecision: PreferenceRuleGovernanceDecision
    public let reasonCodes: [PreferenceRulePromotionReasonCode]

    public init(
        riskLevel: InteractionTurnRiskLevel,
        threshold: PreferencePromotionThreshold,
        qualifyingSignalIds: [String],
        rejectedSignalIds: [String],
        distinctSessionCount: Int,
        averageConfidence: Double,
        teacherConfirmed: Bool,
        latestAcceptedAt: String?,
        latestRejectedAt: String?,
        scopeLevel: PreferenceSignalScope?,
        governanceDecision: PreferenceRuleGovernanceDecision,
        reasonCodes: [PreferenceRulePromotionReasonCode]
    ) {
        self.riskLevel = riskLevel
        self.threshold = threshold
        self.qualifyingSignalIds = qualifyingSignalIds.sorted()
        self.rejectedSignalIds = rejectedSignalIds.sorted()
        self.distinctSessionCount = distinctSessionCount
        self.averageConfidence = averageConfidence
        self.teacherConfirmed = teacherConfirmed
        self.latestAcceptedAt = latestAcceptedAt
        self.latestRejectedAt = latestRejectedAt
        self.scopeLevel = scopeLevel
        self.governanceDecision = governanceDecision
        self.reasonCodes = reasonCodes
    }

    public var isEligible: Bool {
        reasonCodes.isEmpty
    }
}

public struct PreferenceRulePromotionDraft: Equatable, Sendable {
    public let ruleId: String
    public let statement: String
    public let signals: [PreferenceSignal]
    public let riskLevel: InteractionTurnRiskLevel
    public let teacherConfirmed: Bool
    public let createdAt: String?
    public let updatedAt: String?

    public init(
        ruleId: String,
        statement: String,
        signals: [PreferenceSignal],
        riskLevel: InteractionTurnRiskLevel,
        teacherConfirmed: Bool,
        createdAt: String? = nil,
        updatedAt: String? = nil
    ) {
        self.ruleId = ruleId
        self.statement = statement
        self.signals = signals
        self.riskLevel = riskLevel
        self.teacherConfirmed = teacherConfirmed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PreferenceRulePromotionOutcome: String, Codable, CaseIterable, Sendable {
    case candidate
    case promoted
}

public struct PreferenceRulePromotionResult: Equatable, Sendable {
    public let outcome: PreferenceRulePromotionOutcome
    public let evaluation: PreferenceRulePromotionEvaluation
    public let rule: PreferenceRule?

    public init(
        outcome: PreferenceRulePromotionOutcome,
        evaluation: PreferenceRulePromotionEvaluation,
        rule: PreferenceRule?
    ) {
        self.outcome = outcome
        self.evaluation = evaluation
        self.rule = rule
    }
}

public enum PreferenceRulePromoterError: Error, Equatable {
    case emptyStatement(ruleId: String)
    case incompatibleSignalGroup(ruleId: String, reason: String)
}

public struct PreferenceRulePromoter {
    public let policy: PreferencePromotionPolicy
    public let configuration: PreferencePromotionConfiguration

    public init(policy: PreferencePromotionPolicy = .loadDefaultOrFallback()) {
        self.policy = policy
        self.configuration = policy.promotionConfiguration
    }

    public init(configuration: PreferencePromotionConfiguration) {
        self.policy = PreferencePromotionPolicy.v0Default.replacingPromotionConfiguration(configuration)
        self.configuration = configuration
    }

    public func evaluate(
        signals: [PreferenceSignal],
        riskLevel: InteractionTurnRiskLevel,
        teacherConfirmed: Bool
    ) -> PreferenceRulePromotionEvaluation {
        let orderedSignals = signals.sorted {
            ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
        }
        let mergedEntries = PreferenceSignalMerger.merge(orderedSignals).entries
        let qualifyingEntries = qualifyingEntries(from: mergedEntries)
        let rejectedEntries = mergedEntries.filter { $0.signal.promotionStatus == .rejected }
        let threshold = configuration.threshold(for: riskLevel)
        let distinctSessionCount = Set(qualifyingEntries.map(\.signal.sessionId)).count
        let averageConfidence: Double
        if qualifyingEntries.isEmpty {
            averageConfidence = 0
        } else {
            averageConfidence = qualifyingEntries.map(\.mergedConfidence).reduce(0, +) / Double(qualifyingEntries.count)
        }

        let latestAcceptedAt = qualifyingEntries.last?.signal.timestamp
        let latestRejectedAt = rejectedEntries.last?.signal.timestamp
        let representativeSignal = qualifyingEntries.last?.signal ?? mergedEntries.last?.signal
        let representativeScope = representativeSignal?.scope
        let representativeScopeLevel = representativeScope?.level
        let representativeType = representativeSignal?.type ?? mergedEntries.last?.signal.type ?? .procedure
        let governanceDecision = policy.governanceDecision(
            signalType: representativeType,
            riskLevel: riskLevel,
            scope: representativeScope
        )

        var reasonCodes: [PreferenceRulePromotionReasonCode] = []

        if !threshold.allowAutomaticPromotion {
            reasonCodes.append(.automaticPromotionDisabled)
        }

        if representativeScopeLevel != nil,
           let representativeScope,
           !configuration.isScopeEnabled(representativeScope) {
            reasonCodes.append(.scopeNotEnabledByDefault)
        }

        if !governanceDecision.scopeAllowed {
            reasonCodes.append(.scopeNotAllowedByGovernance)
        }

        if qualifyingEntries.count < threshold.minimumSignalCount {
            reasonCodes.append(.insufficientSignals)
        }

        if distinctSessionCount < threshold.minimumSessionCount {
            reasonCodes.append(.insufficientSessions)
        }

        if let minimumAverageConfidence = threshold.minimumAverageConfidence,
           averageConfidence < minimumAverageConfidence {
            reasonCodes.append(.insufficientAverageConfidence)
        }

        if threshold.requiresTeacherConfirmation, !teacherConfirmed {
            reasonCodes.append(.requiresTeacherConfirmation)
        }

        if threshold.requiresNoRecentRejection,
           hasRecentRejection(
            latestAcceptedAt: latestAcceptedAt,
            latestRejectedAt: latestRejectedAt
           ) {
            reasonCodes.append(.recentRejectedSignal)
        }

        return PreferenceRulePromotionEvaluation(
            riskLevel: riskLevel,
            threshold: threshold,
            qualifyingSignalIds: qualifyingEntries.flatMap(\.sourceSignalIds),
            rejectedSignalIds: rejectedEntries.flatMap(\.sourceSignalIds),
            distinctSessionCount: distinctSessionCount,
            averageConfidence: averageConfidence,
            teacherConfirmed: teacherConfirmed,
            latestAcceptedAt: latestAcceptedAt,
            latestRejectedAt: latestRejectedAt,
            scopeLevel: representativeScopeLevel,
            governanceDecision: governanceDecision,
            reasonCodes: reasonCodes
        )
    }

    public func evaluate(
        _ draft: PreferenceRulePromotionDraft
    ) -> PreferenceRulePromotionEvaluation {
        evaluate(
            signals: draft.signals,
            riskLevel: draft.riskLevel,
            teacherConfirmed: draft.teacherConfirmed
        )
    }

    public func promote(
        _ draft: PreferenceRulePromotionDraft
    ) throws -> PreferenceRulePromotionResult {
        guard let statement = normalizedOptionalString(draft.statement) else {
            throw PreferenceRulePromoterError.emptyStatement(ruleId: draft.ruleId)
        }

        let orderedSignals = draft.signals.sorted {
            ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
        }
        let mergedEntries = PreferenceSignalMerger.merge(orderedSignals).entries
        let qualifyingEntries = qualifyingEntries(from: mergedEntries)
        let qualifyingSignals = qualifyingSignals(from: orderedSignals)

        if let compatibilityFailure = compatibilityFailureReason(for: qualifyingEntries) {
            throw PreferenceRulePromoterError.incompatibleSignalGroup(
                ruleId: draft.ruleId,
                reason: compatibilityFailure
            )
        }

        let evaluation = evaluate(
            signals: orderedSignals,
            riskLevel: draft.riskLevel,
            teacherConfirmed: draft.teacherConfirmed
        )

        guard evaluation.isEligible,
              let representative = qualifyingEntries.last?.signal ?? qualifyingEntries.first?.signal else {
            return PreferenceRulePromotionResult(
                outcome: .candidate,
                evaluation: evaluation,
                rule: nil
            )
        }

        let createdAt = draft.createdAt ?? qualifyingEntries.first?.signal.timestamp ?? representative.timestamp
        let updatedAt = draft.updatedAt ?? qualifyingEntries.last?.signal.timestamp ?? representative.timestamp
        let hint = qualifyingEntries.reversed().compactMap { normalizedOptionalString($0.signal.hint) }.first
        let proposedAction = qualifyingEntries.reversed().compactMap { normalizedOptionalString($0.signal.proposedAction) }.first
        let governance = evaluation.governanceDecision.governance.materialized(at: updatedAt)
        let sourceSignalIds = Array(Set(qualifyingEntries.flatMap(\.sourceSignalIds))).sorted()
        let evidenceSignals = uniqueSignalsByID(qualifyingSignals)

        let rule = PreferenceRule(
            ruleId: draft.ruleId,
            sourceSignalIds: sourceSignalIds,
            scope: representative.scope,
            type: representative.type,
            polarity: representative.polarity,
            statement: statement,
            hint: hint,
            proposedAction: proposedAction,
            evidence: evidenceSignals.map(PreferenceRuleEvidence.init(signal:)),
            riskLevel: draft.riskLevel,
            governance: governance,
            activationStatus: .active,
            teacherConfirmed: draft.teacherConfirmed,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        return PreferenceRulePromotionResult(
            outcome: .promoted,
            evaluation: evaluation,
            rule: rule
        )
    }

    private func qualifyingSignals(from signals: [PreferenceSignal]) -> [PreferenceSignal] {
        signals.filter { signal in
            switch signal.promotionStatus {
            case .candidate, .confirmed:
                return true
            case .rejected, .superseded:
                return false
            }
        }
    }

    private func qualifyingEntries(from entries: [PreferenceSignalMergeEntry]) -> [PreferenceSignalMergeEntry] {
        entries.filter { entry in
            switch entry.signal.promotionStatus {
            case .candidate, .confirmed:
                return true
            case .rejected, .superseded:
                return false
            }
        }
    }

    private func hasRecentRejection(
        latestAcceptedAt: String?,
        latestRejectedAt: String?
    ) -> Bool {
        guard let latestRejectedAt else {
            return false
        }
        guard let latestAcceptedAt else {
            return true
        }
        return latestRejectedAt >= latestAcceptedAt
    }

    private func compatibilityFailureReason(for entries: [PreferenceSignalMergeEntry]) -> String? {
        guard let first = entries.first?.signal else {
            return nil
        }

        let signals = entries.map(\.signal)
        if signals.contains(where: { $0.scope != first.scope }) {
            return "signals span multiple scopes"
        }
        if signals.contains(where: { $0.type != first.type }) {
            return "signals span multiple signal types"
        }
        if signals.contains(where: { $0.polarity != first.polarity }) {
            return "signals span multiple polarities"
        }

        let proposedActions = Set(signals.compactMap { normalizedOptionalString($0.proposedAction) })
        if proposedActions.count > 1 {
            return "signals propose multiple actions"
        }

        if entries.contains(where: { $0.conflictTags.contains(.opposingPolarity) }) {
            return "signals contain opposing polarity"
        }
        if entries.contains(where: { $0.conflictTags.contains(.divergentProposedAction) }) {
            return "signals contain conflicting merged actions"
        }

        return nil
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func uniqueSignalsByID(_ signals: [PreferenceSignal]) -> [PreferenceSignal] {
        var signalsByID: [String: PreferenceSignal] = [:]
        for signal in signals {
            signalsByID[signal.signalId] = signal
        }
        return signalsByID.values.sorted {
            ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
        }
    }
}
