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
    public let buildDiagnostics: [InteractionTurnBuildDiagnostic]?
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
        buildDiagnostics: [InteractionTurnBuildDiagnostic]? = nil,
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
        self.buildDiagnostics = buildDiagnostics
        self.privacyTags = privacyTags
        self.learningState = learningState
        self.riskLevel = riskLevel
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct InteractionTurnBuildResult: Equatable {
    public let turn: InteractionTurn
    public let diagnostics: [InteractionTurnBuildDiagnostic]

    public init(
        turn: InteractionTurn,
        diagnostics: [InteractionTurnBuildDiagnostic]
    ) {
        self.turn = turn
        self.diagnostics = diagnostics
    }
}

public enum InteractionTurnBuilder {
    public static func build(_ input: InteractionTurnBuildInput) -> InteractionTurn {
        buildResult(input).turn
    }

    public static func buildResult(_ input: InteractionTurnBuildInput) -> InteractionTurnBuildResult {
        let traceId = input.traceId ?? derivedTraceId(for: input)
        let turnId = input.turnId ?? derivedTurnId(for: input)
        let status = input.status ?? deriveStatus(for: input)
        let learningState = input.learningState ?? deriveLearningState(for: input)
        let riskLevel = input.riskLevel ?? deriveRiskLevel(for: input)
        let diagnostics = derivedDiagnostics(for: input)

        let turn = InteractionTurn(
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
            buildDiagnostics: diagnostics.isEmpty ? input.buildDiagnostics : diagnostics,
            startedAt: input.startedAt,
            endedAt: input.endedAt
        )

        return InteractionTurnBuildResult(
            turn: turn,
            diagnostics: diagnostics
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

    private static func derivedDiagnostics(
        for input: InteractionTurnBuildInput
    ) -> [InteractionTurnBuildDiagnostic] {
        var diagnostics = input.buildDiagnostics ?? []

        let sourceRefKinds = Set(
            input.sourceRefs.map { $0.artifactKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        if input.observationRef.sourceRecordPath == nil {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingObservationSourceRecord,
                    severity: .info,
                    field: "observationRef.sourceRecordPath",
                    message: "source record 缺失，当前 turn 只能回链到 raw event / task chunk 侧证据。"
                )
            )
        }

        if input.observationRef.rawEventLogPath == nil {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingObservationRawEventLog,
                    severity: .warning,
                    field: "observationRef.rawEventLogPath",
                    message: "raw event log 路径缺失，无法直接回放原始事件日志。"
                )
            )
        }

        if input.observationRef.taskChunkPath == nil {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingObservationTaskChunk,
                    severity: .info,
                    field: "observationRef.taskChunkPath",
                    message: "task chunk 路径缺失，turn 只能依赖 step reference 追溯任务切片。"
                )
            )
        }

        if input.observationRef.rawEventLogPath == nil
            && input.observationRef.taskChunkPath == nil
            && input.observationRef.sourceRecordPath == nil
            && input.observationRef.eventIds.isEmpty
        {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingObservationEvidence,
                    severity: .error,
                    field: "observationRef",
                    message: "缺少 source record、raw event、task chunk 和 eventIds，观察证据不足。"
                )
            )
        }

        if input.actionKind == .guiAction, input.semanticTargetSetRef == nil {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingSemanticTargetSet,
                    severity: .warning,
                    field: "semanticTargetSetRef",
                    message: "GUI turn 缺少 semantic target 候选，后续 replay / repair 只能依赖弱上下文。"
                )
            )
        }

        if input.stepReference.knowledgeItemId == nil {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingKnowledgeItemLink,
                    severity: .warning,
                    field: "stepReference.knowledgeItemId",
                    message: "knowledgeItemId 缺失，无法从 turn 直接回链知识条目。"
                )
            )
        }

        if let execution = input.execution,
           execution.executionLogPath == nil,
           execution.executionResultPath == nil
        {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingExecutionArtifacts,
                    severity: .warning,
                    field: "execution",
                    message: "execution 已存在，但 executionLogPath / executionResultPath 均缺失。"
                )
            )
        }

        if let review = input.review, review.rawRef == nil {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingReviewRawReference,
                    severity: .info,
                    field: "review.rawRef",
                    message: "review 已存在，但 rawRef 缺失，无法直接回链原始审阅工件。"
                )
            )
        }

        if input.review?.source == "benchmarkResult",
           !sourceRefKinds.contains("benchmarkreview") {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingBenchmarkLink,
                    severity: .warning,
                    field: "sourceRefs",
                    message: "turn 来源于 benchmark，但 sourceRefs 中缺少 benchmarkReview 关联。"
                )
            )
        }

        if let reviewDecision = input.review?.decision,
           [TeacherQuickFeedbackAction.fixLocator.rawValue, TeacherQuickFeedbackAction.reteach.rawValue].contains(reviewDecision),
           !sourceRefKinds.contains("repairrequest"),
           !sourceRefKinds.contains("skillrepairrequest")
        {
            diagnostics.append(
                InteractionTurnBuildDiagnostic(
                    code: .missingRepairRequestLink,
                    severity: .info,
                    field: "sourceRefs",
                    message: "老师要求修复，但当前 turn 尚未关联 repair request 工件。"
                )
            )
        }

        return dedupedDiagnostics(diagnostics)
    }

    private static func dedupedDiagnostics(
        _ diagnostics: [InteractionTurnBuildDiagnostic]
    ) -> [InteractionTurnBuildDiagnostic] {
        var seen = Set<String>()
        var deduped: [InteractionTurnBuildDiagnostic] = []

        for diagnostic in diagnostics {
            let key = [
                diagnostic.code.rawValue,
                diagnostic.severity.rawValue,
                diagnostic.field,
                diagnostic.message
            ].joined(separator: "|")
            guard seen.insert(key).inserted else {
                continue
            }
            deduped.append(diagnostic)
        }

        return deduped.sorted {
            ($0.severity.rawValue, $0.code.rawValue, $0.field) < ($1.severity.rawValue, $1.code.rawValue, $1.field)
        }
    }
}
