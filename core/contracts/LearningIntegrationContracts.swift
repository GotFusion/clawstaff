import Foundation

public enum LearningHookEventName: String, Codable, CaseIterable, Sendable {
    case learningTurnCreated = "learning.turn.created"
    case learningSignalExtracted = "learning.signal.extracted"
    case preferenceRulePromoted = "preference.rule.promoted"
    case preferenceProfileUpdated = "preference.profile.updated"
}

public struct LearningHookEventMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let eventId: String
    public let eventName: LearningHookEventName
    public let emittedAt: String
    public let producer: String
    public let traceId: String?
    public let sessionId: String?
    public let taskId: String?

    public init(
        schemaVersion: String = "openstaff.learning.hook-envelope.v0",
        eventId: String,
        eventName: LearningHookEventName,
        emittedAt: String,
        producer: String,
        traceId: String? = nil,
        sessionId: String? = nil,
        taskId: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.eventName = eventName
        self.emittedAt = emittedAt
        self.producer = producer
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
    }
}

public struct LearningHookEnvelope<Payload: Codable & Equatable>: Codable, Equatable {
    public let metadata: LearningHookEventMetadata
    public let payload: Payload

    public init(
        metadata: LearningHookEventMetadata,
        payload: Payload
    ) {
        self.metadata = metadata
        self.payload = payload
    }
}

public struct LearningTurnCreatedHookPayload: Codable, Equatable {
    public let turn: InteractionTurn

    public init(turn: InteractionTurn) {
        self.turn = turn
    }
}

public struct LearningSignalExtractedHookPayload: Codable, Equatable {
    public let signal: PreferenceSignal

    public init(signal: PreferenceSignal) {
        self.signal = signal
    }
}

public struct PreferenceRulePromotedHookPayload: Codable, Equatable {
    public let rule: PreferenceRule

    public init(rule: PreferenceRule) {
        self.rule = rule
    }
}

public struct PreferenceProfileUpdatedHookPayload: Codable, Equatable {
    public let profileSnapshot: PreferenceProfileSnapshot

    public init(profileSnapshot: PreferenceProfileSnapshot) {
        self.profileSnapshot = profileSnapshot
    }
}

public typealias LearningTurnCreatedHookEvent = LearningHookEnvelope<LearningTurnCreatedHookPayload>
public typealias LearningSignalExtractedHookEvent = LearningHookEnvelope<LearningSignalExtractedHookPayload>
public typealias PreferenceRulePromotedHookEvent = LearningHookEnvelope<PreferenceRulePromotedHookPayload>
public typealias PreferenceProfileUpdatedHookEvent = LearningHookEnvelope<PreferenceProfileUpdatedHookPayload>

public protocol LearningHookConsuming {
    func consume(_ event: LearningTurnCreatedHookEvent) throws
    func consume(_ event: LearningSignalExtractedHookEvent) throws
    func consume(_ event: PreferenceRulePromotedHookEvent) throws
    func consume(_ event: PreferenceProfileUpdatedHookEvent) throws
}

public enum LearningGatewayMethod: String, Codable, CaseIterable, Sendable {
    case preferencesListRules = "preferences.listRules"
    case preferencesListAssemblyDecisions = "preferences.listAssemblyDecisions"
    case preferencesExportBundle = "preferences.exportBundle"
}

public struct LearningGatewayRuleFilter: Codable, Equatable, Sendable {
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
}

public struct PreferencesListRulesRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let method: LearningGatewayMethod
    public let filter: LearningGatewayRuleFilter
    public let includeLatestProfileSnapshot: Bool

    public init(
        schemaVersion: String = "openstaff.learning.gateway.preferences-list-rules.request.v0",
        method: LearningGatewayMethod = .preferencesListRules,
        filter: LearningGatewayRuleFilter = LearningGatewayRuleFilter(),
        includeLatestProfileSnapshot: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.method = method
        self.filter = filter
        self.includeLatestProfileSnapshot = includeLatestProfileSnapshot
    }
}

public struct PreferencesListRulesResponse: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let method: LearningGatewayMethod
    public let generatedAt: String
    public let rules: [PreferenceRule]
    public let latestProfileSnapshot: PreferenceProfileSnapshot?

    public init(
        schemaVersion: String = "openstaff.learning.gateway.preferences-list-rules.response.v0",
        method: LearningGatewayMethod = .preferencesListRules,
        generatedAt: String,
        rules: [PreferenceRule],
        latestProfileSnapshot: PreferenceProfileSnapshot?
    ) {
        self.schemaVersion = schemaVersion
        self.method = method
        self.generatedAt = generatedAt
        self.rules = rules
        self.latestProfileSnapshot = latestProfileSnapshot
    }
}

public struct LearningGatewayAssemblyDecisionFilter: Codable, Equatable, Sendable {
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

public struct PreferencesListAssemblyDecisionsRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let method: LearningGatewayMethod
    public let filter: LearningGatewayAssemblyDecisionFilter
    public let includeLatestProfileSnapshot: Bool

    public init(
        schemaVersion: String = "openstaff.learning.gateway.preferences-list-assembly-decisions.request.v0",
        method: LearningGatewayMethod = .preferencesListAssemblyDecisions,
        filter: LearningGatewayAssemblyDecisionFilter = LearningGatewayAssemblyDecisionFilter(),
        includeLatestProfileSnapshot: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.method = method
        self.filter = filter
        self.includeLatestProfileSnapshot = includeLatestProfileSnapshot
    }
}

public struct PreferencesListAssemblyDecisionsResponse: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let method: LearningGatewayMethod
    public let generatedAt: String
    public let decisions: [PolicyAssemblyDecision]
    public let latestProfileSnapshot: PreferenceProfileSnapshot?

    public init(
        schemaVersion: String = "openstaff.learning.gateway.preferences-list-assembly-decisions.response.v0",
        method: LearningGatewayMethod = .preferencesListAssemblyDecisions,
        generatedAt: String,
        decisions: [PolicyAssemblyDecision],
        latestProfileSnapshot: PreferenceProfileSnapshot?
    ) {
        self.schemaVersion = schemaVersion
        self.method = method
        self.generatedAt = generatedAt
        self.decisions = decisions
        self.latestProfileSnapshot = latestProfileSnapshot
    }
}

public struct LearningBundleExportFilter: Codable, Equatable, Sendable {
    public let sessionIds: [String]
    public let taskIds: [String]
    public let turnIds: [String]

    public init(
        sessionIds: [String] = [],
        taskIds: [String] = [],
        turnIds: [String] = []
    ) {
        self.sessionIds = Array(Set(sessionIds.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
        self.taskIds = Array(Set(taskIds.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
        self.turnIds = Array(Set(turnIds.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })).sorted()
    }
}

public struct PreferencesExportBundleRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let method: LearningGatewayMethod
    public let outputDirectoryPath: String
    public let bundleId: String?
    public let filter: LearningBundleExportFilter
    public let overwrite: Bool

    public init(
        schemaVersion: String = "openstaff.learning.gateway.preferences-export-bundle.request.v0",
        method: LearningGatewayMethod = .preferencesExportBundle,
        outputDirectoryPath: String,
        bundleId: String? = nil,
        filter: LearningBundleExportFilter = LearningBundleExportFilter(),
        overwrite: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.method = method
        self.outputDirectoryPath = outputDirectoryPath
        self.bundleId = bundleId
        self.filter = filter
        self.overwrite = overwrite
    }
}

public struct LearningBundleCategoryCount: Codable, Equatable, Sendable {
    public let files: Int
    public let records: Int

    public init(files: Int, records: Int) {
        self.files = files
        self.records = records
    }
}

public struct LearningBundleExportCounts: Codable, Equatable, Sendable {
    public let turns: LearningBundleCategoryCount
    public let evidence: LearningBundleCategoryCount
    public let signals: LearningBundleCategoryCount
    public let rules: LearningBundleCategoryCount
    public let profiles: LearningBundleCategoryCount
    public let audit: LearningBundleCategoryCount

    public init(
        turns: LearningBundleCategoryCount,
        evidence: LearningBundleCategoryCount,
        signals: LearningBundleCategoryCount,
        rules: LearningBundleCategoryCount,
        profiles: LearningBundleCategoryCount,
        audit: LearningBundleCategoryCount
    ) {
        self.turns = turns
        self.evidence = evidence
        self.signals = signals
        self.rules = rules
        self.profiles = profiles
        self.audit = audit
    }
}

public struct LearningBundleExportIndexes: Codable, Equatable, Sendable {
    public let turnIds: [String]
    public let evidenceIds: [String]
    public let signalIds: [String]
    public let ruleIds: [String]
    public let profileVersions: [String]
    public let auditIds: [String]
    public let latestProfileVersion: String?
    public let latestProfileUpdatedAt: String?

    public init(
        turnIds: [String],
        evidenceIds: [String],
        signalIds: [String],
        ruleIds: [String],
        profileVersions: [String],
        auditIds: [String],
        latestProfileVersion: String?,
        latestProfileUpdatedAt: String?
    ) {
        self.turnIds = turnIds
        self.evidenceIds = evidenceIds
        self.signalIds = signalIds
        self.ruleIds = ruleIds
        self.profileVersions = profileVersions
        self.auditIds = auditIds
        self.latestProfileVersion = latestProfileVersion
        self.latestProfileUpdatedAt = latestProfileUpdatedAt
    }
}

public struct LearningGatewayIssue: Codable, Equatable, Sendable {
    public let severity: String
    public let code: String
    public let message: String
    public let path: String?
    public let category: String?
    public let recordId: String?
    public let field: String?

    public init(
        severity: String,
        code: String,
        message: String,
        path: String? = nil,
        category: String? = nil,
        recordId: String? = nil,
        field: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.path = path
        self.category = category
        self.recordId = recordId
        self.field = field
    }
}

public struct PreferencesExportBundleResponse: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let method: LearningGatewayMethod
    public let bundleId: String
    public let bundlePath: String
    public let manifestPath: String
    public let verificationPath: String
    public let counts: LearningBundleExportCounts
    public let indexes: LearningBundleExportIndexes
    public let passed: Bool
    public let issues: [LearningGatewayIssue]

    public init(
        schemaVersion: String = "openstaff.learning.gateway.preferences-export-bundle.response.v0",
        method: LearningGatewayMethod = .preferencesExportBundle,
        bundleId: String,
        bundlePath: String,
        manifestPath: String,
        verificationPath: String,
        counts: LearningBundleExportCounts,
        indexes: LearningBundleExportIndexes,
        passed: Bool,
        issues: [LearningGatewayIssue]
    ) {
        self.schemaVersion = schemaVersion
        self.method = method
        self.bundleId = bundleId
        self.bundlePath = bundlePath
        self.manifestPath = manifestPath
        self.verificationPath = verificationPath
        self.counts = counts
        self.indexes = indexes
        self.passed = passed
        self.issues = issues
    }
}

public protocol LearningGatewayServing {
    func listRules(_ request: PreferencesListRulesRequest) throws -> PreferencesListRulesResponse
    func listAssemblyDecisions(
        _ request: PreferencesListAssemblyDecisionsRequest
    ) throws -> PreferencesListAssemblyDecisionsResponse
    func exportBundle(_ request: PreferencesExportBundleRequest) throws -> PreferencesExportBundleResponse
}
