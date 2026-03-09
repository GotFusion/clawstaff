import Foundation

@main
struct OpenStaffOrchestratorCLI {
    static func main() {
        do {
            let options = try OrchestratorCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let logger = StdoutOrchestratorStateLogger()
            let stateMachine = ModeStateMachine(initialMode: options.initialMode, logger: logger)

            if options.printCapabilities {
                printCapabilities(stateMachine: stateMachine)
            }

            guard let targetMode = options.targetMode else {
                if options.printCapabilities {
                    return
                }
                throw OrchestratorCLIOptionError.missingRequired("--to")
            }

            let context = ModeTransitionContext(
                traceId: options.traceId,
                sessionId: options.sessionId,
                taskId: options.taskId,
                timestamp: options.timestamp,
                teacherConfirmed: options.teacherConfirmed,
                learnedKnowledgeReady: options.learnedKnowledgeReady,
                executionPlanReady: options.executionPlanReady,
                pendingAssistSuggestion: options.pendingAssistSuggestion,
                emergencyStopActive: options.emergencyStopActive
            )

            let decision = stateMachine.transition(to: targetMode, context: context)

            if options.printJSONDecision {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(decision)
                if let output = String(data: data, encoding: .utf8) {
                    print(output)
                }
            } else {
                print("Decision: accepted=\(decision.accepted) from=\(decision.fromMode.rawValue) to=\(decision.toMode.rawValue) status=\(decision.status.rawValue)")
                if !decision.unmetRequirements.isEmpty {
                    print("Unmet requirements: \(decision.unmetRequirements.map(\.rawValue).joined(separator: ", "))")
                }
                if let errorCode = decision.errorCode {
                    print("errorCode=\(errorCode.rawValue)")
                }
            }

            if !decision.accepted {
                Foundation.exit(2)
            }
        } catch {
            print("Orchestrator CLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffOrchestratorCLI

        Usage:
          make orchestrator ARGS="--from teaching --to assist --session-id session-20260308-a1 --teacher-confirmed --knowledge-ready"

        Flags:
          --from <teaching|assist|student>   Initial mode. Default: teaching
          --to <teaching|assist|student>     Target mode to switch to.
          --session-id <id>                  Session ID used in structured logs. Default: session-default
          --task-id <id>                     Optional task ID used in structured logs.
          --trace-id <id>                    Trace ID used in structured logs. Default: auto generated.
          --timestamp <iso8601>              Timestamp used in structured logs. Default: now.

          --teacher-confirmed                Guard input: teacher confirmation is true.
          --knowledge-ready                  Guard input: learned knowledge is ready.
          --plan-ready                       Guard input: execution plan is ready.
          --pending-assist-suggestion        Guard input: assist suggestion still pending.
          --emergency-stop-active            Guard input: emergency stop is active.

          --print-capabilities               Print capability whitelist for all modes.
          --json-decision                    Print transition decision as formatted JSON.
          --help                             Show this help message.
        """)
    }

    static func printCapabilities(stateMachine: ModeStateMachine) {
        print("Capability whitelist:")
        for mode in OpenStaffMode.allCases {
            let capabilities = stateMachine
                .allowedCapabilities(for: mode)
                .map(\.rawValue)
                .sorted()
                .joined(separator: ", ")
            print("  \(mode.rawValue): \(capabilities)")
        }
    }
}

struct OrchestratorCLIOptions {
    let initialMode: OpenStaffMode
    let targetMode: OpenStaffMode?
    let sessionId: String
    let taskId: String?
    let traceId: String
    let timestamp: String
    let teacherConfirmed: Bool
    let learnedKnowledgeReady: Bool
    let executionPlanReady: Bool
    let pendingAssistSuggestion: Bool
    let emergencyStopActive: Bool
    let printCapabilities: Bool
    let printJSONDecision: Bool
    let showHelp: Bool

    static func parse(arguments: [String]) throws -> OrchestratorCLIOptions {
        var initialMode: OpenStaffMode = .teaching
        var targetMode: OpenStaffMode?
        var sessionId = "session-default"
        var taskId: String?
        var traceId = "trace-\(UUID().uuidString.lowercased())"
        var timestamp = currentTimestamp()
        var teacherConfirmed = false
        var learnedKnowledgeReady = false
        var executionPlanReady = false
        var pendingAssistSuggestion = false
        var emergencyStopActive = false
        var printCapabilities = false
        var printJSONDecision = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--from":
                index += 1
                guard index < arguments.count else {
                    throw OrchestratorCLIOptionError.missingValue("--from")
                }
                guard let parsed = OpenStaffMode(rawValue: arguments[index]) else {
                    throw OrchestratorCLIOptionError.invalidValue("--from", arguments[index])
                }
                initialMode = parsed
            case "--to":
                index += 1
                guard index < arguments.count else {
                    throw OrchestratorCLIOptionError.missingValue("--to")
                }
                guard let parsed = OpenStaffMode(rawValue: arguments[index]) else {
                    throw OrchestratorCLIOptionError.invalidValue("--to", arguments[index])
                }
                targetMode = parsed
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw OrchestratorCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--task-id":
                index += 1
                guard index < arguments.count else {
                    throw OrchestratorCLIOptionError.missingValue("--task-id")
                }
                taskId = arguments[index]
            case "--trace-id":
                index += 1
                guard index < arguments.count else {
                    throw OrchestratorCLIOptionError.missingValue("--trace-id")
                }
                traceId = arguments[index]
            case "--timestamp":
                index += 1
                guard index < arguments.count else {
                    throw OrchestratorCLIOptionError.missingValue("--timestamp")
                }
                timestamp = arguments[index]
            case "--teacher-confirmed":
                teacherConfirmed = true
            case "--knowledge-ready":
                learnedKnowledgeReady = true
            case "--plan-ready":
                executionPlanReady = true
            case "--pending-assist-suggestion":
                pendingAssistSuggestion = true
            case "--emergency-stop-active":
                emergencyStopActive = true
            case "--print-capabilities":
                printCapabilities = true
            case "--json-decision":
                printJSONDecision = true
            case "--help", "-h":
                showHelp = true
            default:
                throw OrchestratorCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if !showHelp {
            guard isValidSessionId(sessionId) else {
                throw OrchestratorCLIOptionError.invalidValue("--session-id", sessionId)
            }
            guard isValidTraceId(traceId) else {
                throw OrchestratorCLIOptionError.invalidValue("--trace-id", traceId)
            }
            guard isValidISO8601(timestamp) else {
                throw OrchestratorCLIOptionError.invalidValue("--timestamp", timestamp)
            }
            if let taskId, !isValidTaskId(taskId) {
                throw OrchestratorCLIOptionError.invalidValue("--task-id", taskId)
            }
        }

        return OrchestratorCLIOptions(
            initialMode: initialMode,
            targetMode: targetMode,
            sessionId: sessionId,
            taskId: taskId,
            traceId: traceId,
            timestamp: timestamp,
            teacherConfirmed: teacherConfirmed,
            learnedKnowledgeReady: learnedKnowledgeReady,
            executionPlanReady: executionPlanReady,
            pendingAssistSuggestion: pendingAssistSuggestion,
            emergencyStopActive: emergencyStopActive,
            printCapabilities: printCapabilities,
            printJSONDecision: printJSONDecision,
            showHelp: showHelp
        )
    }

    private static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func isValidSessionId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidTaskId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidTraceId(_ value: String) -> Bool {
        let pattern = "^[a-z0-9-]+$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isValidISO8601(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if formatter.date(from: value) != nil {
            return true
        }

        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }
}

enum OrchestratorCLIOptionError: LocalizedError {
    case missingValue(String)
    case missingRequired(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let flag):
            return "Missing value for \(flag)."
        case .missingRequired(let flag):
            return "Missing required flag: \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value for \(flag): \(value)."
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag). Use --help to see supported flags."
        }
    }
}
