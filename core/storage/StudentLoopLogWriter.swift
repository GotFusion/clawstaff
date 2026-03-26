import Foundation

public protocol StudentLoopLogWriting {
    @discardableResult
    func write(_ entry: StudentLoopLogEntry) throws -> URL
}

public struct StudentLoopLogWriter: StudentLoopLogWriting {
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
    public func write(_ entry: StudentLoopLogEntry) throws -> URL {
        try fileWriter.append(
            entry,
            timestamp: entry.timestamp,
            logsRootDirectory: logsRootDirectory,
            fileName: "\(entry.sessionId)-student.log",
            artifactLabel: "student"
        )
    }
}
