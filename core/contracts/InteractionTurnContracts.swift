import Foundation

public enum InteractionTurnKind: String, Codable {
    case taskProgression
    case skillExecution
    case repair
}

public enum InteractionTurnActionKind: String, Codable {
    case nativeAction
    case guiAction
}

public enum InteractionTurnStatus: String, Codable {
    case captured
    case succeeded
    case failed
    case blocked
}

public enum InteractionTurnLearningState: String, Codable {
    case captured
    case linked
    case reviewed
    case excluded
}

public enum InteractionTurnRiskLevel: String, Codable, Sendable {
    case low
    case medium
    case high
    case critical
}

public enum InteractionTurnBuildDiagnosticSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

public enum InteractionTurnBuildDiagnosticCode: String, Codable, Sendable {
    case missingObservationSourceRecord = "missing_observation_source_record"
    case missingObservationRawEventLog = "missing_observation_raw_event_log"
    case missingObservationTaskChunk = "missing_observation_task_chunk"
    case missingObservationEvidence = "missing_observation_evidence"
    case missingSemanticTargetSet = "missing_semantic_target_set"
    case missingKnowledgeItemLink = "missing_knowledge_item_link"
    case missingExecutionArtifacts = "missing_execution_artifacts"
    case missingReviewRawReference = "missing_review_raw_reference"
    case missingBenchmarkLink = "missing_benchmark_link"
    case missingRepairRequestLink = "missing_repair_request_link"
}

public struct InteractionTurnBuildDiagnostic: Codable, Equatable, Sendable {
    public let code: InteractionTurnBuildDiagnosticCode
    public let severity: InteractionTurnBuildDiagnosticSeverity
    public let field: String
    public let message: String

    public init(
        code: InteractionTurnBuildDiagnosticCode,
        severity: InteractionTurnBuildDiagnosticSeverity,
        field: String,
        message: String
    ) {
        self.code = code
        self.severity = severity
        self.field = field
        self.message = message
    }
}

public struct InteractionTurnAppContext: Codable, Equatable {
    public let appName: String
    public let appBundleId: String
    public let windowTitle: String?
    public let windowId: String?
    public let windowSignature: String?

    public init(
        appName: String,
        appBundleId: String,
        windowTitle: String? = nil,
        windowId: String? = nil,
        windowSignature: String? = nil
    ) {
        self.appName = appName
        self.appBundleId = appBundleId
        self.windowTitle = windowTitle
        self.windowId = windowId
        self.windowSignature = windowSignature
    }
}

public struct InteractionTurnObservationReference: Codable, Equatable {
    public let sourceRecordPath: String?
    public let rawEventLogPath: String?
    public let taskChunkPath: String?
    public let eventIds: [String]
    public let screenshotRefs: [String]
    public let axRefs: [String]
    public let ocrRefs: [String]
    public let appContext: InteractionTurnAppContext
    public let note: String?

    public init(
        sourceRecordPath: String? = nil,
        rawEventLogPath: String? = nil,
        taskChunkPath: String? = nil,
        eventIds: [String] = [],
        screenshotRefs: [String] = [],
        axRefs: [String] = [],
        ocrRefs: [String] = [],
        appContext: InteractionTurnAppContext,
        note: String? = nil
    ) {
        self.sourceRecordPath = sourceRecordPath
        self.rawEventLogPath = rawEventLogPath
        self.taskChunkPath = taskChunkPath
        self.eventIds = eventIds
        self.screenshotRefs = screenshotRefs
        self.axRefs = axRefs
        self.ocrRefs = ocrRefs
        self.appContext = appContext
        self.note = note
    }
}

public struct InteractionTurnSemanticTargetSetReference: Codable, Equatable {
    public let sourcePath: String?
    public let sourceStepId: String?
    public let preferredLocatorType: SemanticLocatorType?
    public let candidateCount: Int
    public let semanticTargets: [SemanticTarget]

    public init(
        sourcePath: String? = nil,
        sourceStepId: String? = nil,
        preferredLocatorType: SemanticLocatorType? = nil,
        semanticTargets: [SemanticTarget] = []
    ) {
        self.sourcePath = sourcePath
        self.sourceStepId = sourceStepId
        self.preferredLocatorType = preferredLocatorType
        self.candidateCount = semanticTargets.count
        self.semanticTargets = semanticTargets
    }
}

public struct InteractionTurnStepReference: Codable, Equatable {
    public let stepId: String
    public let stepIndex: Int
    public let instruction: String
    public let knowledgeItemId: String?
    public let knowledgeStepId: String?
    public let skillStepId: String?
    public let planStepId: String?
    public let sourceEventIds: [String]

    public init(
        stepId: String,
        stepIndex: Int,
        instruction: String,
        knowledgeItemId: String? = nil,
        knowledgeStepId: String? = nil,
        skillStepId: String? = nil,
        planStepId: String? = nil,
        sourceEventIds: [String] = []
    ) {
        self.stepId = stepId
        self.stepIndex = stepIndex
        self.instruction = instruction
        self.knowledgeItemId = knowledgeItemId
        self.knowledgeStepId = knowledgeStepId
        self.skillStepId = skillStepId
        self.planStepId = planStepId
        self.sourceEventIds = sourceEventIds
    }
}

public struct InteractionTurnExecutionLink: Codable, Equatable {
    public let traceId: String
    public let component: String
    public let skillName: String?
    public let skillDirectoryPath: String?
    public let planId: String?
    public let planStepId: String?
    public let status: String
    public let errorCode: String?
    public let executionLogPath: String?
    public let executionResultPath: String?
    public let reviewId: String?

    public init(
        traceId: String,
        component: String,
        skillName: String? = nil,
        skillDirectoryPath: String? = nil,
        planId: String? = nil,
        planStepId: String? = nil,
        status: String,
        errorCode: String? = nil,
        executionLogPath: String? = nil,
        executionResultPath: String? = nil,
        reviewId: String? = nil
    ) {
        self.traceId = traceId
        self.component = component
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.planId = planId
        self.planStepId = planStepId
        self.status = status
        self.errorCode = errorCode
        self.executionLogPath = executionLogPath
        self.executionResultPath = executionResultPath
        self.reviewId = reviewId
    }
}

public struct InteractionTurnReviewLink: Codable, Equatable {
    public let reviewId: String
    public let source: String
    public let decision: String
    public let summary: String
    public let note: String?
    public let reviewedAt: String
    public let rawRef: String?

    public init(
        reviewId: String,
        source: String,
        decision: String,
        summary: String,
        note: String? = nil,
        reviewedAt: String,
        rawRef: String? = nil
    ) {
        self.reviewId = reviewId
        self.source = source
        self.decision = decision
        self.summary = summary
        self.note = note
        self.reviewedAt = reviewedAt
        self.rawRef = rawRef
    }
}

public struct InteractionTurnSourceReference: Codable, Equatable {
    public let artifactKind: String
    public let path: String
    public let identifier: String?
    public let sha256: String?

    public init(
        artifactKind: String,
        path: String,
        identifier: String? = nil,
        sha256: String? = nil
    ) {
        self.artifactKind = artifactKind
        self.path = path
        self.identifier = identifier
        self.sha256 = sha256
    }
}

public struct InteractionTurn: Codable, Equatable {
    public let schemaVersion: String
    public let turnId: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let mode: OpenStaffMode
    public let turnKind: InteractionTurnKind
    public let stepIndex: Int
    public let intentSummary: String
    public let actionSummary: String
    public let actionKind: InteractionTurnActionKind
    public let status: InteractionTurnStatus
    public let learningState: InteractionTurnLearningState
    public let privacyTags: [String]
    public let riskLevel: InteractionTurnRiskLevel
    public let appContext: InteractionTurnAppContext
    public let observationRef: InteractionTurnObservationReference
    public let semanticTargetSetRef: InteractionTurnSemanticTargetSetReference?
    public let stepReference: InteractionTurnStepReference
    public let execution: InteractionTurnExecutionLink?
    public let review: InteractionTurnReviewLink?
    public let sourceRefs: [InteractionTurnSourceReference]
    public let buildDiagnostics: [InteractionTurnBuildDiagnostic]?
    public let startedAt: String
    public let endedAt: String

    public init(
        schemaVersion: String = "openstaff.learning.interaction-turn.v0",
        turnId: String,
        traceId: String,
        sessionId: String,
        taskId: String,
        stepId: String,
        mode: OpenStaffMode,
        turnKind: InteractionTurnKind,
        stepIndex: Int,
        intentSummary: String,
        actionSummary: String,
        actionKind: InteractionTurnActionKind,
        status: InteractionTurnStatus,
        learningState: InteractionTurnLearningState,
        privacyTags: [String],
        riskLevel: InteractionTurnRiskLevel,
        appContext: InteractionTurnAppContext,
        observationRef: InteractionTurnObservationReference,
        semanticTargetSetRef: InteractionTurnSemanticTargetSetReference? = nil,
        stepReference: InteractionTurnStepReference,
        execution: InteractionTurnExecutionLink? = nil,
        review: InteractionTurnReviewLink? = nil,
        sourceRefs: [InteractionTurnSourceReference],
        buildDiagnostics: [InteractionTurnBuildDiagnostic]? = nil,
        startedAt: String,
        endedAt: String
    ) {
        self.schemaVersion = schemaVersion
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
        self.status = status
        self.learningState = learningState
        self.privacyTags = privacyTags
        self.riskLevel = riskLevel
        self.appContext = appContext
        self.observationRef = observationRef
        self.semanticTargetSetRef = semanticTargetSetRef
        self.stepReference = stepReference
        self.execution = execution
        self.review = review
        self.sourceRefs = sourceRefs
        self.buildDiagnostics = buildDiagnostics
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}
