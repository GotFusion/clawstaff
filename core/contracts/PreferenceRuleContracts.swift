import Foundation

public enum PreferenceRuleActivationStatus: String, Codable, CaseIterable, Sendable {
    case active
    case superseded
    case revoked
}

public struct PreferenceRuleEvidence: Codable, Equatable, Sendable {
    public let signalId: String
    public let turnId: String
    public let traceId: String?
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let evidenceIds: [String]
    public let confidence: Double
    public let timestamp: String

    public init(
        signalId: String,
        turnId: String,
        traceId: String? = nil,
        sessionId: String,
        taskId: String,
        stepId: String,
        evidenceIds: [String],
        confidence: Double,
        timestamp: String
    ) {
        self.signalId = signalId
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
        self.evidenceIds = evidenceIds
        self.confidence = confidence
        self.timestamp = timestamp
    }

    public init(signal: PreferenceSignal) {
        self.init(
            signalId: signal.signalId,
            turnId: signal.turnId,
            traceId: signal.traceId,
            sessionId: signal.sessionId,
            taskId: signal.taskId,
            stepId: signal.stepId,
            evidenceIds: signal.evidenceIds,
            confidence: signal.confidence,
            timestamp: signal.timestamp
        )
    }
}

public struct PreferenceRule: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let ruleId: String
    public let sourceSignalIds: [String]
    public let scope: PreferenceSignalScopeReference
    public let type: PreferenceSignalType
    public let polarity: PreferenceSignalPolarity
    public let statement: String
    public let hint: String?
    public let proposedAction: String?
    public let evidence: [PreferenceRuleEvidence]
    public let riskLevel: InteractionTurnRiskLevel
    public let activationStatus: PreferenceRuleActivationStatus
    public let teacherConfirmed: Bool
    public let supersededByRuleId: String?
    public let lifecycleReason: String?
    public let createdAt: String
    public let updatedAt: String

    public init(
        schemaVersion: String = "openstaff.learning.preference-rule.v0",
        ruleId: String,
        sourceSignalIds: [String],
        scope: PreferenceSignalScopeReference,
        type: PreferenceSignalType,
        polarity: PreferenceSignalPolarity,
        statement: String,
        hint: String? = nil,
        proposedAction: String? = nil,
        evidence: [PreferenceRuleEvidence],
        riskLevel: InteractionTurnRiskLevel,
        activationStatus: PreferenceRuleActivationStatus,
        teacherConfirmed: Bool,
        supersededByRuleId: String? = nil,
        lifecycleReason: String? = nil,
        createdAt: String,
        updatedAt: String
    ) {
        let evidenceSignalIds = evidence.map(\.signalId)
        self.schemaVersion = schemaVersion
        self.ruleId = ruleId
        self.sourceSignalIds = Array(Set(sourceSignalIds + evidenceSignalIds)).sorted()
        self.scope = scope
        self.type = type
        self.polarity = polarity
        self.statement = statement
        self.hint = hint
        self.proposedAction = proposedAction
        self.evidence = evidence.sorted {
            ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
        }
        self.riskLevel = riskLevel
        self.activationStatus = activationStatus
        self.teacherConfirmed = teacherConfirmed
        self.supersededByRuleId = supersededByRuleId
        self.lifecycleReason = lifecycleReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isActive: Bool {
        activationStatus == .active
    }

    public func updatingActivationStatus(
        _ activationStatus: PreferenceRuleActivationStatus,
        updatedAt: String,
        supersededByRuleId: String? = nil,
        lifecycleReason: String? = nil
    ) -> Self {
        Self(
            schemaVersion: schemaVersion,
            ruleId: ruleId,
            sourceSignalIds: sourceSignalIds,
            scope: scope,
            type: type,
            polarity: polarity,
            statement: statement,
            hint: hint,
            proposedAction: proposedAction,
            evidence: evidence,
            riskLevel: riskLevel,
            activationStatus: activationStatus,
            teacherConfirmed: teacherConfirmed,
            supersededByRuleId: supersededByRuleId,
            lifecycleReason: lifecycleReason,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
