import Foundation

struct LoadedTaskChunks {
    let sourceFiles: [URL]
    let chunks: [TaskChunk]
}

struct TaskChunkLoader {
    private let fileManager: FileManager
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(
        sessionId: String,
        dateKey: String,
        taskChunkRootDirectory: URL
    ) throws -> LoadedTaskChunks {
        let dateDirectory = taskChunkRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dateDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TaskChunkLoaderError.missingDateDirectory(dateDirectory.path)
        }

        let files = try discoverTaskChunkFiles(sessionId: sessionId, in: dateDirectory)
        guard !files.isEmpty else {
            throw TaskChunkLoaderError.noTaskChunkFiles(sessionId: sessionId, dateDirectory: dateDirectory.path)
        }

        var chunks: [TaskChunk] = []
        for fileURL in files {
            do {
                let data = try Data(contentsOf: fileURL)
                let chunk = try decoder.decode(TaskChunk.self, from: data)
                guard chunk.sessionId == sessionId else {
                    throw TaskChunkLoaderError.sessionMismatch(
                        expected: sessionId,
                        actual: chunk.sessionId,
                        filePath: fileURL.path
                    )
                }
                chunks.append(chunk)
            } catch let error as TaskChunkLoaderError {
                throw error
            } catch {
                throw TaskChunkLoaderError.decodeChunkFailed(filePath: fileURL.path, underlying: error)
            }
        }

        return LoadedTaskChunks(sourceFiles: files, chunks: chunks)
    }

    private func discoverTaskChunkFiles(sessionId: String, in directory: URL) throws -> [URL] {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw TaskChunkLoaderError.listDirectoryFailed(directory.path, error)
        }

        let prefix = "task-\(sessionId)-"
        let candidates = files.compactMap { fileURL -> URL? in
            guard fileURL.pathExtension == "json" else {
                return nil
            }
            guard fileURL.lastPathComponent.hasPrefix(prefix) else {
                return nil
            }

            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else {
                return nil
            }

            return fileURL
        }

        return candidates.sorted { lhs, rhs in
            lhs.lastPathComponent < rhs.lastPathComponent
        }
    }
}

struct KnowledgeItemBuilder {
    private let nowProvider: () -> Date
    private let timestampFormatter: ISO8601DateFormatter
    private let summaryGenerator: KnowledgeSummaryGenerator

    init(
        nowProvider: @escaping () -> Date = Date.init,
        summaryGenerator: KnowledgeSummaryGenerator = KnowledgeSummaryGenerator()
    ) {
        self.nowProvider = nowProvider
        self.summaryGenerator = summaryGenerator

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    func build(from chunk: TaskChunk) -> KnowledgeItem {
        let knowledgeItemId = "ki-\(chunk.taskId)"
        let goal = "在 \(chunk.primaryContext.appName) 中复现任务 \(chunk.taskId) 的操作流程"

        let steps = buildSteps(from: chunk)
        let summary = summaryGenerator.generate(from: chunk, steps: steps)
        let context = KnowledgeContext(
            appName: chunk.primaryContext.appName,
            appBundleId: chunk.primaryContext.appBundleId,
            windowTitle: chunk.primaryContext.windowTitle,
            windowId: chunk.primaryContext.windowId
        )

        let constraints: [KnowledgeConstraint] = [
            KnowledgeConstraint(
                type: .frontmostAppMustMatch,
                description: "执行前前台应用必须是 \(chunk.primaryContext.appBundleId)。"
            ),
            KnowledgeConstraint(
                type: .manualConfirmationRequired,
                description: "执行该知识条目时，需要老师确认后再执行。"
            ),
            KnowledgeConstraint(
                type: .coordinateTargetMayDrift,
                description: "坐标点击目标可能随分辨率或界面变化漂移。"
            )
        ]

        let source = KnowledgeSource(
            taskChunkSchemaVersion: chunk.schemaVersion,
            startTimestamp: chunk.startTimestamp,
            endTimestamp: chunk.endTimestamp,
            eventCount: chunk.eventCount,
            boundaryReason: chunk.boundaryReason
        )

        return KnowledgeItem(
            knowledgeItemId: knowledgeItemId,
            taskId: chunk.taskId,
            sessionId: chunk.sessionId,
            goal: goal,
            summary: summary,
            steps: steps,
            context: context,
            constraints: constraints,
            source: source,
            createdAt: timestampFormatter.string(from: nowProvider())
        )
    }

    private func buildSteps(from chunk: TaskChunk) -> [KnowledgeStep] {
        if chunk.eventIds.isEmpty {
            return [
                KnowledgeStep(
                    stepId: "step-001",
                    instruction: "该任务片段未包含可回放事件，请老师补充操作示例。",
                    sourceEventIds: []
                )
            ]
        }

        return chunk.eventIds.enumerated().map { index, eventId in
            let stepId = String(format: "step-%03d", index + 1)
            return KnowledgeStep(
                stepId: stepId,
                instruction: "执行第 \(index + 1) 步点击操作（源事件 \(eventId)）。",
                sourceEventIds: [eventId]
            )
        }
    }
}

struct KnowledgeItemWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    @discardableResult
    func write(
        items: [KnowledgeItem],
        dateKey: String,
        knowledgeRootDirectory: URL
    ) throws -> [URL] {
        let outputDirectory = knowledgeRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw KnowledgeItemWriterError.createOutputDirectoryFailed(outputDirectory.path, error)
        }

        var outputFiles: [URL] = []
        for item in items {
            let outputURL = outputDirectory.appendingPathComponent("\(item.taskId).json", isDirectory: false)
            do {
                let data = try encoder.encode(item)
                try data.write(to: outputURL, options: [.atomic])
                outputFiles.append(outputURL)
            } catch {
                throw KnowledgeItemWriterError.writeItemFailed(outputURL.path, error)
            }
        }

        return outputFiles
    }
}

enum TaskChunkLoaderError: LocalizedError {
    case missingDateDirectory(String)
    case noTaskChunkFiles(sessionId: String, dateDirectory: String)
    case listDirectoryFailed(String, Error)
    case decodeChunkFailed(filePath: String, underlying: Error)
    case sessionMismatch(expected: String, actual: String, filePath: String)

    var errorDescription: String? {
        switch self {
        case .missingDateDirectory(let path):
            return "Task chunk date directory not found: \(path)"
        case .noTaskChunkFiles(let sessionId, let dateDirectory):
            return "No task chunk files found for session \(sessionId) in \(dateDirectory)."
        case .listDirectoryFailed(let path, let error):
            return "Failed to list task chunk directory \(path): \(error.localizedDescription)"
        case .decodeChunkFailed(let filePath, let underlying):
            return "Failed to decode task chunk \(filePath): \(underlying.localizedDescription)"
        case .sessionMismatch(let expected, let actual, let filePath):
            return "Session mismatch in task chunk \(filePath). expected=\(expected), actual=\(actual)."
        }
    }
}

enum KnowledgeItemWriterError: LocalizedError {
    case createOutputDirectoryFailed(String, Error)
    case writeItemFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .createOutputDirectoryFailed(let path, let error):
            return "Failed to create knowledge output directory \(path): \(error.localizedDescription)"
        case .writeItemFailed(let path, let error):
            return "Failed to write knowledge item file \(path): \(error.localizedDescription)"
        }
    }
}
