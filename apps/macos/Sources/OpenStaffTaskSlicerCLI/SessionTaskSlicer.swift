import Foundation

struct LoadedSessionEvents {
    let sourceFiles: [URL]
    let events: [RawEvent]
}

struct SessionRawEventLoader {
    private let decoder = JSONDecoder()
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(
        sessionId: String,
        dateKey: String,
        rawRootDirectory: URL
    ) throws -> LoadedSessionEvents {
        let dateDirectory = rawRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dateDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SessionRawEventLoaderError.missingDateDirectory(dateDirectory.path)
        }

        let sourceFiles = try discoverSessionFiles(sessionId: sessionId, in: dateDirectory)
        guard !sourceFiles.isEmpty else {
            throw SessionRawEventLoaderError.noSessionFiles(sessionId: sessionId, dateDirectory: dateDirectory.path)
        }

        var events: [RawEvent] = []
        for fileURL in sourceFiles {
            let content: String
            do {
                content = try String(contentsOf: fileURL, encoding: .utf8)
            } catch {
                throw SessionRawEventLoaderError.readFileFailed(fileURL.path, error)
            }

            let lines = content.split(whereSeparator: \.isNewline)
            for (lineIndex, rawLine) in lines.enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty {
                    continue
                }

                do {
                    let event = try decoder.decode(RawEvent.self, from: Data(line.utf8))
                    guard event.sessionId == sessionId else {
                        throw SessionRawEventLoaderError.sessionMismatch(
                            expected: sessionId,
                            actual: event.sessionId,
                            filePath: fileURL.path,
                            lineNumber: lineIndex + 1
                        )
                    }
                    events.append(event)
                } catch let error as SessionRawEventLoaderError {
                    throw error
                } catch {
                    throw SessionRawEventLoaderError.decodeLineFailed(
                        filePath: fileURL.path,
                        lineNumber: lineIndex + 1,
                        underlying: error
                    )
                }
            }
        }

        return LoadedSessionEvents(sourceFiles: sourceFiles, events: events)
    }

    private func discoverSessionFiles(sessionId: String, in directory: URL) throws -> [URL] {
        let files: [URL]
        do {
            files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            throw SessionRawEventLoaderError.listDirectoryFailed(directory.path, error)
        }

        let segments: [(index: Int, url: URL)] = files.compactMap { fileURL in
            guard let index = segmentIndex(for: fileURL.lastPathComponent, sessionId: sessionId) else {
                return nil
            }

            var isRegularFile: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isRegularFile), !isRegularFile.boolValue else {
                return nil
            }

            return (index: index, url: fileURL)
        }

        return segments.sorted { lhs, rhs in
            lhs.index < rhs.index
        }.map(\.url)
    }

    private func segmentIndex(for filename: String, sessionId: String) -> Int? {
        let baseName = "\(sessionId).jsonl"
        if filename == baseName {
            return 0
        }

        let prefix = "\(sessionId)-r"
        let suffix = ".jsonl"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }

        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        let value = filename[start..<end]
        return Int(value)
    }
}

struct SessionTaskSlicer {
    private let policy: TaskSlicingPolicy
    private let parserWithFractional: ISO8601DateFormatter
    private let parser: ISO8601DateFormatter

    init(policy: TaskSlicingPolicy = TaskSlicingPolicy()) {
        self.policy = policy

        let parserWithFractional = ISO8601DateFormatter()
        parserWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.parserWithFractional = parserWithFractional

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        self.parser = parser
    }

    func slice(events: [RawEvent], sessionId: String) throws -> [TaskChunk] {
        guard !events.isEmpty else {
            return []
        }

        var chunks: [TaskChunk] = []
        var currentEvents: [RawEvent] = [events[0]]
        var chunkIndex = 1

        for eventIndex in 1..<events.count {
            let previous = events[eventIndex - 1]
            let current = events[eventIndex]

            if let boundaryReason = try detectBoundary(previous: previous, current: current) {
                chunks.append(
                    try buildChunk(
                        events: currentEvents,
                        sessionId: sessionId,
                        chunkIndex: chunkIndex,
                        boundaryReason: boundaryReason
                    )
                )
                chunkIndex += 1
                currentEvents = [current]
            } else {
                currentEvents.append(current)
            }
        }

        chunks.append(
            try buildChunk(
                events: currentEvents,
                sessionId: sessionId,
                chunkIndex: chunkIndex,
                boundaryReason: .sessionEnd
            )
        )

        return chunks
    }

    private func detectBoundary(previous: RawEvent, current: RawEvent) throws -> TaskBoundaryReason? {
        let previousDate = try parseTimestamp(previous.timestamp)
        let currentDate = try parseTimestamp(current.timestamp)

        if currentDate.timeIntervalSince(previousDate) > policy.idleGapSeconds {
            return .idleGap
        }

        if policy.splitOnContextSwitch, didContextSwitch(previous.contextSnapshot, current.contextSnapshot) {
            return .contextSwitch
        }

        return nil
    }

    private func didContextSwitch(_ lhs: ContextSnapshot, _ rhs: ContextSnapshot) -> Bool {
        if lhs.appBundleId != rhs.appBundleId {
            return true
        }

        if lhs.windowId != rhs.windowId {
            if lhs.windowId != nil || rhs.windowId != nil {
                return true
            }
        }

        if lhs.windowId == nil, rhs.windowId == nil, lhs.windowTitle != rhs.windowTitle {
            return true
        }

        return false
    }

    private func parseTimestamp(_ raw: String) throws -> Date {
        if let parsed = parserWithFractional.date(from: raw) {
            return parsed
        }
        if let parsed = parser.date(from: raw) {
            return parsed
        }

        throw SessionTaskSlicerError.invalidTimestamp(raw)
    }

    private func buildChunk(
        events: [RawEvent],
        sessionId: String,
        chunkIndex: Int,
        boundaryReason: TaskBoundaryReason
    ) throws -> TaskChunk {
        guard let first = events.first, let last = events.last else {
            throw SessionTaskSlicerError.emptyChunk
        }

        for event in events where event.sessionId != sessionId {
            throw SessionTaskSlicerError.sessionMismatch(expected: sessionId, actual: event.sessionId, eventId: event.eventId)
        }

        let paddedIndex = String(format: "%03d", chunkIndex)
        let taskId = "task-\(sessionId)-\(paddedIndex)"

        return TaskChunk(
            taskId: taskId,
            sessionId: sessionId,
            startTimestamp: first.timestamp,
            endTimestamp: last.timestamp,
            eventIds: events.map(\.eventId),
            eventCount: events.count,
            primaryContext: first.contextSnapshot,
            boundaryReason: boundaryReason
        )
    }
}

struct TaskChunkWriter {
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
        chunks: [TaskChunk],
        dateKey: String,
        knowledgeRootDirectory: URL
    ) throws -> [URL] {
        let outputDirectory = knowledgeRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw TaskChunkWriterError.createOutputDirectoryFailed(outputDirectory.path, error)
        }

        var outputFiles: [URL] = []
        for chunk in chunks {
            let outputURL = outputDirectory.appendingPathComponent("\(chunk.taskId).json", isDirectory: false)
            do {
                let data = try encoder.encode(chunk)
                try data.write(to: outputURL, options: [.atomic])
                outputFiles.append(outputURL)
            } catch {
                throw TaskChunkWriterError.writeChunkFailed(outputURL.path, error)
            }
        }

        return outputFiles
    }
}

enum SessionRawEventLoaderError: LocalizedError {
    case missingDateDirectory(String)
    case noSessionFiles(sessionId: String, dateDirectory: String)
    case listDirectoryFailed(String, Error)
    case readFileFailed(String, Error)
    case decodeLineFailed(filePath: String, lineNumber: Int, underlying: Error)
    case sessionMismatch(expected: String, actual: String, filePath: String, lineNumber: Int)

    var errorDescription: String? {
        switch self {
        case .missingDateDirectory(let path):
            return "Raw event date directory not found: \(path)"
        case .noSessionFiles(let sessionId, let dateDirectory):
            return "No raw event files found for session \(sessionId) in \(dateDirectory)."
        case .listDirectoryFailed(let path, let error):
            return "Failed to list raw event directory \(path): \(error.localizedDescription)"
        case .readFileFailed(let path, let error):
            return "Failed to read raw event file \(path): \(error.localizedDescription)"
        case .decodeLineFailed(let filePath, let lineNumber, let underlying):
            return "Failed to decode raw event at \(filePath):\(lineNumber): \(underlying.localizedDescription)"
        case .sessionMismatch(let expected, let actual, let filePath, let lineNumber):
            return "Session mismatch at \(filePath):\(lineNumber). expected=\(expected), actual=\(actual)."
        }
    }
}

enum SessionTaskSlicerError: LocalizedError {
    case invalidTimestamp(String)
    case emptyChunk
    case sessionMismatch(expected: String, actual: String, eventId: String)

    var errorDescription: String? {
        switch self {
        case .invalidTimestamp(let value):
            return "Invalid timestamp format in raw event: \(value)"
        case .emptyChunk:
            return "Internal error: generated empty task chunk."
        case .sessionMismatch(let expected, let actual, let eventId):
            return "Session mismatch in task chunk builder for event \(eventId). expected=\(expected), actual=\(actual)."
        }
    }
}

enum TaskChunkWriterError: LocalizedError {
    case createOutputDirectoryFailed(String, Error)
    case writeChunkFailed(String, Error)

    var errorDescription: String? {
        switch self {
        case .createOutputDirectoryFailed(let path, let error):
            return "Failed to create knowledge output directory \(path): \(error.localizedDescription)"
        case .writeChunkFailed(let path, let error):
            return "Failed to write task chunk file \(path): \(error.localizedDescription)"
        }
    }
}
