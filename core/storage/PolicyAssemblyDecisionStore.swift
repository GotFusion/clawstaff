import Foundation

public protocol PolicyAssemblyDecisionWriting {
    @discardableResult
    func store(_ decision: PolicyAssemblyDecision) throws -> URL
}

public struct PolicyAssemblyDecisionQuery: Equatable, Sendable {
    public let date: String?
    public let targetModule: PolicyAssemblyTargetModule?
    public let sessionId: String?
    public let taskId: String?
    public let traceId: String?

    public init(
        date: String? = nil,
        targetModule: PolicyAssemblyTargetModule? = nil,
        sessionId: String? = nil,
        taskId: String? = nil,
        traceId: String? = nil
    ) {
        self.date = date
        self.targetModule = targetModule
        self.sessionId = sessionId
        self.taskId = taskId
        self.traceId = traceId
    }
}

public enum PolicyAssemblyDecisionFeatureFlag {
    public static let environmentKey = "OPENSTAFF_ENABLE_POLICY_ASSEMBLY_LOG"

    public static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard let raw = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !raw.isEmpty else {
            return false
        }

        switch raw {
        case "1", "true", "yes", "on", "enabled":
            return true
        default:
            return false
        }
    }

    public static func storeIfEnabled(
        preferencesRootDirectory: URL,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PolicyAssemblyDecisionStore? {
        guard isEnabled(environment: environment) else {
            return nil
        }
        return PolicyAssemblyDecisionStore(
            preferencesRootDirectory: preferencesRootDirectory,
            fileManager: fileManager
        )
    }
}

public struct PolicyAssemblyDecisionStore: PolicyAssemblyDecisionWriting {
    public let preferencesRootDirectory: URL
    public let assemblyRootDirectory: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        preferencesRootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.preferencesRootDirectory = preferencesRootDirectory
        self.assemblyRootDirectory = preferencesRootDirectory.appendingPathComponent("assembly", isDirectory: true)
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func fileURL(for decision: PolicyAssemblyDecision) -> URL {
        let dateKey = Self.dateKey(from: decision.timestamp)
        let sessionKey = encodedPathComponent(
            decision.inputRef.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? decision.inputRef.sessionId!
                : "__unknown-session__"
        )

        return assemblyRootDirectory
            .appendingPathComponent(dateKey, isDirectory: true)
            .appendingPathComponent(decision.targetModule.rawValue, isDirectory: true)
            .appendingPathComponent(sessionKey, isDirectory: true)
            .appendingPathComponent("\(encodedPathComponent(decision.decisionId)).json", isDirectory: false)
    }

    @discardableResult
    public func store(_ decision: PolicyAssemblyDecision) throws -> URL {
        let fileURL = fileURL(for: decision)
        try ensureDirectory(fileURL.deletingLastPathComponent())

        do {
            let data = try encoder.encode(decision)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PolicyAssemblyDecisionStoreError.writeFailed(path: fileURL.path, underlying: error)
        }

        return fileURL
    }

    public func load(decisionId: String) throws -> PolicyAssemblyDecision? {
        let decisions = try loadDecisions()
        return decisions.first(where: { $0.decisionId == decisionId })
    }

    public func loadDecisions(
        matching query: PolicyAssemblyDecisionQuery = PolicyAssemblyDecisionQuery()
    ) throws -> [PolicyAssemblyDecision] {
        let baseDirectory = queryBaseDirectory(for: query)
        guard fileManager.fileExists(atPath: baseDirectory.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
            at: baseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var decisions: [PolicyAssemblyDecision] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json" else {
                continue
            }

            let decision = try readDecision(at: fileURL)
            if matchesQuery(decision, query: query) {
                decisions.append(decision)
            }
        }

        return decisions.sorted {
            if $0.timestamp == $1.timestamp {
                return $0.decisionId < $1.decisionId
            }
            return $0.timestamp < $1.timestamp
        }
    }

    private func queryBaseDirectory(for query: PolicyAssemblyDecisionQuery) -> URL {
        var base = assemblyRootDirectory
        if let date = query.date?.trimmingCharacters(in: .whitespacesAndNewlines),
           !date.isEmpty {
            base = base.appendingPathComponent(Self.dateKey(from: date), isDirectory: true)
        }
        if let targetModule = query.targetModule {
            base = base.appendingPathComponent(targetModule.rawValue, isDirectory: true)
        }
        if let sessionId = query.sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sessionId.isEmpty {
            base = base.appendingPathComponent(encodedPathComponent(sessionId), isDirectory: true)
        }
        return base
    }

    private func matchesQuery(
        _ decision: PolicyAssemblyDecision,
        query: PolicyAssemblyDecisionQuery
    ) -> Bool {
        if let targetModule = query.targetModule, decision.targetModule != targetModule {
            return false
        }
        if let sessionId = query.sessionId, decision.inputRef.sessionId != sessionId {
            return false
        }
        if let taskId = query.taskId, decision.inputRef.taskId != taskId {
            return false
        }
        if let traceId = query.traceId, decision.inputRef.traceId != traceId {
            return false
        }
        if let date = query.date, Self.dateKey(from: decision.timestamp) != Self.dateKey(from: date) {
            return false
        }
        return true
    }

    private func readDecision(at fileURL: URL) throws -> PolicyAssemblyDecision {
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(PolicyAssemblyDecision.self, from: data)
        } catch {
            throw PolicyAssemblyDecisionStoreError.decodeFailed(path: fileURL.path, underlying: error)
        }
    }

    private func ensureDirectory(_ directoryURL: URL) throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw PolicyAssemblyDecisionStoreError.createDirectoryFailed(
                path: directoryURL.path,
                underlying: error
            )
        }
    }

    private func encodedPathComponent(_ raw: String) -> String {
        Self.encodedPathComponent(raw)
    }

    private static func encodedPathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-%"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? raw.replacingOccurrences(of: "/", with: "%2F")
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

public enum PolicyAssemblyDecisionStoreError: LocalizedError {
    case createDirectoryFailed(path: String, underlying: Error)
    case writeFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let path, let underlying):
            return "Failed to create policy assembly directory \(path): \(underlying.localizedDescription)"
        case .writeFailed(let path, let underlying):
            return "Failed to write policy assembly decision \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode policy assembly decision \(path): \(underlying.localizedDescription)"
        }
    }
}
