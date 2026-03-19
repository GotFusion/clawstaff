import Foundation

public struct PreferenceRuleQuery: Equatable, Sendable {
    public let appBundleId: String?
    public let taskFamily: String?
    public let skillFamily: String?
    public let includeInactive: Bool

    public init(
        appBundleId: String? = nil,
        taskFamily: String? = nil,
        skillFamily: String? = nil,
        includeInactive: Bool = false
    ) {
        self.appBundleId = appBundleId
        self.taskFamily = taskFamily
        self.skillFamily = skillFamily
        self.includeInactive = includeInactive
    }

    public var hasFilters: Bool {
        appBundleId != nil || taskFamily != nil || skillFamily != nil
    }
}

public struct PreferenceRuleAuditContext: Equatable, Sendable {
    public let action: PreferenceAuditLogAction?
    public let source: PreferenceAuditSource
    public let relatedRuleId: String?
    public let relatedProfileVersion: String?

    public init(
        action: PreferenceAuditLogAction? = nil,
        source: PreferenceAuditSource = .manual(),
        relatedRuleId: String? = nil,
        relatedProfileVersion: String? = nil
    ) {
        self.action = action
        self.source = source
        self.relatedRuleId = relatedRuleId
        self.relatedProfileVersion = relatedProfileVersion
    }

    public static func manual(
        action: PreferenceAuditLogAction? = nil,
        source: PreferenceAuditSource = .manual(),
        relatedRuleId: String? = nil,
        relatedProfileVersion: String? = nil
    ) -> Self {
        Self(
            action: action,
            source: source,
            relatedRuleId: relatedRuleId,
            relatedProfileVersion: relatedProfileVersion
        )
    }
}

public struct PreferenceProfileAuditContext: Equatable, Sendable {
    public let source: PreferenceAuditSource
    public let relatedProfileVersion: String?

    public init(
        source: PreferenceAuditSource = .profileBuilder(),
        relatedProfileVersion: String? = nil
    ) {
        self.source = source
        self.relatedProfileVersion = relatedProfileVersion
    }

    public static func builder(
        source: PreferenceAuditSource = .profileBuilder(),
        relatedProfileVersion: String? = nil
    ) -> Self {
        Self(
            source: source,
            relatedProfileVersion: relatedProfileVersion
        )
    }
}

public struct PreferenceMemoryStore {
    public let preferencesRootDirectory: URL
    public let signalsRootDirectory: URL
    public let rulesRootDirectory: URL
    public let profilesRootDirectory: URL
    public let assemblyRootDirectory: URL
    public let auditRootDirectory: URL
    public let auditLogStore: PreferenceAuditLogStore

    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let prettyEncoder: JSONEncoder

    public init(
        preferencesRootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.preferencesRootDirectory = preferencesRootDirectory
        self.signalsRootDirectory = preferencesRootDirectory.appendingPathComponent("signals", isDirectory: true)
        self.rulesRootDirectory = preferencesRootDirectory.appendingPathComponent("rules", isDirectory: true)
        self.profilesRootDirectory = preferencesRootDirectory.appendingPathComponent("profiles", isDirectory: true)
        self.assemblyRootDirectory = preferencesRootDirectory.appendingPathComponent("assembly", isDirectory: true)
        self.auditRootDirectory = preferencesRootDirectory.appendingPathComponent("audit", isDirectory: true)
        self.auditLogStore = PreferenceAuditLogStore(
            auditRootDirectory: self.auditRootDirectory,
            fileManager: fileManager
        )
        self.fileManager = fileManager
        self.decoder = JSONDecoder()

        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.prettyEncoder = prettyEncoder
    }

    public func signalFileURL(for signal: PreferenceSignal) -> URL {
        signalsRootDirectory
            .appendingPathComponent(Self.dateKey(from: signal.timestamp), isDirectory: true)
            .appendingPathComponent(signal.sessionId, isDirectory: true)
            .appendingPathComponent("\(signal.turnId).json", isDirectory: false)
    }

    public func ruleFileURL(for ruleId: String) -> URL {
        rulesRootDirectory.appendingPathComponent("\(ruleId).json", isDirectory: false)
    }

    public func profileFileURL(for profileVersion: String) -> URL {
        profilesRootDirectory.appendingPathComponent("\(profileVersion).json", isDirectory: false)
    }

    @discardableResult
    public func storeSignals(
        _ signals: [PreferenceSignal],
        actor: String = "system",
        source: PreferenceAuditSource = .signalIngestion(),
        note: String? = nil
    ) throws -> [URL] {
        guard !signals.isEmpty else {
            return []
        }

        let groupedSignals = Dictionary(grouping: signals) { signal in
            "\(signal.sessionId)\u{0}\(signal.turnId)"
        }

        var writtenURLs: [URL] = []

        for key in groupedSignals.keys.sorted() {
            guard let group = groupedSignals[key], let firstSignal = group.first else {
                continue
            }

            let fileURL = signalFileURL(for: firstSignal)
            try ensureDirectory(fileURL.deletingLastPathComponent())

            let existingSignals = try loadSignalsFromGroupFile(at: fileURL)
            var mergedSignalsById: [String: PreferenceSignal] = [:]
            for signal in existingSignals {
                mergedSignalsById[signal.signalId] = signal
            }
            for signal in group {
                mergedSignalsById[signal.signalId] = signal
            }

            let mergedSignals = mergedSignalsById.values.sorted {
                ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
            }

            try writeJSON(mergedSignals, to: fileURL)
            let relativePath = relativePath(from: preferencesRootDirectory, to: fileURL)
            for signal in mergedSignals {
                try writeSignalIndex(
                    PreferenceSignalIndexEntry(
                        signalId: signal.signalId,
                        turnId: signal.turnId,
                        sessionId: signal.sessionId,
                        timestamp: signal.timestamp,
                        relativePath: relativePath
                    )
                )
            }

            writtenURLs.append(fileURL)

            let timestamp = mergedSignals.map(\.timestamp).max() ?? firstSignal.timestamp
            try auditLogStore.append(
                PreferenceAuditLogEntry(
                    auditId: "audit-signal-\(UUID().uuidString)",
                    action: .signalStored,
                    timestamp: timestamp,
                    actor: actor,
                    source: source,
                    signalIds: group.map(\.signalId),
                    note: note
                )
            )
        }

        return writtenURLs.sorted(by: { $0.path < $1.path })
    }

    @discardableResult
    public func storeRule(
        _ rule: PreferenceRule,
        actor: String = "system",
        auditContext: PreferenceRuleAuditContext = .manual(),
        note: String? = nil
    ) throws -> URL {
        guard !rule.sourceSignalIds.isEmpty else {
            throw PreferenceMemoryStoreError.invalidRule(ruleId: rule.ruleId, reason: "sourceSignalIds is empty")
        }
        guard !rule.evidence.isEmpty else {
            throw PreferenceMemoryStoreError.invalidRule(ruleId: rule.ruleId, reason: "evidence is empty")
        }

        let fileURL = ruleFileURL(for: rule.ruleId)
        let previousRule = try loadRule(ruleId: rule.ruleId)

        try ensureDirectory(fileURL.deletingLastPathComponent())
        try writeJSON(rule, to: fileURL)
        try refreshRuleIndexes(previousRule: previousRule, newRule: rule)

        try auditLogStore.append(
            PreferenceAuditLogEntry(
                auditId: "audit-rule-\(UUID().uuidString)",
                action: auditAction(
                    previousRule: previousRule,
                    newRule: rule,
                    auditContext: auditContext
                ),
                timestamp: rule.updatedAt,
                actor: actor,
                source: auditContext.source,
                signalIds: rule.sourceSignalIds,
                ruleId: rule.ruleId,
                relatedProfileVersion: auditContext.relatedProfileVersion,
                previousActivationStatus: previousRule?.activationStatus,
                newActivationStatus: rule.activationStatus,
                relatedRuleId: auditContext.relatedRuleId ?? rule.supersededByRuleId,
                note: note
            )
        )

        return fileURL
    }

    @discardableResult
    public func storeProfileSnapshot(
        _ snapshot: PreferenceProfileSnapshot,
        actor: String = "system",
        auditContext: PreferenceProfileAuditContext = .builder(),
        note: String? = nil
    ) throws -> URL {
        guard snapshot.profile.profileVersion == snapshot.profileVersion else {
            throw PreferenceMemoryStoreError.invalidProfile(
                profileVersion: snapshot.profileVersion,
                reason: "profileVersion does not match embedded profile"
            )
        }

        let fileURL = profileFileURL(for: snapshot.profileVersion)
        try ensureDirectory(fileURL.deletingLastPathComponent())
        try writeJSON(snapshot, to: fileURL)
        try writeJSON(
            PreferenceProfileLatestPointer(
                profileVersion: snapshot.profileVersion,
                updatedAt: snapshot.createdAt
            ),
            to: latestProfilePointerURL
        )
        try auditLogStore.append(
            PreferenceAuditLogEntry(
                auditId: "audit-profile-\(UUID().uuidString)",
                action: .profileSnapshotStored,
                timestamp: snapshot.createdAt,
                actor: actor,
                source: auditContext.source,
                signalIds: [],
                profileVersion: snapshot.profileVersion,
                relatedProfileVersion: auditContext.relatedProfileVersion ?? snapshot.previousProfileVersion,
                note: note ?? snapshot.note
            )
        )
        return fileURL
    }

    public func loadRule(ruleId: String) throws -> PreferenceRule? {
        let fileURL = ruleFileURL(for: ruleId)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try readJSON(PreferenceRule.self, from: fileURL)
    }

    public func loadRules(matching query: PreferenceRuleQuery = PreferenceRuleQuery()) throws -> [PreferenceRule] {
        let candidateRules: [PreferenceRule]
        let indexURLs = relevantRuleIndexURLs(for: query)

        if indexURLs.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            let ruleIds = try loadIndexedRuleIDs(for: query)
            candidateRules = try ruleIds.compactMap { ruleId in
                try loadRule(ruleId: ruleId)
            }
        } else {
            candidateRules = try allRuleFileURLs().map {
                try readJSON(PreferenceRule.self, from: $0)
            }
        }

        return candidateRules
            .filter { ruleMatchesQuery($0, query: query) }
            .sorted(by: sortRules)
    }

    public func loadProfileSnapshot(profileVersion: String) throws -> PreferenceProfileSnapshot? {
        let fileURL = profileFileURL(for: profileVersion)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try readJSON(PreferenceProfileSnapshot.self, from: fileURL)
    }

    public func loadLatestProfileSnapshot() throws -> PreferenceProfileSnapshot? {
        if fileManager.fileExists(atPath: latestProfilePointerURL.path) {
            let pointer = try readJSON(PreferenceProfileLatestPointer.self, from: latestProfilePointerURL)
            return try loadProfileSnapshot(profileVersion: pointer.profileVersion)
        }

        let urls = try allProfileFileURLs().sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
        guard let latestURL = urls.last else {
            return nil
        }
        return try readJSON(PreferenceProfileSnapshot.self, from: latestURL)
    }

    public func loadSignals(for ruleId: String) throws -> [PreferenceSignal] {
        guard let rule = try loadRule(ruleId: ruleId) else {
            throw PreferenceMemoryStoreError.ruleNotFound(ruleId: ruleId)
        }

        var groupedSignalsByPath: [String: [PreferenceSignal]] = [:]
        var collectedSignals: [PreferenceSignal] = []

        for signalId in rule.sourceSignalIds.sorted() {
            guard let fileURL = try locateSignalFile(signalId: signalId) else {
                continue
            }

            let pathKey = fileURL.path
            let groupSignals: [PreferenceSignal]
            if let cached = groupedSignalsByPath[pathKey] {
                groupSignals = cached
            } else {
                let loaded = try loadSignalsFromGroupFile(at: fileURL)
                groupedSignalsByPath[pathKey] = loaded
                groupSignals = loaded
            }

            if let signal = groupSignals.first(where: { $0.signalId == signalId }) {
                collectedSignals.append(signal)
            }
        }

        return collectedSignals.sorted {
            ($0.timestamp, $0.signalId) < ($1.timestamp, $1.signalId)
        }
    }

    public func loadAuditEntries(on date: String? = nil) throws -> [PreferenceAuditLogEntry] {
        try auditLogStore.loadEntries(matching: PreferenceAuditLogQuery(date: date))
    }

    public func loadAuditEntries(
        matching query: PreferenceAuditLogQuery
    ) throws -> [PreferenceAuditLogEntry] {
        try auditLogStore.loadEntries(matching: query)
    }

    @discardableResult
    public func revokeRule(
        ruleId: String,
        actor: String,
        reason: String,
        timestamp: String
    ) throws -> PreferenceRule {
        guard let rule = try loadRule(ruleId: ruleId) else {
            throw PreferenceMemoryStoreError.ruleNotFound(ruleId: ruleId)
        }

        let updatedRule = rule.updatingActivationStatus(
            .revoked,
            updatedAt: timestamp,
            lifecycleReason: reason
        )
        try storeRule(
            updatedRule,
            actor: actor,
            auditContext: PreferenceRuleAuditContext(
                action: .ruleRevoked,
                source: .teacherAction(referenceId: ruleId, summary: reason)
            ),
            note: reason
        )
        return updatedRule
    }

    @discardableResult
    public func supersedeRule(
        ruleId: String,
        supersededByRuleId: String,
        actor: String,
        reason: String,
        timestamp: String
    ) throws -> PreferenceRule {
        guard let rule = try loadRule(ruleId: ruleId) else {
            throw PreferenceMemoryStoreError.ruleNotFound(ruleId: ruleId)
        }

        let updatedRule = rule.updatingActivationStatus(
            .superseded,
            updatedAt: timestamp,
            supersededByRuleId: supersededByRuleId,
            lifecycleReason: reason
        )
        try storeRule(
            updatedRule,
            actor: actor,
            auditContext: PreferenceRuleAuditContext(
                action: .ruleSuperseded,
                source: .teacherAction(referenceId: ruleId, summary: reason),
                relatedRuleId: supersededByRuleId
            ),
            note: reason
        )
        return updatedRule
    }

    private var latestProfilePointerURL: URL {
        profilesRootDirectory.appendingPathComponent("latest.json", isDirectory: false)
    }

    private func refreshRuleIndexes(
        previousRule: PreferenceRule?,
        newRule: PreferenceRule
    ) throws {
        let targetsToRemove = previousRule.map(indexTargets(for:)) ?? []
        let targetsToAdd = indexTargets(for: newRule)
        let allTargets = Array(Set(targetsToRemove + targetsToAdd)).sorted {
            ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key)
        }

        for target in allTargets {
            let url = ruleIndexURL(kind: target.kind, key: target.key)
            var indexDocument = try loadRuleIndexDocument(kind: target.kind, key: target.key)
            indexDocument.entries.removeAll { $0.ruleId == newRule.ruleId }

            if targetsToAdd.contains(target) {
                indexDocument.entries.append(PreferenceRuleIndexEntry(rule: newRule))
                indexDocument.entries.sort { lhs, rhs in
                    (lhs.updatedAt, lhs.ruleId) < (rhs.updatedAt, rhs.ruleId)
                }
            }

            if indexDocument.entries.isEmpty {
                try removeFileIfExists(at: url)
            } else {
                indexDocument.updatedAt = newRule.updatedAt
                try ensureDirectory(url.deletingLastPathComponent())
                try writeJSON(indexDocument, to: url)
            }
        }
    }

    private func loadIndexedRuleIDs(for query: PreferenceRuleQuery) throws -> Set<String> {
        let urls = relevantRuleIndexURLs(for: query)
        var collectedRuleIDs: Set<String> = []

        for url in urls where fileManager.fileExists(atPath: url.path) {
            let document = try readJSON(PreferenceRuleIndexDocument.self, from: url)
            document.entries.forEach { collectedRuleIDs.insert($0.ruleId) }
        }

        return collectedRuleIDs
    }

    private func relevantRuleIndexURLs(for query: PreferenceRuleQuery) -> [URL] {
        guard query.hasFilters else {
            return [ruleIndexURL(kind: .all, key: PreferenceRuleIndexKind.all.defaultKey)]
        }

        var urls: [URL] = []

        urls.append(ruleIndexURL(kind: .global, key: PreferenceRuleIndexKind.global.defaultKey))
        if let appBundleId = query.appBundleId {
            urls.append(ruleIndexURL(kind: .app, key: appBundleId))
        }
        if let taskFamily = query.taskFamily {
            urls.append(ruleIndexURL(kind: .taskFamily, key: taskFamily))
        }
        if let skillFamily = query.skillFamily {
            urls.append(ruleIndexURL(kind: .skillFamily, key: skillFamily))
        }

        return urls
    }

    private func indexTargets(for rule: PreferenceRule) -> [RuleIndexTarget] {
        var targets: [RuleIndexTarget] = [
            RuleIndexTarget(kind: .all, key: PreferenceRuleIndexKind.all.defaultKey)
        ]

        if rule.scope.level == .global {
            targets.append(RuleIndexTarget(kind: .global, key: PreferenceRuleIndexKind.global.defaultKey))
        }
        if let appBundleId = rule.scope.appBundleId {
            targets.append(RuleIndexTarget(kind: .app, key: appBundleId))
        }
        if let taskFamily = rule.scope.taskFamily {
            targets.append(RuleIndexTarget(kind: .taskFamily, key: taskFamily))
        }
        if let skillFamily = rule.scope.skillFamily {
            targets.append(RuleIndexTarget(kind: .skillFamily, key: skillFamily))
        }

        return Array(Set(targets))
    }

    private func ruleMatchesQuery(
        _ rule: PreferenceRule,
        query: PreferenceRuleQuery
    ) -> Bool {
        if !query.includeInactive, rule.activationStatus != .active {
            return false
        }

        guard query.hasFilters else {
            return true
        }

        if rule.scope.level == .global {
            return true
        }

        if let scopedAppBundleId = rule.scope.appBundleId,
           scopedAppBundleId != query.appBundleId {
            return false
        }
        if let scopedTaskFamily = rule.scope.taskFamily,
           scopedTaskFamily != query.taskFamily {
            return false
        }
        if let scopedSkillFamily = rule.scope.skillFamily,
           scopedSkillFamily != query.skillFamily {
            return false
        }

        switch rule.scope.level {
        case .global:
            return true
        case .app:
            return rule.scope.appBundleId == query.appBundleId
        case .taskFamily:
            return rule.scope.taskFamily == query.taskFamily
        case .skillFamily:
            return rule.scope.skillFamily == query.skillFamily
        case .windowPattern:
            return false
        }
    }

    private func sortRules(lhs: PreferenceRule, rhs: PreferenceRule) -> Bool {
        PreferenceConflictResolver().sortsBefore(lhs, rhs)
    }

    private func locateSignalFile(signalId: String) throws -> URL? {
        if let indexEntry = try loadSignalIndex(signalId: signalId) {
            let fileURL = preferencesRootDirectory.appendingPathComponent(indexEntry.relativePath, isDirectory: false)
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }

        guard fileManager.fileExists(atPath: signalsRootDirectory.path) else {
            return nil
        }

        guard let enumerator = fileManager.enumerator(at: signalsRootDirectory, includingPropertiesForKeys: nil) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "json",
                  !fileURL.path.contains("/index/") else {
                continue
            }

            let signals = try loadSignalsFromGroupFile(at: fileURL)
            if signals.contains(where: { $0.signalId == signalId }) {
                let relativePath = relativePath(from: preferencesRootDirectory, to: fileURL)
                if let matchedSignal = signals.first(where: { $0.signalId == signalId }) {
                    try writeSignalIndex(
                        PreferenceSignalIndexEntry(
                            signalId: matchedSignal.signalId,
                            turnId: matchedSignal.turnId,
                            sessionId: matchedSignal.sessionId,
                            timestamp: matchedSignal.timestamp,
                            relativePath: relativePath
                        )
                    )
                }
                return fileURL
            }
        }

        return nil
    }

    private func loadSignalsFromGroupFile(at fileURL: URL) throws -> [PreferenceSignal] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        return try readJSON([PreferenceSignal].self, from: fileURL)
    }

    private func writeSignalIndex(_ entry: PreferenceSignalIndexEntry) throws {
        let url = signalIndexURL(for: entry.signalId)
        try ensureDirectory(url.deletingLastPathComponent())
        try writeJSON(entry, to: url)
    }

    private func loadSignalIndex(signalId: String) throws -> PreferenceSignalIndexEntry? {
        let url = signalIndexURL(for: signalId)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try readJSON(PreferenceSignalIndexEntry.self, from: url)
    }

    private func signalIndexURL(for signalId: String) -> URL {
        signalsRootDirectory
            .appendingPathComponent("index", isDirectory: true)
            .appendingPathComponent("by-id", isDirectory: true)
            .appendingPathComponent("\(Self.encodedPathComponent(signalId)).json", isDirectory: false)
    }

    private func ruleIndexURL(kind: PreferenceRuleIndexKind, key: String) -> URL {
        let encodedKey = Self.encodedPathComponent(key)
        return rulesRootDirectory
            .appendingPathComponent("index", isDirectory: true)
            .appendingPathComponent(kind.directoryName, isDirectory: true)
            .appendingPathComponent("\(encodedKey).json", isDirectory: false)
    }

    private func loadRuleIndexDocument(
        kind: PreferenceRuleIndexKind,
        key: String
    ) throws -> PreferenceRuleIndexDocument {
        let url = ruleIndexURL(kind: kind, key: key)
        guard fileManager.fileExists(atPath: url.path) else {
            return PreferenceRuleIndexDocument(kind: kind, key: key, updatedAt: nil, entries: [])
        }
        return try readJSON(PreferenceRuleIndexDocument.self, from: url)
    }

    private func allRuleFileURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: rulesRootDirectory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(at: rulesRootDirectory, includingPropertiesForKeys: nil)
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent != "latest.json"
                    && $0.lastPathComponent != "index.json"
                    && !$0.path.contains("/index/")
            }
    }

    private func allProfileFileURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: profilesRootDirectory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(at: profilesRootDirectory, includingPropertiesForKeys: nil)
            .filter {
                $0.pathExtension == "json"
                    && $0.lastPathComponent != "latest.json"
            }
    }

    private func writeJSON<T: Encodable>(_ value: T, to fileURL: URL) throws {
        do {
            let data = try prettyEncoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw PreferenceMemoryStoreError.writeFailed(path: fileURL.path, underlying: error)
        }
    }

    private func ensureDirectory(_ directoryURL: URL) throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw PreferenceMemoryStoreError.createDirectoryFailed(path: directoryURL.path, underlying: error)
        }
    }

    private func removeFileIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw PreferenceMemoryStoreError.writeFailed(path: url.path, underlying: error)
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from fileURL: URL) throws -> T {
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(type, from: data)
        } catch {
            throw PreferenceMemoryStoreError.decodeFailed(path: fileURL.path, underlying: error)
        }
    }

    private func relativePath(from root: URL, to fileURL: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents

        guard fileComponents.starts(with: rootComponents) else {
            return fileURL.path
        }

        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
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

    private static func encodedPathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-%"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? raw.replacingOccurrences(of: "/", with: "%2F")
    }

    private func auditAction(
        previousRule: PreferenceRule?,
        newRule: PreferenceRule,
        auditContext: PreferenceRuleAuditContext
    ) -> PreferenceAuditLogAction {
        if let action = auditContext.action {
            return action
        }

        if auditContext.source.kind == .rollbackService {
            return .ruleRolledBack
        }

        guard let previousRule else {
            return auditContext.source.kind == .rulePromotion ? .rulePromoted : .ruleCreated
        }

        if previousRule.activationStatus != .superseded,
           newRule.activationStatus == .superseded {
            return .ruleSuperseded
        }

        if previousRule.activationStatus != .revoked,
           newRule.activationStatus == .revoked {
            return .ruleRevoked
        }

        return .ruleUpdated
    }

}

public enum PreferenceMemoryStoreError: LocalizedError {
    case createDirectoryFailed(path: String, underlying: Error)
    case createFileFailed(path: String)
    case openFileFailed(path: String)
    case encodeFailed(underlying: Error)
    case writeFailed(path: String, underlying: Error)
    case decodeFailed(path: String, underlying: Error)
    case invalidRule(ruleId: String, reason: String)
    case invalidProfile(profileVersion: String, reason: String)
    case ruleNotFound(ruleId: String)

    public var errorDescription: String? {
        switch self {
        case .createDirectoryFailed(let path, let underlying):
            return "Failed to create preference memory directory \(path): \(underlying.localizedDescription)"
        case .createFileFailed(let path):
            return "Failed to create preference memory file \(path)."
        case .openFileFailed(let path):
            return "Failed to open preference memory file \(path)."
        case .encodeFailed(let underlying):
            return "Failed to encode preference memory payload: \(underlying.localizedDescription)"
        case .writeFailed(let path, let underlying):
            return "Failed to write preference memory payload \(path): \(underlying.localizedDescription)"
        case .decodeFailed(let path, let underlying):
            return "Failed to decode preference memory payload \(path): \(underlying.localizedDescription)"
        case .invalidRule(let ruleId, let reason):
            return "Preference rule \(ruleId) is invalid: \(reason)"
        case .invalidProfile(let profileVersion, let reason):
            return "Preference profile \(profileVersion) is invalid: \(reason)"
        case .ruleNotFound(let ruleId):
            return "Preference rule \(ruleId) was not found."
        }
    }
}

private struct PreferenceSignalIndexEntry: Codable, Equatable {
    let schemaVersion: String
    let signalId: String
    let turnId: String
    let sessionId: String
    let timestamp: String
    let relativePath: String

    init(
        schemaVersion: String = "openstaff.learning.preference-signal-index.v0",
        signalId: String,
        turnId: String,
        sessionId: String,
        timestamp: String,
        relativePath: String
    ) {
        self.schemaVersion = schemaVersion
        self.signalId = signalId
        self.turnId = turnId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.relativePath = relativePath
    }
}

private enum PreferenceRuleIndexKind: String, CaseIterable {
    case all
    case global
    case app
    case taskFamily
    case skillFamily

    var directoryName: String {
        switch self {
        case .all:
            return "all"
        case .global:
            return "global"
        case .app:
            return "by-app"
        case .taskFamily:
            return "by-task-family"
        case .skillFamily:
            return "by-skill-family"
        }
    }

    var defaultKey: String {
        switch self {
        case .all:
            return "__all__"
        case .global:
            return "global"
        case .app, .taskFamily, .skillFamily:
            return ""
        }
    }
}

private struct RuleIndexTarget: Hashable {
    let kind: PreferenceRuleIndexKind
    let key: String
}

private struct PreferenceRuleIndexEntry: Codable, Equatable {
    let ruleId: String
    let scopeLevel: PreferenceSignalScope
    let appBundleId: String?
    let taskFamily: String?
    let skillFamily: String?
    let activationStatus: PreferenceRuleActivationStatus
    let teacherConfirmed: Bool
    let updatedAt: String

    init(rule: PreferenceRule) {
        self.ruleId = rule.ruleId
        self.scopeLevel = rule.scope.level
        self.appBundleId = rule.scope.appBundleId
        self.taskFamily = rule.scope.taskFamily
        self.skillFamily = rule.scope.skillFamily
        self.activationStatus = rule.activationStatus
        self.teacherConfirmed = rule.teacherConfirmed
        self.updatedAt = rule.updatedAt
    }
}

private struct PreferenceRuleIndexDocument: Codable, Equatable {
    let schemaVersion: String
    let indexKind: String
    let key: String
    var updatedAt: String
    var entries: [PreferenceRuleIndexEntry]

    init(
        schemaVersion: String = "openstaff.learning.preference-rule-index.v0",
        kind: PreferenceRuleIndexKind,
        key: String,
        updatedAt: String?,
        entries: [PreferenceRuleIndexEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.indexKind = kind.rawValue
        self.key = key
        self.updatedAt = updatedAt ?? "1970-01-01T00:00:00Z"
        self.entries = entries
    }
}

private struct PreferenceProfileLatestPointer: Codable, Equatable {
    let schemaVersion: String
    let profileVersion: String
    let updatedAt: String

    init(
        schemaVersion: String = "openstaff.learning.preference-profile-pointer.v0",
        profileVersion: String,
        updatedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.profileVersion = profileVersion
        self.updatedAt = updatedAt
    }
}
