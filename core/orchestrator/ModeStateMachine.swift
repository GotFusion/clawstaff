import Foundation

public protocol OrchestratorStateLogger {
    func log(_ entry: OrchestratorLogEntry)
}

public final class StdoutOrchestratorStateLogger: OrchestratorStateLogger {
    private let encoder: JSONEncoder

    public init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func log(_ entry: OrchestratorLogEntry) {
        guard let data = try? encoder.encode(entry),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        print(line)
    }
}

public final class InMemoryOrchestratorStateLogger: OrchestratorStateLogger {
    public private(set) var entries: [OrchestratorLogEntry] = []

    public init() {}

    public func log(_ entry: OrchestratorLogEntry) {
        entries.append(entry)
    }
}

public final class ModeStateMachine {
    private struct Rule: Sendable {
        let requirements: [ModeTransitionRequirement]
    }

    private static let transitionRules: [OpenStaffMode: [OpenStaffMode: Rule]] = [
        .teaching: [
            .assist: Rule(requirements: [.teacherConfirmed, .learnedKnowledgeReady, .emergencyStopInactive])
        ],
        .assist: [
            .teaching: Rule(requirements: []),
            .student: Rule(requirements: [.teacherConfirmed, .learnedKnowledgeReady, .executionPlanReady, .noPendingAssistSuggestion, .emergencyStopInactive])
        ],
        .student: [
            .assist: Rule(requirements: [.teacherConfirmed, .emergencyStopInactive]),
            .teaching: Rule(requirements: [])
        ]
    ]

    private static let capabilityWhitelist: [OpenStaffMode: Set<OrchestratorCapability>] = [
        .teaching: [.observeTeacherActions, .captureRawEvents, .sliceTasks, .buildKnowledgeItems, .summarizeKnowledge],
        .assist: [.observeTeacherActions, .predictNextAction, .requestTeacherConfirmation, .executeConfirmedAction],
        .student: [.planAutonomousTask, .executeAutonomousTask, .generateExecutionReport]
    ]

    public private(set) var currentMode: OpenStaffMode
    private let logger: OrchestratorStateLogger

    public init(initialMode: OpenStaffMode = .teaching, logger: OrchestratorStateLogger = StdoutOrchestratorStateLogger()) {
        self.currentMode = initialMode
        self.logger = logger
    }

    public func allowedCapabilities(for mode: OpenStaffMode? = nil) -> Set<OrchestratorCapability> {
        let resolvedMode = mode ?? currentMode
        return Self.capabilityWhitelist[resolvedMode] ?? []
    }

    public func setCurrentMode(_ mode: OpenStaffMode) {
        currentMode = mode
    }

    @discardableResult
    public func transition(to targetMode: OpenStaffMode, context: ModeTransitionContext) -> ModeTransitionDecision {
        let sourceMode = currentMode

        guard sourceMode != targetMode else {
            let decision = ModeTransitionDecision(
                fromMode: sourceMode,
                toMode: targetMode,
                accepted: false,
                status: .modeStable,
                errorCode: .transitionDenied,
                message: "Source mode and target mode are the same."
            )
            log(decision: decision, context: context)
            return decision
        }

        guard let rule = Self.transitionRules[sourceMode]?[targetMode] else {
            let decision = ModeTransitionDecision(
                fromMode: sourceMode,
                toMode: targetMode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .transitionDenied,
                message: "Transition from \(sourceMode.rawValue) to \(targetMode.rawValue) is not allowed."
            )
            log(decision: decision, context: context)
            return decision
        }

        let unmetRequirements = rule.requirements.filter { !Self.isRequirementMet($0, context: context) }
        guard unmetRequirements.isEmpty else {
            let decision = ModeTransitionDecision(
                fromMode: sourceMode,
                toMode: targetMode,
                accepted: false,
                status: .modeTransitionRejected,
                errorCode: .guardConditionFailed,
                unmetRequirements: unmetRequirements,
                message: "Transition guard conditions are not met."
            )
            log(decision: decision, context: context)
            return decision
        }

        currentMode = targetMode
        let decision = ModeTransitionDecision(
            fromMode: sourceMode,
            toMode: targetMode,
            accepted: true,
            status: .modeTransitionAccepted,
            message: "Mode transition accepted."
        )
        log(decision: decision, context: context)
        return decision
    }

    private func log(decision: ModeTransitionDecision, context: ModeTransitionContext) {
        let entry = OrchestratorLogEntry(
            timestamp: context.timestamp,
            traceId: context.traceId,
            sessionId: context.sessionId,
            taskId: context.taskId,
            status: decision.status.rawValue,
            errorCode: decision.errorCode?.rawValue,
            message: decision.message,
            fromMode: decision.fromMode,
            toMode: decision.toMode,
            unmetRequirements: decision.unmetRequirements
        )
        logger.log(entry)
    }

    private static func isRequirementMet(_ requirement: ModeTransitionRequirement, context: ModeTransitionContext) -> Bool {
        switch requirement {
        case .teacherConfirmed:
            return context.teacherConfirmed
        case .learnedKnowledgeReady:
            return context.learnedKnowledgeReady
        case .executionPlanReady:
            return context.executionPlanReady
        case .noPendingAssistSuggestion:
            return !context.pendingAssistSuggestion
        case .emergencyStopInactive:
            return !context.emergencyStopActive
        }
    }
}
