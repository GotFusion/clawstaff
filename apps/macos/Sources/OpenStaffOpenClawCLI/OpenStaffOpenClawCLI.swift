import Foundation

@main
struct OpenStaffOpenClawCLI {
    static func main() {
        do {
            let options = try OpenClawCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            if options.gatewayMode {
                let payload = try executeGateway(options: options)
                emitGateway(payload: payload, jsonResult: options.jsonResult)
                Foundation.exit(payload.status == .succeeded ? 0 : 2)
            }

            let descriptor = try OpenClawSkillDescriptorLoader().load(from: options.skillDirectoryURL)
            let traceId = options.traceId ?? "trace-openclaw-run-\(UUID().uuidString.lowercased())"
            let sessionId = options.sessionId ?? descriptor.sessionId
            let taskId = options.taskId ?? descriptor.taskId
            let runtimeExecutablePath = options.runtimeExecutablePath
                ?? ProcessInfo.processInfo.environment["OPENCLAW_CLI_PATH"]
                ?? (CommandLine.arguments.first ?? "")

            let request = OpenClawExecutionRequest(
                traceId: traceId,
                sessionId: sessionId,
                taskId: taskId,
                skillName: descriptor.skillName,
                skillDirectoryPath: options.skillDirectoryURL.path,
                runtimeExecutablePath: runtimeExecutablePath,
                runtimeArguments: options.gatewayArguments(
                    skillDirectoryURL: options.skillDirectoryURL,
                    traceId: traceId,
                    sessionId: sessionId,
                    taskId: taskId
                ),
                workingDirectoryPath: options.workingDirectoryPath,
                logsRootDirectoryPath: options.logsRootDirectoryURL.path,
                safetyRulesPath: options.safetyRulesPath,
                timeoutSeconds: options.timeoutSeconds,
                semanticOnly: true,
                teacherConfirmed: options.teacherConfirmed
            )

            let result = OpenClawRunner().execute(request: request)
            emitRunner(result: result, jsonResult: options.jsonResult)
            Foundation.exit(result.status == .succeeded ? 0 : 2)
        } catch {
            print("OpenStaffOpenClawCLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    private static func executeGateway(options: OpenClawCLIOptions) throws -> OpenClawGatewayExecutionPayload {
        let validator = SkillPreflightValidator()
        let skillBundle = try validator.loadSkillBundle(from: options.skillDirectoryURL)
        let traceId = options.traceId ?? "trace-openclaw-gateway-\(UUID().uuidString.lowercased())"
        let sessionId = options.sessionId ?? skillBundle.sessionId
        let taskId = options.taskId ?? skillBundle.taskId
        let startedAt = currentTimestamp()
        let skillName = skillBundle.skillName
        let skillDirectoryPath = options.skillDirectoryURL.path

        guard options.semanticOnly else {
            let finishedAt = currentTimestamp()
            return OpenClawGatewayExecutionPayload(
                traceId: traceId,
                sessionId: sessionId,
                taskId: taskId,
                skillName: skillName,
                skillDirectoryPath: skillDirectoryPath,
                status: .failed,
                errorCode: OpenClawExecutionErrorCode.semanticOnlyRequired.rawValue,
                startedAt: startedAt,
                finishedAt: finishedAt,
                summary: "Gateway refused legacy execution entry because --semantic-only was not provided. Coordinate execution is disabled by SEM-001.",
                totalSteps: 0,
                succeededSteps: 0,
                failedSteps: 0,
                blockedSteps: 0,
                stepResults: []
            )
        }

        let preflight = validator.validate(
            payload: skillBundle,
            skillDirectoryPath: skillDirectoryPath,
            options: SkillPreflightOptions(
                safetyRulesPath: options.safetyRulesPath,
                semanticOnly: options.semanticOnly
            )
        )
        if preflight.status == .failed {
            let finishedAt = currentTimestamp()
            return OpenClawGatewayExecutionPayload(
                traceId: traceId,
                sessionId: sessionId,
                taskId: taskId,
                skillName: skillName,
                skillDirectoryPath: skillDirectoryPath,
                status: gatewayStatus(for: preflight),
                errorCode: gatewayErrorCode(for: preflight),
                startedAt: startedAt,
                finishedAt: finishedAt,
                summary: preflight.summary,
                totalSteps: 0,
                succeededSteps: 0,
                failedSteps: 0,
                blockedSteps: 0,
                stepResults: []
            )
        }

        if preflight.requiresTeacherConfirmation && !options.teacherConfirmed {
            let finishedAt = currentTimestamp()
            return OpenClawGatewayExecutionPayload(
                traceId: traceId,
                sessionId: sessionId,
                taskId: taskId,
                skillName: skillName,
                skillDirectoryPath: skillDirectoryPath,
                status: .blocked,
                errorCode: OpenClawExecutionErrorCode.skillConfirmationRequired.rawValue,
                startedAt: startedAt,
                finishedAt: finishedAt,
                summary: preflight.summary,
                totalSteps: 0,
                succeededSteps: 0,
                failedSteps: 0,
                blockedSteps: 0,
                stepResults: []
            )
        }

        guard !skillBundle.mappedOutput.executionPlan.steps.isEmpty else {
            let finishedAt = currentTimestamp()
            return OpenClawGatewayExecutionPayload(
                traceId: traceId,
                sessionId: sessionId,
                taskId: taskId,
                skillName: skillName,
                skillDirectoryPath: skillDirectoryPath,
                status: .failed,
                errorCode: OpenClawExecutionErrorCode.invalidSkillBundle.rawValue,
                startedAt: startedAt,
                finishedAt: finishedAt,
                summary: "Skill bundle does not contain executable steps.",
                totalSteps: 0,
                succeededSteps: 0,
                failedSteps: 0,
                blockedSteps: 0,
                stepResults: []
            )
        }

        var stepResults: [OpenClawExecutionStepResult] = []
        stepResults.reserveCapacity(skillBundle.mappedOutput.executionPlan.steps.count)

        var succeededSteps = 0
        var failedSteps = 0
        let blockedSteps = 0
        var gatewayErrorCode: String?

        for (index, step) in skillBundle.mappedOutput.executionPlan.steps.enumerated() {
            let stepStartedAt = currentTimestamp()
            let stepFinishedAt = currentTimestamp()

            if options.simulateRuntimeFailureAtStepIndex == index + 1 {
                let errorCode = OpenClawExecutionErrorCode.runtimeFailed.rawValue
                gatewayErrorCode = errorCode
                failedSteps += 1
                stepResults.append(
                    OpenClawExecutionStepResult(
                        stepId: step.stepId,
                        actionType: step.actionType,
                        status: .failed,
                        startedAt: stepStartedAt,
                        finishedAt: stepFinishedAt,
                        output: "Gateway simulated failure at step \(step.stepId).",
                        errorCode: errorCode
                    )
                )
                break
            }

            let target = step.target.trimmingCharacters(in: .whitespacesAndNewlines)
            if step.actionType == "unknown" {
                let errorCode = OpenClawExecutionErrorCode.invalidSkillBundle.rawValue
                gatewayErrorCode = errorCode
                failedSteps += 1
                stepResults.append(
                    OpenClawExecutionStepResult(
                        stepId: step.stepId,
                        actionType: step.actionType,
                        status: .failed,
                        startedAt: stepStartedAt,
                        finishedAt: stepFinishedAt,
                        output: "Gateway refused step \(step.stepId) because actionType is not executable.",
                        errorCode: errorCode
                    )
                )
                break
            }

            succeededSteps += 1
            stepResults.append(
                OpenClawExecutionStepResult(
                    stepId: step.stepId,
                    actionType: step.actionType,
                    status: .succeeded,
                    startedAt: stepStartedAt,
                    finishedAt: stepFinishedAt,
                    output: "Gateway executed \(step.actionType) -> \(target.isEmpty ? "unknown" : target)"
                )
            )
        }

        let finishedAt = currentTimestamp()
        let finalStatus: OpenClawExecutionStatus = failedSteps > 0 ? .failed : .succeeded

        let totalSteps = skillBundle.mappedOutput.executionPlan.steps.count
        let summary = "Gateway finished skill \(skillName). total=\(totalSteps) succeeded=\(succeededSteps) failed=\(failedSteps) blocked=\(blockedSteps)"
        return OpenClawGatewayExecutionPayload(
            traceId: traceId,
            sessionId: sessionId,
            taskId: taskId,
            skillName: skillName,
            skillDirectoryPath: skillDirectoryPath,
            status: finalStatus,
            errorCode: gatewayErrorCode,
            startedAt: startedAt,
            finishedAt: finishedAt,
            summary: summary,
            totalSteps: totalSteps,
            succeededSteps: succeededSteps,
            failedSteps: failedSteps,
            blockedSteps: blockedSteps,
            stepResults: stepResults
        )
    }

    private static func emitRunner(result: OpenClawExecutionResult, jsonResult: Bool) {
        if jsonResult {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(result),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        print("OpenClaw runner finished. status=\(result.status.rawValue)")
        print("summary=\(result.summary)")
        let exitCodeText = result.exitCode.map { String($0) } ?? "nil"
        print("exitCode=\(exitCodeText)")
        if let preflight = result.preflight {
            print("preflight=\(preflight.status.rawValue)")
        }
        if let review = result.review {
            print("logFile=\(review.logFilePath)")
        }
    }

    private static func emitGateway(payload: OpenClawGatewayExecutionPayload, jsonResult: Bool) {
        if payload.status != .succeeded, let errorCode = payload.errorCode {
            let errorLine = "OpenClaw gateway error: \(errorCode) :: \(payload.summary)\n"
            if let data = errorLine.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }

        if jsonResult {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(payload),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        print("OpenClaw gateway finished. status=\(payload.status.rawValue)")
        print("summary=\(payload.summary)")
    }

    private static func printHelp() {
        print("""
        OpenStaffOpenClawCLI

        Usage:
          swift run --package-path apps/macos OpenStaffOpenClawCLI --skill-dir scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001 --json-result

        Flags:
          --skill-dir <path>                    Skill directory containing SKILL.md and openstaff-skill.json.
          --session-id <id>                     Optional session ID override.
          --task-id <id>                        Optional task ID override.
          --trace-id <id>                       Optional trace ID override.
          --logs-root <path>                    Execution log root. Default: data/logs
          --safety-rules <path>                 Optional safety rules file. Default: config/safety-rules.yaml
          --runtime-executable <path>           Optional runtime executable override. Default: OPENCLAW_CLI_PATH or current executable.
          --working-dir <path>                  Optional subprocess working directory.
          --timeout-seconds <n>                 Subprocess timeout in seconds. Default: 30
          --simulate-runtime-failure-step <n>   Simulate gateway failure on step n (1-based).
          --semantic-only                       Required in --gateway-mode. Runner forwards it automatically.
          --teacher-confirmed                   Confirm teacher approval for skills gated by preflight.
          --gateway-mode                        Internal runtime entry. Must be paired with --semantic-only.
          --json-result                         Print structured JSON result.
          --help                                Show this help message.
        """)
    }

    private static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private struct OpenClawCLIOptions {
    static let defaultLogsRoot = "data/logs"

    let skillDirectoryPath: String
    let sessionId: String?
    let taskId: String?
    let traceId: String?
    let logsRootPath: String
    let safetyRulesPath: String?
    let runtimeExecutablePath: String?
    let workingDirectoryPath: String?
    let timeoutSeconds: Int
    let simulateRuntimeFailureAtStepIndex: Int?
    let teacherConfirmed: Bool
    let semanticOnly: Bool
    let jsonResult: Bool
    let showHelp: Bool
    let gatewayMode: Bool

    var skillDirectoryURL: URL {
        resolve(path: skillDirectoryPath)
    }

    var logsRootDirectoryURL: URL {
        resolve(path: logsRootPath)
    }

    static func parse(arguments: [String]) throws -> OpenClawCLIOptions {
        var skillDirectoryPath: String?
        var sessionId: String?
        var taskId: String?
        var traceId: String?
        var logsRootPath = defaultLogsRoot
        var safetyRulesPath: String?
        var runtimeExecutablePath: String?
        var workingDirectoryPath: String?
        var timeoutSeconds = 30
        var simulateRuntimeFailureAtStepIndex: Int?
        var teacherConfirmed = false
        var semanticOnly = false
        var jsonResult = false
        var showHelp = false
        var gatewayMode = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]

            switch token {
            case "--skill-dir":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--skill-dir")
                }
                skillDirectoryPath = arguments[index]
            case "--session-id":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--session-id")
                }
                sessionId = arguments[index]
            case "--task-id":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--task-id")
                }
                taskId = arguments[index]
            case "--trace-id":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--trace-id")
                }
                traceId = arguments[index]
            case "--logs-root":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--logs-root")
                }
                logsRootPath = arguments[index]
            case "--safety-rules":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--safety-rules")
                }
                safetyRulesPath = arguments[index]
            case "--runtime-executable":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--runtime-executable")
                }
                runtimeExecutablePath = arguments[index]
            case "--working-dir":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--working-dir")
                }
                workingDirectoryPath = arguments[index]
            case "--timeout-seconds":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--timeout-seconds")
                }
                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw OpenClawCLIOptionError.invalidValue("--timeout-seconds", arguments[index])
                }
                timeoutSeconds = parsed
            case "--simulate-runtime-failure-step":
                index += 1
                guard index < arguments.count else {
                    throw OpenClawCLIOptionError.missingValue("--simulate-runtime-failure-step")
                }
                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw OpenClawCLIOptionError.invalidValue(
                        "--simulate-runtime-failure-step",
                        arguments[index]
                    )
                }
                simulateRuntimeFailureAtStepIndex = parsed
            case "--teacher-confirmed":
                teacherConfirmed = true
            case "--semantic-only":
                semanticOnly = true
            case "--json-result":
                jsonResult = true
            case "--gateway-mode":
                gatewayMode = true
            case "--help", "-h":
                showHelp = true
            default:
                throw OpenClawCLIOptionError.unknownFlag(token)
            }

            index += 1
        }

        if showHelp {
            return OpenClawCLIOptions(
                skillDirectoryPath: skillDirectoryPath ?? "scripts/skills/examples/generated/openstaff-task-session-20260307-a1-001",
                sessionId: sessionId,
                taskId: taskId,
                traceId: traceId,
                logsRootPath: logsRootPath,
                safetyRulesPath: safetyRulesPath,
                runtimeExecutablePath: runtimeExecutablePath,
                workingDirectoryPath: workingDirectoryPath,
                timeoutSeconds: timeoutSeconds,
                simulateRuntimeFailureAtStepIndex: simulateRuntimeFailureAtStepIndex,
                teacherConfirmed: teacherConfirmed,
                semanticOnly: semanticOnly,
                jsonResult: jsonResult,
                showHelp: true,
                gatewayMode: gatewayMode
            )
        }

        guard let skillDirectoryPath else {
            throw OpenClawCLIOptionError.missingRequired("--skill-dir")
        }

        return OpenClawCLIOptions(
            skillDirectoryPath: skillDirectoryPath,
            sessionId: sessionId,
            taskId: taskId,
            traceId: traceId,
            logsRootPath: logsRootPath,
            safetyRulesPath: safetyRulesPath,
            runtimeExecutablePath: runtimeExecutablePath,
            workingDirectoryPath: workingDirectoryPath,
            timeoutSeconds: timeoutSeconds,
            simulateRuntimeFailureAtStepIndex: simulateRuntimeFailureAtStepIndex,
            teacherConfirmed: teacherConfirmed,
            semanticOnly: semanticOnly,
            jsonResult: jsonResult,
            showHelp: false,
            gatewayMode: gatewayMode
        )
    }

    func gatewayArguments(
        skillDirectoryURL: URL,
        traceId: String,
        sessionId: String,
        taskId: String?
    ) -> [String] {
        var arguments = [
            "--gateway-mode",
            "--semantic-only",
            "--skill-dir",
            skillDirectoryURL.path,
            "--trace-id",
            traceId,
            "--session-id",
            sessionId,
            "--json-result",
        ]
        if let taskId {
            arguments += ["--task-id", taskId]
        }
        if let safetyRulesPath {
            arguments += ["--safety-rules", safetyRulesPath]
        }
        if teacherConfirmed {
            arguments.append("--teacher-confirmed")
        }
        if let simulateRuntimeFailureAtStepIndex {
            arguments += ["--simulate-runtime-failure-step", String(simulateRuntimeFailureAtStepIndex)]
        }
        return arguments
    }

    private func resolve(path: String) -> URL {
        let currentDirectory = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).standardizedFileURL
    }
}

private enum OpenClawCLIOptionError: LocalizedError {
    case missingRequired(String)
    case missingValue(String)
    case invalidValue(String, String)
    case unknownFlag(String)

    var errorDescription: String? {
        switch self {
        case .missingRequired(let flag):
            return "Missing required flag \(flag)."
        case .missingValue(let flag):
            return "Missing value for flag \(flag)."
        case .invalidValue(let flag, let value):
            return "Invalid value '\(value)' for flag \(flag)."
        case .unknownFlag(let flag):
            return "Unknown flag \(flag)."
        }
    }
}

private extension OpenStaffOpenClawCLI {
    static func gatewayStatus(for preflight: SkillPreflightReport) -> OpenClawExecutionStatus {
        if preflight.issues.contains(where: { $0.code == .coordinateExecutionDisabled }) {
            return .failed
        }
        return .blocked
    }

    static func gatewayErrorCode(for preflight: SkillPreflightReport) -> String {
        if preflight.issues.contains(where: { $0.code == .coordinateExecutionDisabled }) {
            return OpenClawExecutionErrorCode.coordinateExecutionDisabled.rawValue
        }
        return OpenClawExecutionErrorCode.skillPreflightFailed.rawValue
    }
}

private struct OpenClawSkillDescriptorLoader {
    private let decoder = JSONDecoder()

    func load(from skillDirectoryURL: URL) throws -> OpenClawSkillDescriptor {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: skillDirectoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw OpenClawSkillDescriptorLoaderError.skillDirectoryNotFound(skillDirectoryURL.path)
        }

        let payloadURL = skillDirectoryURL.appendingPathComponent("openstaff-skill.json", isDirectory: false)
        let data: Data
        do {
            data = try Data(contentsOf: payloadURL)
        } catch {
            throw OpenClawSkillDescriptorLoaderError.readFailed(payloadURL.path, underlying: error)
        }

        do {
            return try decoder.decode(OpenClawSkillDescriptor.self, from: data)
        } catch {
            throw OpenClawSkillDescriptorLoaderError.decodeFailed(payloadURL.path, underlying: error)
        }
    }
}

private enum OpenClawSkillDescriptorLoaderError: LocalizedError {
    case skillDirectoryNotFound(String)
    case readFailed(String, underlying: Error)
    case decodeFailed(String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .skillDirectoryNotFound(let path):
            return "Skill directory not found: \(path)"
        case .readFailed(let path, let underlying):
            return "Failed to read skill payload \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode skill payload \(path): \(underlying.localizedDescription)"
        }
    }
}

private struct OpenClawSkillDescriptor: Decodable {
    let skillName: String
    let taskId: String
    let sessionId: String
    let mappedOutput: OpenClawSkillMappedOutput
}

private struct OpenClawSkillMappedOutput: Decodable {
    let executionPlan: OpenClawSkillExecutionPlan
}

private struct OpenClawSkillExecutionPlan: Decodable {
    let steps: [OpenClawSkillExecutionStep]
}

private struct OpenClawSkillExecutionStep: Decodable {
    let stepId: String
    let actionType: String
    let instruction: String
    let target: String
}
