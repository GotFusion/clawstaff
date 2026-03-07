import Foundation

public protocol AssistLoopLogWriting {
    @discardableResult
    func write(_ entry: AssistLoopLogEntry) throws -> URL
}

public struct AssistLoopLogWriter: AssistLoopLogWriting {
    private let fileManager: FileManager
    private let logsRootDirectory: URL
    private let encoder: JSONEncoder

    public init(
        logsRootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.logsRootDirectory = logsRootDirectory

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    @discardableResult
    public func write(_ entry: AssistLoopLogEntry) throws -> URL {
        let dateKey = Self.dateKey(from: entry.timestamp)
        let dateDirectory = logsRootDirectory.appendingPathComponent(dateKey, isDirectory: true)

        do {
            try fileManager.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        } catch {
            throw AssistLoopLogWriterError.createDirectoryFailed(path: dateDirectory.path, underlying: error)
        }

        let fileName = "\(entry.sessionId)-assist.log"
        let fileURL = dateDirectory.appendingPathComponent(fileName, isDirectory: false)

        let lineData: Data
        do {
            let encoded = try encoder.encode(entry)
            lineData = encoded + Data([0x0A])
        } catch {
            throw AssistLoopLogWriterError.encodeEntryFailed(underlying: error)
        }

        if !fileManager.fileExists(atPath: fileURL.path) {
            let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
            guard created else {
                throw AssistLoopLogWriterError.createFileFailed(path: fileURL.path)
            }
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw AssistLoopLogWriterError.openFileFailed(path: fileURL.path)
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } catch {
            throw AssistLoopLogWriterError.appendFailed(path: fileURL.path, underlying: error)
        }

        return fileURL
    }

    private static func dateKey(from timestamp: String) -> String {
        let pattern = "^\\d{4}-\\d{2}-\\d{2}$"
        let candidate = String(timestamp.prefix(10))
        if candidate.range(of: pattern, options: .regularExpression) != nil {
            return candidate
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

public enum AssistLoopLogWriterError: LocalizedError {
    case createDirectoryFailed(path: String, underlying: Error)
    case createFileFailed(path: String)
    case openFileFailed(path: String)
    case encodeEntryFailed(underlying: Error)
    case appendFailed(path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let path, let underlying):
            return "Failed to create assist log directory \(path): \(underlying.localizedDescription)"
        case .createFileFailed(let path):
            return "Failed to create assist log file \(path)."
        case .openFileFailed(let path):
            return "Failed to open assist log file \(path)."
        case .encodeEntryFailed(let underlying):
            return "Failed to encode assist log entry: \(underlying.localizedDescription)"
        case .appendFailed(let path, let underlying):
            return "Failed to append assist log file \(path): \(underlying.localizedDescription)"
        }
    }
}
