import Foundation

public struct StructuredLogFileWriter {
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    @discardableResult
    public func append<Entry: Encodable>(
        _ entry: Entry,
        timestamp: String,
        logsRootDirectory: URL,
        fileName: String,
        artifactLabel: String
    ) throws -> URL {
        let dateDirectory = logsRootDirectory.appendingPathComponent(Self.dateKey(from: timestamp), isDirectory: true)

        do {
            try fileManager.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        } catch {
            throw StructuredLogFileWriterError.createDirectoryFailed(
                artifactLabel: artifactLabel,
                path: dateDirectory.path,
                underlying: error
            )
        }

        let fileURL = dateDirectory.appendingPathComponent(fileName, isDirectory: false)

        let lineData: Data
        do {
            lineData = try encoder.encode(entry) + Data([0x0A])
        } catch {
            throw StructuredLogFileWriterError.encodeEntryFailed(
                artifactLabel: artifactLabel,
                underlying: error
            )
        }

        if !fileManager.fileExists(atPath: fileURL.path) {
            let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
            guard created else {
                throw StructuredLogFileWriterError.createFileFailed(
                    artifactLabel: artifactLabel,
                    path: fileURL.path
                )
            }
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw StructuredLogFileWriterError.openFileFailed(
                artifactLabel: artifactLabel,
                path: fileURL.path
            )
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } catch {
            throw StructuredLogFileWriterError.appendFailed(
                artifactLabel: artifactLabel,
                path: fileURL.path,
                underlying: error
            )
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

public enum StructuredLogFileWriterError: LocalizedError {
    case createDirectoryFailed(artifactLabel: String, path: String, underlying: Error)
    case createFileFailed(artifactLabel: String, path: String)
    case openFileFailed(artifactLabel: String, path: String)
    case encodeEntryFailed(artifactLabel: String, underlying: Error)
    case appendFailed(artifactLabel: String, path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let artifactLabel, let path, let underlying):
            return "Failed to create \(artifactLabel) log directory \(path): \(underlying.localizedDescription)"
        case .createFileFailed(let artifactLabel, let path):
            return "Failed to create \(artifactLabel) log file \(path)."
        case .openFileFailed(let artifactLabel, let path):
            return "Failed to open \(artifactLabel) log file \(path)."
        case .encodeEntryFailed(let artifactLabel, let underlying):
            return "Failed to encode \(artifactLabel) log entry: \(underlying.localizedDescription)"
        case .appendFailed(let artifactLabel, let path, let underlying):
            return "Failed to append \(artifactLabel) log file \(path): \(underlying.localizedDescription)"
        }
    }
}
