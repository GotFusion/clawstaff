import Foundation

public enum PreferenceAuditLogAction: String, Codable, CaseIterable, Sendable {
    case signalStored
    case ruleCreated
    case ruleUpdated
    case rulePromoted
    case ruleSuperseded
    case ruleRevoked
    case ruleRolledBack
    case profileSnapshotStored
    case rollbackApplied
}

public enum PreferenceAuditSourceKind: String, Codable, CaseIterable, Sendable {
    case signalIngestion
    case manual
    case rulePromotion
    case teacherAction
    case profileBuilder
    case cli
    case rollbackService
    case system
}

public struct PreferenceAuditSource: Codable, Equatable, Sendable {
    public let kind: PreferenceAuditSourceKind
    public let referenceId: String?
    public let summary: String?

    public init(
        kind: PreferenceAuditSourceKind,
        referenceId: String? = nil,
        summary: String? = nil
    ) {
        self.kind = kind
        self.referenceId = Self.normalized(referenceId)
        self.summary = Self.normalized(summary)
    }

    public static func signalIngestion(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .signalIngestion, referenceId: referenceId, summary: summary)
    }

    public static func manual(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .manual, referenceId: referenceId, summary: summary)
    }

    public static func rulePromotion(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .rulePromotion, referenceId: referenceId, summary: summary)
    }

    public static func teacherAction(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .teacherAction, referenceId: referenceId, summary: summary)
    }

    public static func profileBuilder(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .profileBuilder, referenceId: referenceId, summary: summary)
    }

    public static func cli(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .cli, referenceId: referenceId, summary: summary)
    }

    public static func rollbackService(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .rollbackService, referenceId: referenceId, summary: summary)
    }

    public static func system(
        referenceId: String? = nil,
        summary: String? = nil
    ) -> Self {
        Self(kind: .system, referenceId: referenceId, summary: summary)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct PreferenceAuditLogEntry: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let auditId: String
    public let action: PreferenceAuditLogAction
    public let timestamp: String
    public let actor: String
    public let source: PreferenceAuditSource
    public let signalIds: [String]
    public let ruleId: String?
    public let affectedRuleIds: [String]
    public let profileVersion: String?
    public let relatedProfileVersion: String?
    public let previousActivationStatus: PreferenceRuleActivationStatus?
    public let newActivationStatus: PreferenceRuleActivationStatus?
    public let relatedRuleId: String?
    public let note: String?

    public init(
        schemaVersion: String = "openstaff.learning.preference-audit.v0",
        auditId: String,
        action: PreferenceAuditLogAction,
        timestamp: String,
        actor: String,
        source: PreferenceAuditSource,
        signalIds: [String] = [],
        ruleId: String? = nil,
        affectedRuleIds: [String] = [],
        profileVersion: String? = nil,
        relatedProfileVersion: String? = nil,
        previousActivationStatus: PreferenceRuleActivationStatus? = nil,
        newActivationStatus: PreferenceRuleActivationStatus? = nil,
        relatedRuleId: String? = nil,
        note: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.auditId = auditId
        self.action = action
        self.timestamp = timestamp
        self.actor = actor
        self.source = source
        self.signalIds = Array(Set(signalIds)).sorted()
        self.ruleId = Self.normalized(ruleId)
        self.affectedRuleIds = Array(Set(affectedRuleIds + [ruleId].compactMap { $0 })).sorted()
        self.profileVersion = Self.normalized(profileVersion)
        self.relatedProfileVersion = Self.normalized(relatedProfileVersion)
        self.previousActivationStatus = previousActivationStatus
        self.newActivationStatus = newActivationStatus
        self.relatedRuleId = Self.normalized(relatedRuleId)
        self.note = Self.normalized(note)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct PreferenceAuditLogQuery: Equatable, Sendable {
    public let date: String?
    public let ruleId: String?
    public let profileVersion: String?
    public let action: PreferenceAuditLogAction?

    public init(
        date: String? = nil,
        ruleId: String? = nil,
        profileVersion: String? = nil,
        action: PreferenceAuditLogAction? = nil
    ) {
        self.date = date
        self.ruleId = ruleId
        self.profileVersion = profileVersion
        self.action = action
    }
}

public struct PreferenceAuditLogStore {
    public let auditRootDirectory: URL

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let lineEncoder: JSONEncoder

    public init(
        auditRootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.auditRootDirectory = auditRootDirectory
        self.fileManager = fileManager
        self.decoder = JSONDecoder()

        let lineEncoder = JSONEncoder()
        lineEncoder.outputFormatting = [.sortedKeys]
        self.lineEncoder = lineEncoder
    }

    public func append(_ entry: PreferenceAuditLogEntry) throws {
        let fileURL = auditFileURL(for: entry.timestamp)
        try ensureDirectory(fileURL.deletingLastPathComponent())
        try appendJSONLine(entry, to: fileURL)
    }

    public func loadEntries(
        matching query: PreferenceAuditLogQuery = PreferenceAuditLogQuery()
    ) throws -> [PreferenceAuditLogEntry] {
        let urls: [URL]
        if let date = query.date {
            let fileURL = auditFileURL(for: date)
            urls = fileManager.fileExists(atPath: fileURL.path) ? [fileURL] : []
        } else {
            urls = try allAuditFileURLs()
        }

        return try urls
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            .flatMap { fileURL in
                try readJSONLines(PreferenceAuditLogEntry.self, from: fileURL)
            }
            .filter { entry in
                matches(entry, query: query)
            }
            .sorted {
                ($0.timestamp, $0.auditId) < ($1.timestamp, $1.auditId)
            }
    }

    public func auditFileURL(for timestampOrDate: String) -> URL {
        let dateKey = Self.dateKey(from: timestampOrDate)
        return auditRootDirectory.appendingPathComponent("\(dateKey).jsonl", isDirectory: false)
    }

    private func matches(
        _ entry: PreferenceAuditLogEntry,
        query: PreferenceAuditLogQuery
    ) -> Bool {
        if let action = query.action, entry.action != action {
            return false
        }

        if let ruleId = query.ruleId {
            let matchesRule = entry.ruleId == ruleId || entry.affectedRuleIds.contains(ruleId)
            if !matchesRule {
                return false
            }
        }

        if let profileVersion = query.profileVersion {
            let matchesProfile = entry.profileVersion == profileVersion
                || entry.relatedProfileVersion == profileVersion
            if !matchesProfile {
                return false
            }
        }

        return true
    }

    private func allAuditFileURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: auditRootDirectory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(at: auditRootDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to fileURL: URL) throws {
        let lineData: Data
        do {
            lineData = try lineEncoder.encode(value) + Data([0x0A])
        } catch {
            throw PreferenceAuditLogStoreError.encodeFailed(underlying: error)
        }

        if !fileManager.fileExists(atPath: fileURL.path) {
            let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
            guard created else {
                throw PreferenceAuditLogStoreError.createFileFailed(path: fileURL.path)
            }
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            throw PreferenceAuditLogStoreError.openFileFailed(path: fileURL.path)
        }
        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } catch {
            throw PreferenceAuditLogStoreError.writeFailed(path: fileURL.path, underlying: error)
        }
    }

    private func ensureDirectory(_ directoryURL: URL) throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw PreferenceAuditLogStoreError.createDirectoryFailed(path: directoryURL.path, underlying: error)
        }
    }

    private func readJSONLines<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> [T] {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return try content
                .split(whereSeparator: \.isNewline)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { line in
                    try decoder.decode(type, from: Data(line.utf8))
                }
        } catch {
            throw PreferenceAuditLogStoreError.decodeFailed(path: fileURL.path, underlying: error)
        }
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

public enum PreferenceAuditLogStoreError: LocalizedError {
    case createDirectoryFailed(path: String, underlying: Error)
    case createFileFailed(path: String)
    case openFileFailed(path: String)
    case encodeFailed(underlying: Error)
    case writeFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let path, let underlying):
            return "Failed to create preference audit directory \(path): \(underlying.localizedDescription)"
        case .createFileFailed(let path):
            return "Failed to create preference audit file \(path)."
        case .openFileFailed(let path):
            return "Failed to open preference audit file \(path)."
        case .encodeFailed(let underlying):
            return "Failed to encode preference audit payload: \(underlying.localizedDescription)"
        case .writeFailed(let path, let underlying):
            return "Failed to write preference audit payload \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode preference audit payload \(path): \(underlying.localizedDescription)"
        }
    }
}
