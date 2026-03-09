import Foundation

struct IntegratedTeachingWorkflowResult {
    let sessionId: String
    let dateKey: String
    let rawEventCount: Int
    let taskChunkCount: Int
    let knowledgeItemCount: Int
}

final class IntegratedModeWorkflowRunner {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func buildKnowledgeFromCapturedSession(sessionId: String) throws -> IntegratedTeachingWorkflowResult {
        let dateKey = try resolveDateKeyForCapturedSession(sessionId: sessionId)

        let rawLoader = SessionRawEventLoader(fileManager: fileManager)
        let loaded = try rawLoader.load(
            sessionId: sessionId,
            dateKey: dateKey,
            rawRootDirectory: OpenStaffWorkspacePaths.rawEventsDirectory
        )

        guard !loaded.events.isEmpty else {
            throw IntegratedWorkflowError.emptyCapturedEvents(sessionId: sessionId, dateKey: dateKey)
        }

        let slicer = SessionTaskSlicer()
        let chunks = try slicer.slice(events: loaded.events, sessionId: sessionId)

        let chunkWriter = TaskChunkWriter(fileManager: fileManager)
        _ = try chunkWriter.write(
            chunks: chunks,
            dateKey: dateKey,
            taskChunkRootDirectory: OpenStaffWorkspacePaths.taskChunksDirectory
        )

        let knowledgeBuilder = KnowledgeItemBuilder()
        let knowledgeItems = chunks.map { knowledgeBuilder.build(from: $0) }
        let knowledgeWriter = KnowledgeItemWriter(fileManager: fileManager)
        _ = try knowledgeWriter.write(
            items: knowledgeItems,
            dateKey: dateKey,
            knowledgeRootDirectory: OpenStaffWorkspacePaths.knowledgeDirectory
        )

        return IntegratedTeachingWorkflowResult(
            sessionId: sessionId,
            dateKey: dateKey,
            rawEventCount: loaded.events.count,
            taskChunkCount: chunks.count,
            knowledgeItemCount: knowledgeItems.count
        )
    }

    func runAssistLoop(sessionId: String, emergencyStopActive: Bool) throws -> AssistLoopRunResult {
        let knowledgeItems = try loadKnowledgeItems(preferredSessionId: sessionId)
        guard let primaryItem = knowledgeItems.first else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        let stateMachine = ModeStateMachine(initialMode: .teaching, logger: InMemoryOrchestratorStateLogger())
        let orchestrator = AssistModeLoopOrchestrator(
            modeStateMachine: stateMachine,
            predictor: RuleBasedAssistNextActionPredictor(),
            confirmationPrompter: AssistPopupConfirmationPrompter(forcedDecision: true),
            actionExecutor: AssistActionExecutor(),
            logWriter: AssistLoopLogWriter(logsRootDirectory: OpenStaffWorkspacePaths.logsDirectory)
        )

        let traceId = "trace-gui-assist-\(UUID().uuidString.lowercased())"
        let timestamp = currentTimestamp()
        let input = AssistLoopInput(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            timestamp: timestamp,
            teacherConfirmed: true,
            emergencyStopActive: emergencyStopActive,
            completedStepCount: 0,
            currentAppName: primaryItem.context.appName,
            currentAppBundleId: primaryItem.context.appBundleId,
            knowledgeItems: knowledgeItems
        )
        let executionContext = AssistExecutionContext(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            dryRun: true,
            emergencyStopActive: emergencyStopActive
        )

        return try orchestrator.run(input: input, executionContext: executionContext)
    }

    func runStudentLoop(
        sessionId: String,
        preferredGoal: String?,
        emergencyStopActive: Bool
    ) throws -> StudentLoopRunResult {
        let knowledgeItems = try loadKnowledgeItems(preferredSessionId: sessionId)
        guard let primaryItem = knowledgeItems.first else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        let stateMachine = ModeStateMachine(initialMode: .assist, logger: InMemoryOrchestratorStateLogger())
        let orchestrator = StudentModeLoopOrchestrator(
            modeStateMachine: stateMachine,
            planner: RuleBasedStudentTaskPlanner(),
            skillExecutor: StudentSkillExecutor(),
            logWriter: StudentLoopLogWriter(logsRootDirectory: OpenStaffWorkspacePaths.logsDirectory),
            reportWriter: StudentReviewReportWriter(reportsRootDirectory: OpenStaffWorkspacePaths.reportsDirectory)
        )

        let goal = resolveGoal(preferredGoal: preferredGoal, fallbackItem: primaryItem)
        let traceId = "trace-gui-student-\(UUID().uuidString.lowercased())"
        let timestamp = currentTimestamp()

        let input = StudentLoopInput(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            timestamp: timestamp,
            teacherConfirmed: true,
            emergencyStopActive: emergencyStopActive,
            goal: goal,
            preferredKnowledgeItemId: primaryItem.knowledgeItemId,
            pendingAssistSuggestion: false,
            knowledgeItems: knowledgeItems
        )
        let executionContext = StudentExecutionContext(
            traceId: traceId,
            sessionId: sessionId,
            taskId: primaryItem.taskId,
            dryRun: true,
            emergencyStopActive: emergencyStopActive
        )

        return try orchestrator.run(input: input, executionContext: executionContext)
    }

    private func resolveGoal(preferredGoal: String?, fallbackItem: KnowledgeItem) -> String {
        if let preferredGoal {
            let normalized = preferredGoal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }
        return fallbackItem.goal
    }

    private func resolveDateKeyForCapturedSession(sessionId: String) throws -> String {
        let rawRoot = OpenStaffWorkspacePaths.rawEventsDirectory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rawRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IntegratedWorkflowError.rawEventDirectoryMissing(rawRoot.path)
        }

        let dateDirectories = try fileManager.contentsOfDirectory(
            at: rawRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent > rhs.lastPathComponent
            }

        for dateDirectory in dateDirectories {
            if try containsSessionFile(in: dateDirectory, sessionId: sessionId) {
                return dateDirectory.lastPathComponent
            }
        }

        throw IntegratedWorkflowError.rawEventsForSessionNotFound(sessionId: sessionId)
    }

    private func containsSessionFile(in dateDirectory: URL, sessionId: String) throws -> Bool {
        let files = try fileManager.contentsOfDirectory(
            at: dateDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let baseName = "\(sessionId).jsonl"
        let rotatedPrefix = "\(sessionId)-r"

        return files.contains { fileURL in
            guard fileURL.pathExtension == "jsonl" else {
                return false
            }
            let filename = fileURL.lastPathComponent
            if filename == baseName {
                return true
            }
            return filename.hasPrefix(rotatedPrefix) && filename.hasSuffix(".jsonl")
        }
    }

    private func loadKnowledgeItems(preferredSessionId: String?) throws -> [KnowledgeItem] {
        let root = OpenStaffWorkspacePaths.knowledgeDirectory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw IntegratedWorkflowError.knowledgeDirectoryMissing(root.path)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        let decoder = JSONDecoder()
        var allItems: [KnowledgeItem] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else {
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                continue
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                continue
            }

            if let item = try? decoder.decode(KnowledgeItem.self, from: data) {
                allItems.append(item)
            }
        }

        guard !allItems.isEmpty else {
            throw IntegratedWorkflowError.knowledgeNotFound
        }

        if let preferredSessionId {
            let matched = allItems.filter { $0.sessionId == preferredSessionId }
            if !matched.isEmpty {
                return matched.sorted { lhs, rhs in
                    lhs.createdAt > rhs.createdAt
                }
            }
        }

        return allItems.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

enum IntegratedWorkflowError: LocalizedError {
    case rawEventDirectoryMissing(String)
    case rawEventsForSessionNotFound(sessionId: String)
    case emptyCapturedEvents(sessionId: String, dateKey: String)
    case knowledgeDirectoryMissing(String)
    case knowledgeNotFound

    var errorDescription: String? {
        switch self {
        case .rawEventDirectoryMissing(let path):
            return "教学模式原始事件目录不存在：\(path)"
        case .rawEventsForSessionNotFound(let sessionId):
            return "未找到会话 \(sessionId) 的采集事件文件。"
        case .emptyCapturedEvents(let sessionId, let dateKey):
            return "会话 \(sessionId) 在 \(dateKey) 下没有可切片事件。"
        case .knowledgeDirectoryMissing(let path):
            return "知识目录不存在：\(path)"
        case .knowledgeNotFound:
            return "未找到可用于辅助/学生模式的知识条目。"
        }
    }
}
