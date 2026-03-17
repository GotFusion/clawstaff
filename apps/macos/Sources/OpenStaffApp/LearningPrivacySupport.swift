import Foundation

struct LearningPrivacyConfiguration: Codable, Equatable, Sendable {
    static let schemaVersion = "openstaff.learning-privacy.v1"
    static let temporaryPauseDuration: TimeInterval = 15 * 60

    var schemaVersionValue: String
    var excludedApps: [LearningPrivacyAppExclusion]
    var excludedWindowTitleRules: [LearningWindowTitleExclusionRule]
    var temporaryPauseUntil: Date?
    var sensitiveSceneAutoMuteEnabled: Bool
    var enabledSensitiveSceneRuleIds: [String]

    init(
        schemaVersionValue: String = LearningPrivacyConfiguration.schemaVersion,
        excludedApps: [LearningPrivacyAppExclusion] = [],
        excludedWindowTitleRules: [LearningWindowTitleExclusionRule] = [],
        temporaryPauseUntil: Date? = nil,
        sensitiveSceneAutoMuteEnabled: Bool = true,
        enabledSensitiveSceneRuleIds: [String] = SensitiveScenePolicy.defaultEnabledRuleIds
    ) {
        self.schemaVersionValue = schemaVersionValue
        self.excludedApps = excludedApps
        self.excludedWindowTitleRules = excludedWindowTitleRules
        self.temporaryPauseUntil = temporaryPauseUntil
        self.sensitiveSceneAutoMuteEnabled = sensitiveSceneAutoMuteEnabled
        self.enabledSensitiveSceneRuleIds = enabledSensitiveSceneRuleIds
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersionValue = "schemaVersion"
        case excludedApps
        case excludedWindowTitleRules
        case temporaryPauseUntil
        case sensitiveSceneAutoMuteEnabled
        case enabledSensitiveSceneRuleIds
    }

    static let `default` = LearningPrivacyConfiguration()

    func normalized(referenceDate: Date) -> LearningPrivacyConfiguration {
        LearningPrivacyConfiguration(
            schemaVersionValue: Self.schemaVersion,
            excludedApps: deduplicatedApps(excludedApps),
            excludedWindowTitleRules: deduplicatedWindowRules(excludedWindowTitleRules),
            temporaryPauseUntil: normalizedTemporaryPause(referenceDate: referenceDate),
            sensitiveSceneAutoMuteEnabled: sensitiveSceneAutoMuteEnabled,
            enabledSensitiveSceneRuleIds: deduplicatedStrings(enabledSensitiveSceneRuleIds)
        )
    }

    func isTemporaryPauseActive(at date: Date) -> Bool {
        guard let temporaryPauseUntil else {
            return false
        }
        return temporaryPauseUntil > date
    }

    var effectiveEnabledSensitiveSceneRuleIds: [String] {
        guard sensitiveSceneAutoMuteEnabled else {
            return []
        }

        let configured = deduplicatedStrings(enabledSensitiveSceneRuleIds)
        if configured.isEmpty {
            return SensitiveScenePolicy.defaultEnabledRuleIds
        }
        return configured
    }

    func isSensitiveSceneEnabled(_ ruleId: String) -> Bool {
        let normalizedRuleId = Self.normalizedValue(ruleId)
        return effectiveEnabledSensitiveSceneRuleIds.contains {
            Self.normalizedValue($0) == normalizedRuleId
        }
    }

    private func normalizedTemporaryPause(referenceDate: Date) -> Date? {
        guard let temporaryPauseUntil else {
            return nil
        }
        return temporaryPauseUntil > referenceDate ? temporaryPauseUntil : nil
    }

    private func deduplicatedApps(
        _ items: [LearningPrivacyAppExclusion]
    ) -> [LearningPrivacyAppExclusion] {
        var ordered: [LearningPrivacyAppExclusion] = []
        var seen = Set<String>()
        for item in items {
            let normalized = item.normalized()
            let key = "\(Self.normalizedValue(normalized.bundleId))#\(Self.normalizedValue(normalized.appName))"
            guard !key.replacingOccurrences(of: "#", with: "").isEmpty else {
                continue
            }
            if seen.insert(key).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    private func deduplicatedWindowRules(
        _ items: [LearningWindowTitleExclusionRule]
    ) -> [LearningWindowTitleExclusionRule] {
        var ordered: [LearningWindowTitleExclusionRule] = []
        var seen = Set<String>()
        for item in items {
            let normalized = item.normalized()
            let key = "\(normalized.matchType.rawValue)#\(Self.normalizedValue(normalized.pattern))"
            guard !Self.normalizedValue(normalized.pattern).isEmpty else {
                continue
            }
            if seen.insert(key).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    private func deduplicatedStrings(_ values: [String]) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()
        for value in values {
            let normalized = Self.normalizedValue(value)
            guard !normalized.isEmpty else {
                continue
            }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }

    private static func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct LearningPrivacyAppExclusion: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var bundleId: String
    var appName: String

    init(
        id: String? = nil,
        displayName: String = "",
        bundleId: String = "",
        appName: String = ""
    ) {
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBundleId = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? Self.makeIdentifier(bundleId: normalizedBundleId, appName: normalizedAppName)
        self.displayName = normalizedDisplayName
        self.bundleId = normalizedBundleId
        self.appName = normalizedAppName
    }

    var resolvedDisplayName: String {
        if !displayName.isEmpty {
            return displayName
        }
        if !appName.isEmpty {
            return appName
        }
        if !bundleId.isEmpty {
            return bundleId
        }
        return "未命名 app 规则"
    }

    func normalized() -> LearningPrivacyAppExclusion {
        LearningPrivacyAppExclusion(
            id: id,
            displayName: displayName,
            bundleId: bundleId,
            appName: appName
        )
    }

    private static func makeIdentifier(bundleId: String, appName: String) -> String {
        let normalizedBundleId = sanitizeIdentifier(bundleId)
        if !normalizedBundleId.isEmpty {
            return "app.\(normalizedBundleId)"
        }

        let normalizedAppName = sanitizeIdentifier(appName)
        if !normalizedAppName.isEmpty {
            return "app.\(normalizedAppName)"
        }

        return "app.\(UUID().uuidString.lowercased())"
    }

    private static func sanitizeIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "--", with: "-")
    }
}

enum LearningWindowTitleMatchType: String, Codable, CaseIterable, Sendable {
    case contains
    case regex

    var displayName: String {
        switch self {
        case .contains:
            return "包含"
        case .regex:
            return "正则"
        }
    }
}

struct LearningWindowTitleExclusionRule: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var pattern: String
    var matchType: LearningWindowTitleMatchType

    init(
        id: String? = nil,
        displayName: String = "",
        pattern: String,
        matchType: LearningWindowTitleMatchType = .contains
    ) {
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id ?? Self.makeIdentifier(pattern: normalizedPattern, matchType: matchType)
        self.displayName = normalizedDisplayName
        self.pattern = normalizedPattern
        self.matchType = matchType
    }

    var resolvedDisplayName: String {
        if !displayName.isEmpty {
            return displayName
        }
        switch matchType {
        case .contains:
            return "窗口标题包含 “\(pattern)”"
        case .regex:
            return "窗口标题匹配正则 “\(pattern)”"
        }
    }

    func normalized() -> LearningWindowTitleExclusionRule {
        LearningWindowTitleExclusionRule(
            id: id,
            displayName: displayName,
            pattern: pattern,
            matchType: matchType
        )
    }

    private static func makeIdentifier(
        pattern: String,
        matchType: LearningWindowTitleMatchType
    ) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let fragment = pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .prefix(48)
        if fragment.isEmpty {
            return "window.\(matchType.rawValue).\(UUID().uuidString.lowercased())"
        }
        return "window.\(matchType.rawValue).\(fragment)"
    }
}

protocol LearningPrivacyConfigurationStoring {
    var configurationURL: URL { get }
    func load() -> LearningPrivacyConfiguration
    func save(_ configuration: LearningPrivacyConfiguration) throws
}

struct FileLearningPrivacyConfigurationStore: LearningPrivacyConfigurationStoring {
    let configurationURL: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.configurationURL = Self.resolveConfigurationURL(
            fileManager: fileManager,
            environment: environment
        )
    }

    func load() -> LearningPrivacyConfiguration {
        guard fileManager.fileExists(atPath: configurationURL.path) else {
            return .default
        }

        guard let data = try? Data(contentsOf: configurationURL) else {
            return .default
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let stringValue = try? container.decode(String.self),
               let date = OpenStaffDateFormatter.date(from: stringValue) {
                return date
            }
            if let timestamp = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: timestamp)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date in learning privacy configuration."
            )
        }

        guard let configuration = try? decoder.decode(LearningPrivacyConfiguration.self, from: data) else {
            return .default
        }
        return configuration
    }

    func save(_ configuration: LearningPrivacyConfiguration) throws {
        try fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(OpenStaffDateFormatter.iso8601String(from: date))
        }

        let data = try encoder.encode(configuration)
        var normalizedData = data
        normalizedData.append(0x0A)
        try normalizedData.write(to: configurationURL, options: [.atomic])
    }

    private static func resolveConfigurationURL(
        fileManager: FileManager,
        environment: [String: String]
    ) -> URL {
        if let override = environment["OPENSTAFF_LEARNING_PRIVACY_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: false)
        }

        let trackedConfigurationURL = OpenStaffWorkspacePaths.configDirectory
            .appendingPathComponent("learning-privacy.yaml", isDirectory: false)
        if fileManager.fileExists(atPath: trackedConfigurationURL.path) {
            return trackedConfigurationURL
        }

        return OpenStaffWorkspacePaths.runtimeDirectory
            .appendingPathComponent("learning-privacy.json", isDirectory: false)
    }
}

extension OpenStaffWorkspacePaths {
    static var configDirectory: URL {
        repositoryRoot.appendingPathComponent("config", isDirectory: true)
    }
}
