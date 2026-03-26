import Foundation

public protocol AssistLoopLogWriting {
    @discardableResult
    func write(_ entry: AssistLoopLogEntry) throws -> URL
}

public struct AssistLoopLogWriter: AssistLoopLogWriting {
    private let logsRootDirectory: URL
    private let fileWriter: StructuredLogFileWriter

    public init(
        logsRootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.logsRootDirectory = logsRootDirectory
        self.fileWriter = StructuredLogFileWriter(fileManager: fileManager)
    }

    @discardableResult
    public func write(_ entry: AssistLoopLogEntry) throws -> URL {
        try fileWriter.append(
            entry,
            timestamp: entry.timestamp,
            logsRootDirectory: logsRootDirectory,
            fileName: "\(entry.sessionId)-assist.log",
            artifactLabel: "assist"
        )
    }
}
