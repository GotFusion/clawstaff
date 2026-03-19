import Foundation

public struct PreferencePromotionThreshold: Codable, Equatable, Sendable {
    public let minimumSignalCount: Int
    public let minimumSessionCount: Int
    public let minimumAverageConfidence: Double?
    public let requiresTeacherConfirmation: Bool
    public let requiresNoRecentRejection: Bool
    public let allowAutomaticPromotion: Bool

    public init(
        minimumSignalCount: Int,
        minimumSessionCount: Int,
        minimumAverageConfidence: Double? = nil,
        requiresTeacherConfirmation: Bool = false,
        requiresNoRecentRejection: Bool = false,
        allowAutomaticPromotion: Bool = true
    ) {
        self.minimumSignalCount = minimumSignalCount
        self.minimumSessionCount = minimumSessionCount
        self.minimumAverageConfidence = minimumAverageConfidence
        self.requiresTeacherConfirmation = requiresTeacherConfirmation
        self.requiresNoRecentRejection = requiresNoRecentRejection
        self.allowAutomaticPromotion = allowAutomaticPromotion
    }
}

public struct PreferencePromotionConfiguration: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let enabledScopeLevels: [PreferenceSignalScope]
    public let lowRisk: PreferencePromotionThreshold
    public let mediumRisk: PreferencePromotionThreshold
    public let highRisk: PreferencePromotionThreshold
    public let criticalRisk: PreferencePromotionThreshold

    public init(
        schemaVersion: String = "openstaff.learning.preference-promotion.v0",
        enabledScopeLevels: [PreferenceSignalScope],
        lowRisk: PreferencePromotionThreshold,
        mediumRisk: PreferencePromotionThreshold,
        highRisk: PreferencePromotionThreshold,
        criticalRisk: PreferencePromotionThreshold
    ) {
        self.schemaVersion = schemaVersion
        self.enabledScopeLevels = Self.normalizedScopeLevels(enabledScopeLevels)
        self.lowRisk = lowRisk
        self.mediumRisk = mediumRisk
        self.highRisk = highRisk
        self.criticalRisk = criticalRisk
    }

    public static let v0Default = PreferencePromotionPolicy.loadDefaultOrFallback().promotionConfiguration

    public func threshold(for riskLevel: InteractionTurnRiskLevel) -> PreferencePromotionThreshold {
        switch riskLevel {
        case .low:
            return lowRisk
        case .medium:
            return mediumRisk
        case .high:
            return highRisk
        case .critical:
            return criticalRisk
        }
    }

    public func isScopeEnabled(_ scope: PreferenceSignalScopeReference) -> Bool {
        enabledScopeLevels.contains(scope.level)
    }

    private static func normalizedScopeLevels(_ scopeLevels: [PreferenceSignalScope]) -> [PreferenceSignalScope] {
        Array(Set(scopeLevels)).sorted { $0.rawValue < $1.rawValue }
    }
}

public enum PreferenceRuleAutoExecutionPolicy: String, Codable, CaseIterable, Sendable {
    case inheritSafetyInterlocks
    case disabled
    case requiresTeacherConfirmation
}

public enum PreferenceConflictPriority: String, Codable, CaseIterable, Sendable {
    case activeRulePreferred
    case moreSpecificScope
    case recentTeacherConfirmation
    case lowerRisk
    case moreRecentlyUpdated
    case stableRuleIdTieBreak

    static func normalized(_ values: [PreferenceConflictPriority]) -> [PreferenceConflictPriority] {
        var ordered: [PreferenceConflictPriority] = []
        var seen = Set<String>()
        for value in values + Self.allCases {
            if seen.insert(value.rawValue).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }
}

public struct PreferenceRiskGovernancePolicy: Codable, Equatable, Sendable {
    public let promotionThreshold: PreferencePromotionThreshold
    public let autoExecutionPolicy: PreferenceRuleAutoExecutionPolicy

    public init(
        promotionThreshold: PreferencePromotionThreshold,
        autoExecutionPolicy: PreferenceRuleAutoExecutionPolicy
    ) {
        self.promotionThreshold = promotionThreshold
        self.autoExecutionPolicy = autoExecutionPolicy
    }

    public var candidateOnly: Bool {
        !promotionThreshold.allowAutomaticPromotion
    }
}

public struct PreferenceRiskGovernancePolicies: Codable, Equatable, Sendable {
    public let low: PreferenceRiskGovernancePolicy
    public let medium: PreferenceRiskGovernancePolicy
    public let high: PreferenceRiskGovernancePolicy
    public let critical: PreferenceRiskGovernancePolicy

    public init(
        low: PreferenceRiskGovernancePolicy,
        medium: PreferenceRiskGovernancePolicy,
        high: PreferenceRiskGovernancePolicy,
        critical: PreferenceRiskGovernancePolicy
    ) {
        self.low = low
        self.medium = medium
        self.high = high
        self.critical = critical
    }

    public func policy(for riskLevel: InteractionTurnRiskLevel) -> PreferenceRiskGovernancePolicy {
        switch riskLevel {
        case .low:
            return low
        case .medium:
            return medium
        case .high:
            return high
        case .critical:
            return critical
        }
    }
}

public struct PreferenceSignalTypeGovernancePolicy: Codable, Equatable, Sendable {
    public let allowedScopeLevels: [PreferenceSignalScope]
    public let expiresAfterDays: Int?
    public let notes: [String]

    public init(
        allowedScopeLevels: [PreferenceSignalScope],
        expiresAfterDays: Int? = nil,
        notes: [String] = []
    ) {
        self.allowedScopeLevels = Array(Set(allowedScopeLevels)).sorted { $0.rawValue < $1.rawValue }
        self.expiresAfterDays = expiresAfterDays
        self.notes = notes
    }

    public func allows(_ scopeLevel: PreferenceSignalScope) -> Bool {
        allowedScopeLevels.contains(scopeLevel)
    }
}

public struct PreferenceSignalTypeGovernancePolicies: Codable, Equatable, Sendable {
    public let outcome: PreferenceSignalTypeGovernancePolicy
    public let procedure: PreferenceSignalTypeGovernancePolicy
    public let locator: PreferenceSignalTypeGovernancePolicy
    public let style: PreferenceSignalTypeGovernancePolicy
    public let risk: PreferenceSignalTypeGovernancePolicy
    public let repair: PreferenceSignalTypeGovernancePolicy

    public init(
        outcome: PreferenceSignalTypeGovernancePolicy,
        procedure: PreferenceSignalTypeGovernancePolicy,
        locator: PreferenceSignalTypeGovernancePolicy,
        style: PreferenceSignalTypeGovernancePolicy,
        risk: PreferenceSignalTypeGovernancePolicy,
        repair: PreferenceSignalTypeGovernancePolicy
    ) {
        self.outcome = outcome
        self.procedure = procedure
        self.locator = locator
        self.style = style
        self.risk = risk
        self.repair = repair
    }

    public func policy(for signalType: PreferenceSignalType) -> PreferenceSignalTypeGovernancePolicy {
        switch signalType {
        case .outcome:
            return outcome
        case .procedure:
            return procedure
        case .locator:
            return locator
        case .style:
            return style
        case .risk:
            return risk
        case .repair:
            return repair
        }
    }
}

public struct PreferenceRuleGovernance: Codable, Equatable, Sendable {
    public let policySchemaVersion: String
    public let autoExecutionPolicy: PreferenceRuleAutoExecutionPolicy
    public let allowedScopeLevels: [PreferenceSignalScope]
    public let expiresAfterDays: Int?
    public let expiresAt: String?
    public let notes: [String]

    public init(
        policySchemaVersion: String,
        autoExecutionPolicy: PreferenceRuleAutoExecutionPolicy,
        allowedScopeLevels: [PreferenceSignalScope],
        expiresAfterDays: Int? = nil,
        expiresAt: String? = nil,
        notes: [String] = []
    ) {
        self.policySchemaVersion = policySchemaVersion
        self.autoExecutionPolicy = autoExecutionPolicy
        self.allowedScopeLevels = Array(Set(allowedScopeLevels)).sorted { $0.rawValue < $1.rawValue }
        self.expiresAfterDays = expiresAfterDays
        self.expiresAt = expiresAt
        self.notes = notes
    }

    public func materialized(at timestamp: String) -> Self {
        let expiresAt = Self.expirationTimestamp(from: timestamp, expiresAfterDays: expiresAfterDays)
        return Self(
            policySchemaVersion: policySchemaVersion,
            autoExecutionPolicy: autoExecutionPolicy,
            allowedScopeLevels: allowedScopeLevels,
            expiresAfterDays: expiresAfterDays,
            expiresAt: expiresAt,
            notes: notes
        )
    }

    private static func expirationTimestamp(from timestamp: String, expiresAfterDays: Int?) -> String? {
        guard let expiresAfterDays,
              let timestampDate = parseISO8601(timestamp) else {
            return nil
        }
        guard let expiresAt = Calendar(identifier: .gregorian).date(
            byAdding: .day,
            value: expiresAfterDays,
            to: timestampDate
        ) else {
            return nil
        }
        return iso8601String(from: expiresAt)
    }

    private static func parseISO8601(_ value: String) -> Date? {
        if let date = makeFormatter(withFractionalSeconds: true).date(from: value) {
            return date
        }
        return makeFormatter(withFractionalSeconds: false).date(from: value)
    }

    private static func iso8601String(from date: Date) -> String {
        makeFormatter(withFractionalSeconds: false).string(from: date)
    }

    private static func makeFormatter(withFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = withFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

public struct PreferenceRuleGovernanceDecision: Codable, Equatable, Sendable {
    public let scopeAllowed: Bool
    public let candidateOnly: Bool
    public let governance: PreferenceRuleGovernance

    public init(
        scopeAllowed: Bool,
        candidateOnly: Bool,
        governance: PreferenceRuleGovernance
    ) {
        self.scopeAllowed = scopeAllowed
        self.candidateOnly = candidateOnly
        self.governance = governance
    }
}

public struct PreferencePromotionPolicy: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let enabledScopeLevels: [PreferenceSignalScope]
    public let conflictPriority: [PreferenceConflictPriority]
    public let riskPolicies: PreferenceRiskGovernancePolicies
    public let signalTypePolicies: PreferenceSignalTypeGovernancePolicies

    public init(
        schemaVersion: String = "openstaff.learning.preference-governance.v0",
        enabledScopeLevels: [PreferenceSignalScope],
        conflictPriority: [PreferenceConflictPriority],
        riskPolicies: PreferenceRiskGovernancePolicies,
        signalTypePolicies: PreferenceSignalTypeGovernancePolicies
    ) {
        self.schemaVersion = schemaVersion
        self.enabledScopeLevels = Array(Set(enabledScopeLevels)).sorted { $0.rawValue < $1.rawValue }
        self.conflictPriority = PreferenceConflictPriority.normalized(conflictPriority)
        self.riskPolicies = riskPolicies
        self.signalTypePolicies = signalTypePolicies
    }

    public static let v0Default = Self(
        enabledScopeLevels: [.global, .app, .taskFamily],
        conflictPriority: [
            .activeRulePreferred,
            .moreSpecificScope,
            .recentTeacherConfirmation,
            .lowerRisk,
            .moreRecentlyUpdated,
            .stableRuleIdTieBreak
        ],
        riskPolicies: PreferenceRiskGovernancePolicies(
            low: PreferenceRiskGovernancePolicy(
                promotionThreshold: PreferencePromotionThreshold(
                    minimumSignalCount: 3,
                    minimumSessionCount: 2,
                    minimumAverageConfidence: 0.75
                ),
                autoExecutionPolicy: .inheritSafetyInterlocks
            ),
            medium: PreferenceRiskGovernancePolicy(
                promotionThreshold: PreferencePromotionThreshold(
                    minimumSignalCount: 4,
                    minimumSessionCount: 3,
                    requiresNoRecentRejection: true
                ),
                autoExecutionPolicy: .disabled
            ),
            high: PreferenceRiskGovernancePolicy(
                promotionThreshold: PreferencePromotionThreshold(
                    minimumSignalCount: 1,
                    minimumSessionCount: 1,
                    requiresTeacherConfirmation: true,
                    requiresNoRecentRejection: true
                ),
                autoExecutionPolicy: .requiresTeacherConfirmation
            ),
            critical: PreferenceRiskGovernancePolicy(
                promotionThreshold: PreferencePromotionThreshold(
                    minimumSignalCount: 1,
                    minimumSessionCount: 1,
                    requiresTeacherConfirmation: true,
                    requiresNoRecentRejection: true,
                    allowAutomaticPromotion: false
                ),
                autoExecutionPolicy: .disabled
            )
        ),
        signalTypePolicies: PreferenceSignalTypeGovernancePolicies(
            outcome: PreferenceSignalTypeGovernancePolicy(
                allowedScopeLevels: [.app, .taskFamily],
                expiresAfterDays: 45,
                notes: [
                    "Outcome preferences stay local to app or task family because success criteria drift with workflow changes."
                ]
            ),
            procedure: PreferenceSignalTypeGovernancePolicy(
                allowedScopeLevels: [.app, .taskFamily, .skillFamily],
                expiresAfterDays: 90,
                notes: [
                    "Procedure preferences should stay attached to app or task context instead of becoming global habits."
                ]
            ),
            locator: PreferenceSignalTypeGovernancePolicy(
                allowedScopeLevels: [.app, .taskFamily, .skillFamily, .windowPattern],
                expiresAfterDays: 30,
                notes: [
                    "Locator preferences are UI-fragile and must remain local with an expiration window."
                ]
            ),
            style: PreferenceSignalTypeGovernancePolicy(
                allowedScopeLevels: [.global, .app, .taskFamily],
                notes: [
                    "Style preferences can be global when repeatedly reinforced across apps."
                ]
            ),
            risk: PreferenceSignalTypeGovernancePolicy(
                allowedScopeLevels: [.global, .app, .taskFamily],
                notes: [
                    "Risk preferences may stay broad, but execution is still constrained by risk-tier auto-execution policy."
                ]
            ),
            repair: PreferenceSignalTypeGovernancePolicy(
                allowedScopeLevels: [.app, .taskFamily, .skillFamily, .windowPattern],
                expiresAfterDays: 30,
                notes: [
                    "Repair preferences are tied to concrete UI drift and should expire unless re-confirmed."
                ]
            )
        )
    )

    public var promotionConfiguration: PreferencePromotionConfiguration {
        PreferencePromotionConfiguration(
            enabledScopeLevels: enabledScopeLevels,
            lowRisk: riskPolicies.low.promotionThreshold,
            mediumRisk: riskPolicies.medium.promotionThreshold,
            highRisk: riskPolicies.high.promotionThreshold,
            criticalRisk: riskPolicies.critical.promotionThreshold
        )
    }

    public func governanceDecision(
        signalType: PreferenceSignalType,
        riskLevel: InteractionTurnRiskLevel,
        scope: PreferenceSignalScopeReference?
    ) -> PreferenceRuleGovernanceDecision {
        let riskPolicy = riskPolicies.policy(for: riskLevel)
        let signalTypePolicy = signalTypePolicies.policy(for: signalType)
        let scopeAllowed = scope.map { signalTypePolicy.allows($0.level) } ?? true

        return PreferenceRuleGovernanceDecision(
            scopeAllowed: scopeAllowed,
            candidateOnly: riskPolicy.candidateOnly,
            governance: PreferenceRuleGovernance(
                policySchemaVersion: schemaVersion,
                autoExecutionPolicy: riskPolicy.autoExecutionPolicy,
                allowedScopeLevels: signalTypePolicy.allowedScopeLevels,
                expiresAfterDays: signalTypePolicy.expiresAfterDays,
                notes: signalTypePolicy.notes
            )
        )
    }

    public func replacingPromotionConfiguration(
        _ configuration: PreferencePromotionConfiguration
    ) -> Self {
        Self(
            schemaVersion: schemaVersion,
            enabledScopeLevels: configuration.enabledScopeLevels,
            conflictPriority: conflictPriority,
            riskPolicies: PreferenceRiskGovernancePolicies(
                low: PreferenceRiskGovernancePolicy(
                    promotionThreshold: configuration.lowRisk,
                    autoExecutionPolicy: riskPolicies.low.autoExecutionPolicy
                ),
                medium: PreferenceRiskGovernancePolicy(
                    promotionThreshold: configuration.mediumRisk,
                    autoExecutionPolicy: riskPolicies.medium.autoExecutionPolicy
                ),
                high: PreferenceRiskGovernancePolicy(
                    promotionThreshold: configuration.highRisk,
                    autoExecutionPolicy: riskPolicies.high.autoExecutionPolicy
                ),
                critical: PreferenceRiskGovernancePolicy(
                    promotionThreshold: configuration.criticalRisk,
                    autoExecutionPolicy: riskPolicies.critical.autoExecutionPolicy
                )
            ),
            signalTypePolicies: signalTypePolicies
        )
    }

    public static func loadDefaultOrFallback(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self {
        guard let url = defaultPolicyURL(fileManager: fileManager, environment: environment),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else {
            return .v0Default
        }
        return decoded
    }

    public static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private static func defaultPolicyURL(
        fileManager: FileManager,
        environment: [String: String]
    ) -> URL? {
        if let override = environment["OPENSTAFF_PREFERENCE_GOVERNANCE_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: false)
        }

        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if let found = searchUpward(from: currentDirectoryURL, fileManager: fileManager) {
            return found
        }

        let sourceURL = URL(fileURLWithPath: #filePath, isDirectory: false).deletingLastPathComponent()
        return searchUpward(from: sourceURL, fileManager: fileManager)
    }

    private static func searchUpward(
        from startURL: URL,
        fileManager: FileManager
    ) -> URL? {
        var cursor = startURL
        for _ in 0..<8 {
            let candidate = cursor.appendingPathComponent("config/preference-governance.yaml", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path {
                break
            }
            cursor = parent
        }
        return nil
    }
}
