import Foundation

public struct InteractionTurnBuildInput: Equatable {
    public let turnId: String?
    public let traceId: String?
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let mode: OpenStaffMode
    public let turnKind: InteractionTurnKind
    public let stepIndex: Int
    public let intentSummary: String
    public let actionSummary: String
    public let actionKind: InteractionTurnActionKind
    public let appContext: InteractionTurnAppContext
    public let observationRef: InteractionTurnObservationReference
    public let semanticTargetSetRef: InteractionTurnSemanticTargetSetReference?
    public let stepReference: InteractionTurnStepReference
    public let execution: InteractionTurnExecutionLink?
    public let review: InteractionTurnReviewLink?
    public let sourceRefs: [InteractionTurnSourceReference]
    public let privacyTags: [String]
    public let learningState: InteractionTurnLearningState?
    public let riskLevel: InteractionTurnRiskLevel?
    public let status: InteractionTurnStatus?
    public let startedAt: String
    public let endedAt: String

    public init(
        turnId: String? = nil,
        traceId: String? = nil,
        sessionId: String,
        taskId: String,
        stepId: String,
        mode: OpenStaffMode,
        turnKind: InteractionTurnKind,
        stepIndex: Int,
        intentSummary: String,
        actionSummary: String,
        actionKind: InteractionTurnActionKind,
        appContext: InteractionTurnAppContext,
        observationRef: InteractionTurnObservationReference,
        semanticTargetSetRef: InteractionTurnSemanticTargetSetReference? = nil,
        stepReference: InteractionTurnStepReference,
        execution: InteractionTurnExecutionLink? = nil,
        review: InteractionTurnReviewLink? = nil,
        sourceRefs: [InteractionTurnSourceReference],
        privacyTags: [String] = [],
        learningState: InteractionTurnLearningState? = nil,
        riskLevel: InteractionTurnRiskLevel? = nil,
        status: InteractionTurnStatus? = nil,
        startedAt: String,
        endedAt: String
    ) {
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
        self.mode = mode
        self.turnKind = turnKind
        self.stepIndex = stepIndex
        self.intentSummary = intentSummary
        self.actionSummary = actionSummary
        self.actionKind = actionKind
        self.appContext = appContext
        self.observationRef = observationRef
        self.semanticTargetSetRef = semanticTargetSetRef
        self.stepReference = stepReference
        self.execution = execution
        self.review = review
        self.sourceRefs = sourceRefs
        self.privacyTags = privacyTags
        self.learningState = learningState
        self.riskLevel = riskLevel
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum InteractionTurnBuilder {
    public static func build(_ input: InteractionTurnBuildInput) -> InteractionTurn {
        let traceId = input.traceId ?? derivedTraceId(for: input)
        let turnId = input.turnId ?? derivedTurnId(for: input)
        let status = input.status ?? deriveStatus(for: input)
        let learningState = input.learningState ?? deriveLearningState(for: input)
        let riskLevel = input.riskLevel ?? deriveRiskLevel(for: input)

        return InteractionTurn(
            turnId: turnId,
            traceId: traceId,
            sessionId: input.sessionId,
            taskId: input.taskId,
            stepId: input.stepId,
            mode: input.mode,
            turnKind: input.turnKind,
            stepIndex: input.stepIndex,
            intentSummary: input.intentSummary,
            actionSummary: input.actionSummary,
            actionKind: input.actionKind,
            status: status,
            learningState: learningState,
            privacyTags: input.privacyTags,
            riskLevel: riskLevel,
            appContext: input.appContext,
            observationRef: input.observationRef,
            semanticTargetSetRef: input.semanticTargetSetRef,
            stepReference: input.stepReference,
            execution: input.execution,
            review: input.review,
            sourceRefs: input.sourceRefs,
            startedAt: input.startedAt,
            endedAt: input.endedAt
        )
    }

    public static func derivedTurnId(for input: InteractionTurnBuildInput) -> String {
        let taskToken = sanitizedToken(input.taskId)
        return "turn-\(input.mode.rawValue)-\(input.turnKind.rawValue)-\(taskToken)-\(input.stepId)"
    }

    public static func derivedTraceId(for input: InteractionTurnBuildInput) -> String {
        let taskToken = sanitizedToken(input.taskId)
        return "trace-learning-\(input.mode.rawValue)-\(taskToken)-\(input.stepId)"
    }

    public static func deriveStatus(for input: InteractionTurnBuildInput) -> InteractionTurnStatus {
        guard let execution = input.execution else {
            return .captured
        }

        let normalizedStatus = execution.status.lowercased()
        if normalizedStatus.contains("blocked") {
            return .blocked
        }
        if normalizedStatus.contains("failed") {
            return .failed
        }
        return .succeeded
    }

    public static func deriveLearningState(for input: InteractionTurnBuildInput) -> InteractionTurnLearningState {
        if input.privacyTags.contains(where: isExclusionPrivacyTag(_:)) {
            return .excluded
        }
        if input.review != nil {
            return .reviewed
        }
        if input.execution != nil || !input.sourceRefs.isEmpty {
            return .linked
        }
        return .captured
    }

    public static func deriveRiskLevel(for input: InteractionTurnBuildInput) -> InteractionTurnRiskLevel {
        if input.review?.decision == TeacherQuickFeedbackAction.tooDangerous.rawValue {
            return .critical
        }

        if input.privacyTags.contains(where: isExclusionPrivacyTag(_:)) {
            return .high
        }

        if let locatorType = input.semanticTargetSetRef?.preferredLocatorType,
           locatorType == .coordinateFallback {
            return .high
        }

        if let execution = input.execution,
           let errorCode = execution.errorCode,
           !errorCode.isEmpty {
            return .high
        }

        if input.actionKind == .nativeAction {
            return .medium
        }

        return .low
    }

    private static func isExclusionPrivacyTag(_ tag: String) -> Bool {
        let normalized = tag.lowercased()
        return normalized.contains("excluded")
            || normalized.contains("sensitive")
            || normalized.contains("redacted")
    }

    private static func sanitizedToken(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let token = String(scalars)
        return token.isEmpty ? "turn" : token
    }
}
