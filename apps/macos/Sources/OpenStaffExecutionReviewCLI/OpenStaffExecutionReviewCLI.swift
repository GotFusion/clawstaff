import Foundation

@main
struct OpenStaffExecutionReviewCLI {
    static func main() {
        do {
            let options = try ExecutionReviewCLIOptions.parse(arguments: CommandLine.arguments)

            if options.showHelp {
                printHelp()
                return
            }

            let scenario = try ScenarioLoader.load(from: options.scenarioURL)
            let workspace = try ReviewScenarioWorkspaceMaterializer().materialize(scenario: scenario)
            defer { try? FileManager.default.removeItem(at: workspace.workspaceRoot) }

            let store = ExecutionReviewStore(
                logsRootDirectory: workspace.logsRoot,
                feedbackRootDirectory: workspace.feedbackRoot,
                reportsRootDirectory: workspace.reportsRoot,
                knowledgeRootDirectory: workspace.knowledgeRoot,
                preferencesRootDirectory: workspace.preferencesRoot,
                skillRoots: [
                    ExecutionReviewSkillRoot(scopeId: "pending", directory: workspace.pendingSkillsRoot)
                ]
            )

            let snapshot = store.loadExecutionSnapshot(limit: 20)
            guard let selectedLog = snapshot.logs.first(where: { log in
                log.traceId == scenario.traceId && log.status != StudentLoopStatusCode.executionStarted.rawValue
            }) ?? snapshot.logs.first else {
                throw ExecutionReviewCLIError.noLogEntries
            }

            let detail = store.loadDetail(for: selectedLog)
            let output = ExecutionReviewCLIOutput(
                schemaVersion: "openstaff.execution-review-cli.result.v0",
                scenarioId: scenario.scenarioId,
                selectedLogId: selectedLog.id,
                selectedLogStatus: selectedLog.status,
                selectedLogMessage: selectedLog.message,
                topSuggestion: detail.reviewSuggestions.first.map(ExecutionReviewSuggestionOutput.init),
                suggestions: detail.reviewSuggestions.map(ExecutionReviewSuggestionOutput.init),
                decision: detail.reviewPreferenceDecision.map(ExecutionReviewSuggestionDecisionOutput.init),
                comparisonRowCount: detail.comparisonRows.count,
                hasLocatorRepairAction: detail.locatorRepairAction != nil,
                hasReteachAction: detail.reteachAction != nil
            )

            printSummary(output)

            if options.printJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(output)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            }
        } catch {
            print("Execution review CLI failed: \(error.localizedDescription)")
            Foundation.exit(1)
        }
    }

    static func printHelp() {
        print("""
        OpenStaffExecutionReviewCLI

        Usage:
          swift run --package-path apps/macos OpenStaffExecutionReviewCLI --scenario /tmp/review-scenario.json --json

        Flags:
          --scenario <path>   Review scenario JSON path.
          --json              Print structured JSON output.
          --help              Show this help message.
        """)
    }

    fileprivate static func printSummary(_ output: ExecutionReviewCLIOutput) {
        print("Execution review evaluated. scenarioId=\(output.scenarioId)")
        print("selectedLogId=\(output.selectedLogId)")
        print("selectedLogStatus=\(output.selectedLogStatus)")
        if let topSuggestion = output.topSuggestion {
            print("topSuggestion=\(topSuggestion.action)")
            print("appliedRuleIds=\(topSuggestion.appliedRuleIds.joined(separator: ","))")
            if let suggestedNote = topSuggestion.suggestedNote {
                print("suggestedNote=\(suggestedNote)")
            }
        }
        if let decision = output.decision {
            print("profileVersion=\(decision.profileVersion)")
            print("decisionRuleIds=\(decision.appliedRuleIds.joined(separator: ","))")
        }
    }
}

private struct ExecutionReviewCLIOptions {
    let scenarioPath: String
    let printJSON: Bool
    let showHelp: Bool

    var scenarioURL: URL {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return URL(fileURLWithPath: scenarioPath, relativeTo: current).standardizedFileURL
    }

    static func parse(arguments: [String]) throws -> Self {
        var scenarioPath: String?
        var printJSON = false
        var showHelp = false

        var index = 1
        while index < arguments.count {
            let token = arguments[index]
            switch token {
            case "--scenario":
                index += 1
                guard index < arguments.count else {
                    throw ExecutionReviewCLIError.missingValue("--scenario")
                }
                scenarioPath = arguments[index]
            case "--json":
                printJSON = true
            case "--help", "-h":
                showHelp = true
            default:
                throw ExecutionReviewCLIError.unknownFlag(token)
            }
            index += 1
        }

        if !showHelp, scenarioPath == nil {
            throw ExecutionReviewCLIError.missingValue("--scenario")
        }

        return Self(
            scenarioPath: scenarioPath ?? "",
            printJSON: printJSON,
            showHelp: showHelp
        )
    }
}

private enum ExecutionReviewCLIError: LocalizedError {
    case missingValue(String)
    case unknownFlag(String)
    case noLogEntries
    case invalidScenario(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(flag):
            return "Missing value for \(flag)."
        case let .unknownFlag(flag):
            return "Unknown flag: \(flag)."
        case .noLogEntries:
            return "Scenario did not produce any reviewable log entries."
        case let .invalidScenario(reason):
            return "Invalid review scenario: \(reason)"
        }
    }
}

private struct ExecutionReviewCLIOutput: Codable {
    let schemaVersion: String
    let scenarioId: String
    let selectedLogId: String
    let selectedLogStatus: String
    let selectedLogMessage: String
    let topSuggestion: ExecutionReviewSuggestionOutput?
    let suggestions: [ExecutionReviewSuggestionOutput]
    let decision: ExecutionReviewSuggestionDecisionOutput?
    let comparisonRowCount: Int
    let hasLocatorRepairAction: Bool
    let hasReteachAction: Bool
}

private struct ExecutionReviewSuggestionOutput: Codable {
    let action: String
    let summary: String
    let suggestedNote: String?
    let appliedRuleIds: [String]
    let priority: Double

    init(_ suggestion: ExecutionReviewSuggestion) {
        self.action = suggestion.action.rawValue
        self.summary = suggestion.summary
        self.suggestedNote = suggestion.suggestedNote
        self.appliedRuleIds = suggestion.appliedRuleIds
        self.priority = suggestion.priority
    }
}

private struct ExecutionReviewSuggestionDecisionOutput: Codable {
    let profileVersion: String
    let appliedRuleIds: [String]
    let summary: String

    init(_ decision: ExecutionReviewSuggestionDecision) {
        self.profileVersion = decision.profileVersion
        self.appliedRuleIds = decision.appliedRuleIds
        self.summary = decision.summary
    }
}

private enum ScenarioLoader {
    static func load(from url: URL) throws -> ExecutionReviewScenario {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExecutionReviewScenario.self, from: data)
    }
}

private struct ExecutionReviewScenario: Codable {
    let scenarioId: String
    let traceId: String
    let sessionId: String
    let taskId: String
    let timestamp: String
    let goal: String
    let summary: String
    let appName: String
    let appBundleId: String
    let windowTitle: String
    let taskFamily: String?
    let skillFamily: String?
    let repairVersion: Int
    let teacherSteps: [ExecutionReviewScenarioStep]
    let skillSteps: [ExecutionReviewScenarioStep]
    let failedLog: ExecutionReviewScenarioLog
    let preferenceSnapshot: PreferenceProfileSnapshot?
}

private struct ExecutionReviewScenarioStep: Codable {
    let stepId: String
    let instruction: String
    let elementTitle: String?
    let includeSemanticTarget: Bool
}

private struct ExecutionReviewScenarioLog: Codable {
    let status: String
    let errorCode: String?
    let message: String
}

private struct MaterializedReviewWorkspace {
    let workspaceRoot: URL
    let logsRoot: URL
    let feedbackRoot: URL
    let reportsRoot: URL
    let knowledgeRoot: URL
    let preferencesRoot: URL?
    let pendingSkillsRoot: URL
}

private struct ReviewScenarioWorkspaceMaterializer {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder.sorted

    func materialize(scenario: ExecutionReviewScenario) throws -> MaterializedReviewWorkspace {
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("openstaff-review-cli-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        let logsRoot = workspaceRoot.appendingPathComponent("data/logs", isDirectory: true)
        let feedbackRoot = workspaceRoot.appendingPathComponent("data/feedback", isDirectory: true)
        let reportsRoot = workspaceRoot.appendingPathComponent("data/reports", isDirectory: true)
        let knowledgeRoot = workspaceRoot.appendingPathComponent("data/knowledge", isDirectory: true)
        let pendingSkillsRoot = workspaceRoot.appendingPathComponent("data/skills/pending", isDirectory: true)
        let preferencesRoot = workspaceRoot.appendingPathComponent("data/preferences", isDirectory: true)

        try fileManager.createDirectory(at: logsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: feedbackRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: reportsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: knowledgeRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: pendingSkillsRoot, withIntermediateDirectories: true)
        if scenario.preferenceSnapshot != nil {
            try fileManager.createDirectory(at: preferencesRoot, withIntermediateDirectories: true)
        }

        let knowledgeItem = buildKnowledgeItem(from: scenario)
        try encoder.encode(knowledgeItem).write(
            to: knowledgeRoot.appendingPathComponent("\(knowledgeItem.knowledgeItemId).json", isDirectory: false)
        )

        let skillDirectory = pendingSkillsRoot.appendingPathComponent("skill-\(scenario.scenarioId)", isDirectory: true)
        try fileManager.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let skillPayload = buildSkillPayload(from: scenario, knowledgeItemId: knowledgeItem.knowledgeItemId)
        try encoder.encode(skillPayload).write(
            to: skillDirectory.appendingPathComponent("openstaff-skill.json", isDirectory: false)
        )

        let logDirectory = logsRoot.appendingPathComponent(String(scenario.timestamp.prefix(10)), isDirectory: true)
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let logFile = logDirectory.appendingPathComponent("\(scenario.sessionId)-student.log", isDirectory: false)
        let entries = buildLogEntries(from: scenario, skillDirectory: skillDirectory, knowledgeItemId: knowledgeItem.knowledgeItemId)
        let logContent = try entries
            .map { try encoder.encode($0) }
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n") + "\n"
        try logContent.write(to: logFile, atomically: true, encoding: .utf8)

        if let snapshot = scenario.preferenceSnapshot {
            let store = PreferenceMemoryStore(preferencesRootDirectory: preferencesRoot)
            try store.storeProfileSnapshot(snapshot, actor: "execution-review-cli")
        }

        return MaterializedReviewWorkspace(
            workspaceRoot: workspaceRoot,
            logsRoot: logsRoot,
            feedbackRoot: feedbackRoot,
            reportsRoot: reportsRoot,
            knowledgeRoot: knowledgeRoot,
            preferencesRoot: scenario.preferenceSnapshot == nil ? nil : preferencesRoot,
            pendingSkillsRoot: pendingSkillsRoot
        )
    }

    private func buildKnowledgeItem(from scenario: ExecutionReviewScenario) -> KnowledgeItem {
        KnowledgeItem(
            knowledgeItemId: "knowledge-\(scenario.scenarioId)",
            taskId: scenario.taskId,
            sessionId: scenario.sessionId,
            goal: scenario.goal,
            summary: scenario.summary,
            steps: scenario.teacherSteps.enumerated().map { index, step in
                KnowledgeStep(
                    stepId: step.stepId,
                    instruction: step.instruction,
                    sourceEventIds: ["evt-teacher-\(index + 1)"]
                )
            },
            context: KnowledgeContext(
                appName: scenario.appName,
                appBundleId: scenario.appBundleId,
                windowTitle: scenario.windowTitle,
                windowId: nil
            ),
            constraints: [],
            source: KnowledgeSource(
                taskChunkSchemaVersion: "task.chunk.v0",
                startTimestamp: scenario.timestamp,
                endTimestamp: scenario.timestamp,
                eventCount: scenario.teacherSteps.count,
                boundaryReason: .sessionEnd
            ),
            createdAt: scenario.timestamp
        )
    }

    private func buildSkillPayload(
        from scenario: ExecutionReviewScenario,
        knowledgeItemId: String
    ) -> SkillBundlePayload {
        let stepMappings = zip(scenario.skillSteps, scenario.teacherSteps).enumerated().map { index, pair in
            let skillStep = pair.0
            let teacherStep = pair.1
            let semanticTargets: [SkillBundleSemanticTarget]
            if skillStep.includeSemanticTarget {
                semanticTargets = [
                    SkillBundleSemanticTarget(
                        locatorType: .roleAndTitle,
                        appBundleId: scenario.appBundleId,
                        windowTitlePattern: "^\(NSRegularExpression.escapedPattern(for: scenario.windowTitle))$",
                        elementRole: "AXButton",
                        elementTitle: skillStep.elementTitle ?? "Action \(index + 1)",
                        confidence: 0.9,
                        source: "capture"
                    )
                ]
            } else {
                semanticTargets = []
            }

            return SkillBundleStepMapping(
                skillStepId: skillStep.stepId,
                knowledgeStepId: teacherStep.stepId,
                instruction: skillStep.instruction,
                sourceEventIds: ["evt-skill-\(index + 1)"],
                preferredLocatorType: semanticTargets.isEmpty ? nil : .roleAndTitle,
                coordinate: semanticTargets.isEmpty ? nil : SkillBundleCoordinate(
                    x: Double(220 + (index * 20)),
                    y: Double(120 + (index * 24)),
                    coordinateSpace: "screen"
                ),
                semanticTargets: semanticTargets
            )
        }

        return SkillBundlePayload(
            schemaVersion: "openstaff.openclaw-skill.v1",
            skillName: "skill-\(scenario.scenarioId)",
            knowledgeItemId: knowledgeItemId,
            taskId: scenario.taskId,
            sessionId: scenario.sessionId,
            llmOutputAccepted: true,
            createdAt: scenario.timestamp,
            mappedOutput: SkillBundleMappedOutput(
                objective: scenario.goal,
                context: SkillBundleContext(
                    appName: scenario.appName,
                    appBundleId: scenario.appBundleId,
                    windowTitle: scenario.windowTitle
                ),
                executionPlan: SkillBundleExecutionPlan(
                    requiresTeacherConfirmation: false,
                    steps: scenario.skillSteps.enumerated().map { index, step in
                        SkillBundleExecutionStep(
                            stepId: step.stepId,
                            actionType: "click",
                            instruction: step.instruction,
                            target: step.elementTitle ?? "action-\(index + 1)",
                            sourceEventIds: ["evt-skill-\(index + 1)"]
                        )
                    },
                    completionCriteria: SkillBundleCompletionCriteria(
                        expectedStepCount: scenario.skillSteps.count,
                        requiredFrontmostAppBundleId: scenario.appBundleId
                    )
                ),
                safetyNotes: [],
                confidence: 0.92
            ),
            provenance: SkillBundleProvenance(
                skillBuild: SkillBundleSkillBuild(
                    repairVersion: scenario.repairVersion,
                    preferenceProfileVersion: scenario.preferenceSnapshot?.profileVersion,
                    appliedPreferenceRuleIds: scenario.preferenceSnapshot?.sourceRuleIds,
                    preferenceSummary: nil,
                    taskFamily: scenario.taskFamily,
                    skillFamily: scenario.skillFamily
                ),
                stepMappings: stepMappings
            )
        )
    }

    private func buildLogEntries(
        from scenario: ExecutionReviewScenario,
        skillDirectory: URL,
        knowledgeItemId: String
    ) -> [StudentLoopLogEntry] {
        var entries: [StudentLoopLogEntry] = [
            StudentLoopLogEntry(
                timestamp: scenario.timestamp,
                traceId: scenario.traceId,
                sessionId: scenario.sessionId,
                taskId: scenario.taskId,
                component: "student.skill.single-run",
                status: StudentLoopStatusCode.executionStarted.rawValue,
                message: "Manual UI run started for skill skill-\(scenario.scenarioId).",
                skillId: "skill-\(scenario.scenarioId)",
                skillName: "skill-\(scenario.scenarioId)",
                skillDirectoryPath: skillDirectory.path,
                sourceKnowledgeItemId: knowledgeItemId
            )
        ]

        for (index, step) in scenario.skillSteps.dropLast().enumerated() {
            entries.append(
                StudentLoopLogEntry(
                    timestamp: shiftedTimestamp(base: scenario.timestamp, seconds: index + 1),
                    traceId: scenario.traceId,
                    sessionId: scenario.sessionId,
                    taskId: scenario.taskId,
                    component: "student.skill.single-run",
                    status: StudentLoopStatusCode.executionCompleted.rawValue,
                    message: "已执行 click：\(step.instruction)",
                    skillId: "skill-\(scenario.scenarioId)-\(step.stepId)",
                    planStepId: "single-step-\(index + 1)",
                    skillName: "skill-\(scenario.scenarioId)",
                    skillDirectoryPath: skillDirectory.path,
                    sourceKnowledgeItemId: knowledgeItemId,
                    sourceStepId: step.stepId,
                    stepId: step.stepId
                )
            )
        }

        guard let failedStep = scenario.skillSteps.last else {
            return entries
        }

        let normalizedStatus = scenario.failedLog.status.lowercased()
        let statusCode: StudentLoopStatusCode
        switch normalizedStatus {
        case "completed", "succeeded":
            statusCode = .executionCompleted
        case "failed", "blocked":
            statusCode = .executionFailed
        default:
            statusCode = .executionFailed
        }

        entries.append(
            StudentLoopLogEntry(
                timestamp: shiftedTimestamp(base: scenario.timestamp, seconds: scenario.skillSteps.count + 1),
                traceId: scenario.traceId,
                sessionId: scenario.sessionId,
                taskId: scenario.taskId,
                component: "student.skill.single-run",
                status: statusCode.rawValue,
                errorCode: scenario.failedLog.errorCode,
                message: scenario.failedLog.message,
                skillId: "skill-\(scenario.scenarioId)-\(failedStep.stepId)",
                planStepId: "single-step-\(scenario.skillSteps.count)",
                skillName: "skill-\(scenario.scenarioId)",
                skillDirectoryPath: skillDirectory.path,
                sourceKnowledgeItemId: knowledgeItemId,
                sourceStepId: failedStep.stepId,
                stepId: failedStep.stepId
            )
        )

        return entries
    }

    private func shiftedTimestamp(base: String, seconds: Int) -> String {
        guard let date = ISO8601DateFormatter.flexible.date(from: base) else {
            return base
        }
        return ISO8601DateFormatter.flexible.string(from: date.addingTimeInterval(TimeInterval(seconds)))
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension ISO8601DateFormatter {
    static var flexible: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
