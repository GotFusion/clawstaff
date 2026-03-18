import Foundation

public enum NextStateEvidenceSource: String, Codable, CaseIterable, Sendable {
    case teacherReview
    case executionRuntime
    case replayVerify
    case driftDetection
    case chatgptSuggestion
    case benchmarkResult
}

public enum NextStateEvidenceSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
    case critical
}

public enum NextStateEvidenceRole: String, Codable, Sendable {
    case evaluative
    case directive
    case mixed
}

public enum NextStateEvidencePolarity: String, Codable, Sendable {
    case positive
    case negative
    case neutral
}

public enum NextStateEvidenceGUIFailureBucket: String, Codable, Sendable {
    case locatorResolutionFailed = "locator_resolution_failed"
    case actionKindMismatch = "action_kind_mismatch"
    case riskBlocked = "risk_blocked"
}

public struct NextStateEvidenceTurnContext: Codable, Equatable, Sendable {
    public let turnId: String
    public let traceId: String?
    public let sessionId: String
    public let taskId: String
    public let stepId: String

    public init(
        turnId: String,
        traceId: String? = nil,
        sessionId: String,
        taskId: String,
        stepId: String
    ) {
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
    }

    public init(turn: InteractionTurn) {
        self.init(
            turnId: turn.turnId,
            traceId: turn.traceId,
            sessionId: turn.sessionId,
            taskId: turn.taskId,
            stepId: turn.stepId
        )
    }
}

public struct NextStateEvidenceRawReference: Codable, Equatable, Sendable {
    public let artifactKind: String
    public let path: String
    public let lineNumber: Int?
    public let identifier: String?
    public let note: String?

    public init(
        artifactKind: String,
        path: String,
        lineNumber: Int? = nil,
        identifier: String? = nil,
        note: String? = nil
    ) {
        self.artifactKind = artifactKind
        self.path = path
        self.lineNumber = lineNumber
        self.identifier = identifier
        self.note = note
    }
}

public struct NextStateEvaluativeCandidate: Codable, Equatable, Sendable {
    public let decision: String
    public let polarity: NextStateEvidencePolarity
    public let rationale: String?

    public init(
        decision: String,
        polarity: NextStateEvidencePolarity,
        rationale: String? = nil
    ) {
        self.decision = decision
        self.polarity = polarity
        self.rationale = rationale
    }
}

public struct NextStateDirectiveCandidate: Codable, Equatable, Sendable {
    public let action: String
    public let hint: String
    public let repairActionType: String?

    public init(
        action: String,
        hint: String,
        repairActionType: String? = nil
    ) {
        self.action = action
        self.hint = hint
        self.repairActionType = repairActionType
    }
}

public struct NextStateEvidence: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let evidenceId: String
    public let turnId: String
    public let traceId: String?
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let source: NextStateEvidenceSource
    public let summary: String
    public let rawRefs: [NextStateEvidenceRawReference]
    public let timestamp: String
    public let confidence: Double
    public let severity: NextStateEvidenceSeverity
    public let role: NextStateEvidenceRole
    public let guiFailureBucket: NextStateEvidenceGUIFailureBucket?
    public let evaluativeCandidate: NextStateEvaluativeCandidate?
    public let directiveCandidate: NextStateDirectiveCandidate?

    public init(
        schemaVersion: String = "openstaff.learning.next-state-evidence.v0",
        evidenceId: String,
        turnId: String,
        traceId: String? = nil,
        sessionId: String,
        taskId: String,
        stepId: String,
        source: NextStateEvidenceSource,
        summary: String,
        rawRefs: [NextStateEvidenceRawReference],
        timestamp: String,
        confidence: Double,
        severity: NextStateEvidenceSeverity,
        role: NextStateEvidenceRole,
        guiFailureBucket: NextStateEvidenceGUIFailureBucket? = nil,
        evaluativeCandidate: NextStateEvaluativeCandidate? = nil,
        directiveCandidate: NextStateDirectiveCandidate? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.evidenceId = evidenceId
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
        self.source = source
        self.summary = summary
        self.rawRefs = rawRefs
        self.timestamp = timestamp
        self.confidence = confidence
        self.severity = severity
        self.role = role
        self.guiFailureBucket = guiFailureBucket
        self.evaluativeCandidate = evaluativeCandidate
        self.directiveCandidate = directiveCandidate
    }
}
