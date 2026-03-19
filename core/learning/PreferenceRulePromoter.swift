import Foundation

public struct PreferencePromotionThreshold: Codable, Equatable, Sendable {
    public let minimumSignalCount: Int
    public let minimumSessionCount: Int
    public let minimumAverageConfidence: Double?
    public let requiresTeacherConfirmation: Bool
    public let requiresNoRecentRejection: Bool
    public let allowAutomaticPromotion: Bool

    public init(
        minimumSignalCount: Int,
        minimumSessionCount: Int,
        minimumAverageConfidence: Double? = nil,
        requiresTeacherConfirmation: Bool = false,
        requiresNoRecentRejection: Bool = false,
        allowAutomaticPromotion: Bool = true
    ) {
        self.minimumSignalCount = minimumSignalCount
        self.minimumSessionCount = minimumSessionCount
        self.minimumAverageConfidence = minimumAverageConfidence
        self.requiresTeacherConfirmation = requiresTeacherConfirmation
        self.requiresNoRecentRejection = requiresNoRecentRejection
        self.allowAutomaticPromotion = allowAutomaticPromotion
    }
}

public struct PreferencePromotionConfiguration: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let enabledScopeLevels: [PreferenceSignalScope]
    public let lowRisk: PreferencePromotionThreshold
    public let mediumRisk: PreferencePromotionThreshold
    public let highRisk: PreferencePromotionThreshold
    public let criticalRisk: PreferencePromotionThreshold

    public init(
        schemaVersion: String = "openstaff.learning.preference-promotion.v0",
        enabledScopeLevels: [PreferenceSignalScope],
        lowRisk: PreferencePromotionThreshold,
        mediumRisk: PreferencePromotionThreshold,
        highRisk: PreferencePromotionThreshold,
        criticalRisk: PreferencePromotionThreshold
    ) {
        self.schemaVersion = schemaVersion
        self.enabledScopeLevels = Array(Set(enabledScopeLevels)).sorted { $0.rawValue < $1.rawValue }
        self.lowRisk = lowRisk
        self.mediumRisk = mediumRisk
        self.highRisk = highRisk
        self.criticalRisk = criticalRisk
    }

    public static let v0Default = Self(
        enabledScopeLevels: [.global, .app, .taskFamily],
        lowRisk: PreferencePromotionThreshold(
            minimumSignalCount: 3,
            minimumSessionCount: 2,
            minimumAverageConfidence: 0.75
        ),
        mediumRisk: PreferencePromotionThreshold(
            minimumSignalCount: 4,
            minimumSessionCount: 3,
            requiresNoRecentRejection: true
        ),
        highRisk: PreferencePromotionThreshold(
            minimumSignalCount: 1,
            minimumSessionCount: 1,
            requiresTeacherConfirmation: true,
            requiresNoRecentRejection: true
        ),
        criticalRisk: PreferencePromotionThreshold(
            minimumSignalCount: 1,
            minimumSessionCount: 1,
            requiresTeacherConfirmation: true,
            requiresNoRecentRejection: true,
            allowAutomaticPromotion: false
        )
    )

    public func threshold(for riskLevel: InteractionTurnRiskLevel) -> PreferencePromotionThreshold {
        switch riskLevel {
        case .low:
            return lowRisk
        case .medium:
            return mediumRisk
        case .high:
            return highRisk
        case .critical:
            return criticalRisk
        }
    }

    public func isScopeEnabled(_ scope: PreferenceSignalScopeReference) -> Bool {
        enabledScopeLevels.contains(scope.level)
    }
}

public enum PreferenceRulePromotionReasonCode: String, Codable, CaseIterable, Sendable {
    case insufficientSignals
    case insufficientSessions
    case insufficientAverageConfidence
    case requiresTeacherConfirmation
    case recentRejectedSignal
    case automaticPromotionDisabled
    case scopeNotEnabledByDefault
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
    public let configuration: PreferencePromotionConfiguration

    public init(configuration: PreferencePromotionConfiguration = .v0Default) {
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
        let qualifyingSignals = qualifyingSignals(from: orderedSignals)
        let rejectedSignals = orderedSignals.filter { $0.promotionStatus == .rejected }
        let threshold = configuration.threshold(for: riskLevel)
        let distinctSessionCount = Set(qualifyingSignals.map(\.sessionId)).count
        let averageConfidence: Double
        if qualifyingSignals.isEmpty {
            averageConfidence = 0
        } else {
            averageConfidence = qualifyingSignals.map(\.confidence).reduce(0, +) / Double(qualifyingSignals.count)
        }

        let latestAcceptedAt = qualifyingSignals.last?.timestamp
        let latestRejectedAt = rejectedSignals.last?.timestamp
        let representativeScopeLevel = qualifyingSignals.last?.scope.level ?? orderedSignals.last?.scope.level

        var reasonCodes: [PreferenceRulePromotionReasonCode] = []

        if !threshold.allowAutomaticPromotion {
            reasonCodes.append(.automaticPromotionDisabled)
        }

        if representativeScopeLevel != nil,
           let representativeScope = qualifyingSignals.last?.scope ?? orderedSignals.last?.scope,
           !configuration.isScopeEnabled(representativeScope) {
            reasonCodes.append(.scopeNotEnabledByDefault)
        }

        if qualifyingSignals.count < threshold.minimumSignalCount {
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
            qualifyingSignalIds: qualifyingSignals.map(\.signalId),
            rejectedSignalIds: rejectedSignals.map(\.signalId),
            distinctSessionCount: distinctSessionCount,
            averageConfidence: averageConfidence,
            teacherConfirmed: teacherConfirmed,
            latestAcceptedAt: latestAcceptedAt,
            latestRejectedAt: latestRejectedAt,
            scopeLevel: representativeScopeLevel,
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
        let qualifyingSignals = qualifyingSignals(from: orderedSignals)

        if let compatibilityFailure = compatibilityFailureReason(for: qualifyingSignals) {
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
              let representative = qualifyingSignals.last ?? qualifyingSignals.first else {
            return PreferenceRulePromotionResult(
                outcome: .candidate,
                evaluation: evaluation,
                rule: nil
            )
        }

        let createdAt = draft.createdAt ?? qualifyingSignals.first?.timestamp ?? representative.timestamp
        let updatedAt = draft.updatedAt ?? qualifyingSignals.last?.timestamp ?? representative.timestamp
        let hint = qualifyingSignals.reversed().compactMap { normalizedOptionalString($0.hint) }.first
        let proposedAction = qualifyingSignals.reversed().compactMap { normalizedOptionalString($0.proposedAction) }.first

        let rule = PreferenceRule(
            ruleId: draft.ruleId,
            sourceSignalIds: qualifyingSignals.map(\.signalId),
            scope: representative.scope,
            type: representative.type,
            polarity: representative.polarity,
            statement: statement,
            hint: hint,
            proposedAction: proposedAction,
            evidence: qualifyingSignals.map(PreferenceRuleEvidence.init(signal:)),
            riskLevel: draft.riskLevel,
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

    private func compatibilityFailureReason(for signals: [PreferenceSignal]) -> String? {
        guard let first = signals.first else {
            return nil
        }

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

        return nil
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
