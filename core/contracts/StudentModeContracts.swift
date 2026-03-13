import Foundation

// MARK: - Planning

public enum StudentPlanningStrategy: String, Codable, Sendable {
    case ruleV0
    case modelV1Placeholder
}

public struct StudentPlannedStep: Codable, Equatable, Sendable {
    public let planStepId: String
    public let skillId: String
    public let instruction: String
    public let sourceKnowledgeItemId: String
    public let sourceStepId: String
    public let confidence: Double

    public init(
        planStepId: String,
        skillId: String,
        instruction: String,
        sourceKnowledgeItemId: String,
        sourceStepId: String,
        confidence: Double
    ) {
        self.planStepId = planStepId
        self.skillId = skillId
        self.instruction = instruction
        self.sourceKnowledgeItemId = sourceKnowledgeItemId
        self.sourceStepId = sourceStepId
        self.confidence = confidence
    }
}

public struct StudentExecutionPlan: Codable, Equatable, Sendable {
    public let planId: String
    public let goal: String
    public let selectedKnowledgeItemId: String
    public let selectedTaskId: String
    public let strategy: StudentPlanningStrategy
    public let plannerVersion: String
    public let steps: [StudentPlannedStep]

    public init(
        planId: String,
        goal: String,
        selectedKnowledgeItemId: String,
        selectedTaskId: String,
        strategy: StudentPlanningStrategy,
        plannerVersion: String = "rule-v0",
        steps: [StudentPlannedStep]
    ) {
        self.planId = planId
        self.goal = goal
        self.selectedKnowledgeItemId = selectedKnowledgeItemId
        self.selectedTaskId = selectedTaskId
        self.strategy = strategy
        self.plannerVersion = plannerVersion
        self.steps = steps
    }
}

// MARK: - Execution

public enum StudentStepExecutionStatus: String, Codable, Sendable {
    case succeeded
    case failed
    case blocked
}

public struct StudentStepExecutionResult: Codable, Equatable, Sendable {
    public let planStepId: String
    public let skillId: String
    public let status: StudentStepExecutionStatus
    public let startedAt: String
    public let finishedAt: String
    public let output: String
    public let errorCode: StudentLoopErrorCode?

    public init(
        planStepId: String,
        skillId: String,
        status: StudentStepExecutionStatus,
        startedAt: String,
        finishedAt: String,
        output: String,
        errorCode: StudentLoopErrorCode? = nil
    ) {
        self.planStepId = planStepId
        self.skillId = skillId
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.output = output
        self.errorCode = errorCode
    }
}

// MARK: - Review

public struct StudentReviewReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let reportId: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let goal: String
    public let plan: StudentExecutionPlan
    public let stepResults: [StudentStepExecutionResult]
    public let startedAt: String
    public let finishedAt: String
    public let totalSteps: Int
    public let succeededSteps: Int
    public let failedSteps: Int
    public let blockedSteps: Int
    public let finalStatus: StudentLoopFinalStatus
    public let summary: String

    public init(
        schemaVersion: String = "student.review-report.v0",
        reportId: String,
        traceId: String,
        sessionId: String,
        taskId: String?,
        goal: String,
        plan: StudentExecutionPlan,
        stepResults: [StudentStepExecutionResult],
        startedAt: String,
        finishedAt: String,
        totalSteps: Int,
        succeededSteps: Int,
        failedSteps: Int,
        blockedSteps: Int,
        finalStatus: StudentLoopFinalStatus,
        summary: String
    ) {
        self.schemaVersion = schemaVersion
        self.reportId = reportId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.goal = goal
        self.plan = plan
        self.stepResults = stepResults
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.totalSteps = totalSteps
        self.succeededSteps = succeededSteps
        self.failedSteps = failedSteps
        self.blockedSteps = blockedSteps
        self.finalStatus = finalStatus
        self.summary = summary
    }
}

// MARK: - Run Result

public enum StudentLoopFinalStatus: String, Codable, Sendable {
    case completed
    case blockedByState
    case noPlan
    case executionFailed
}

public struct StudentLoopRunResult: Codable, Equatable, Sendable {
    public let finalStatus: StudentLoopFinalStatus
    public let plan: StudentExecutionPlan?
    public let report: StudentReviewReport?
    public let logFilePath: String
    public let reportFilePath: String?
    public let message: String

    public init(
        finalStatus: StudentLoopFinalStatus,
        plan: StudentExecutionPlan?,
        report: StudentReviewReport?,
        logFilePath: String,
        reportFilePath: String?,
        message: String
    ) {
        self.finalStatus = finalStatus
        self.plan = plan
        self.report = report
        self.logFilePath = logFilePath
        self.reportFilePath = reportFilePath
        self.message = message
    }
}

// MARK: - Status and Error Code

public enum StudentLoopStatusCode: String, Codable, Sendable {
    case planningReady = "STATUS_ORC_STUDENT_PLAN_READY"
    case executionStarted = "STATUS_EXE_STUDENT_EXECUTION_STARTED"
    case executionCompleted = "STATUS_EXE_STUDENT_EXECUTION_COMPLETED"
    case executionFailed = "STATUS_EXE_STUDENT_EXECUTION_FAILED"
    case reviewGenerated = "STATUS_ORC_STUDENT_REVIEW_GENERATED"
}

public enum StudentLoopErrorCode: String, Codable, Sendable {
    case planningNotFound = "ORC-PLANNING-NOT-FOUND"
    case modeTransitionRejected = "ORC-STATE-TRANSITION-DENIED"
    case blockedAction = "EXE-ACTION-BLOCKED"
    case executionFailed = "EXE-ACTION-FAILED"
}

public struct StudentLoopLogEntry: Codable, Equatable, Sendable {
    public let timestamp: String
    public let traceId: String
    public let sessionId: String
    public let taskId: String?
    public let component: String
    public let status: String
    public let errorCode: String?
    public let message: String
    public let planId: String?
    public let skillId: String?
    public let planStepId: String?
    public let skillName: String?
    public let skillDirectoryPath: String?
    public let sourceKnowledgeItemId: String?
    public let sourceStepId: String?

    public init(
        timestamp: String,
        traceId: String,
        sessionId: String,
        taskId: String?,
        component: String = "student.loop",
        status: String,
        errorCode: String? = nil,
        message: String,
        planId: String? = nil,
        skillId: String? = nil,
        planStepId: String? = nil,
        skillName: String? = nil,
        skillDirectoryPath: String? = nil,
        sourceKnowledgeItemId: String? = nil,
        sourceStepId: String? = nil
    ) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.component = component
        self.status = status
        self.errorCode = errorCode
        self.message = message
        self.planId = planId
        self.skillId = skillId
        self.planStepId = planStepId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.sourceKnowledgeItemId = sourceKnowledgeItemId
        self.sourceStepId = sourceStepId
    }
}
