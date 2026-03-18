import Foundation

public enum PreferenceSignalType: String, Codable, CaseIterable, Sendable {
    case outcome
    case procedure
    case locator
    case style
    case risk
    case repair
}

public enum PreferenceSignalPolarity: String, Codable, CaseIterable, Sendable {
    case reinforce
    case discourage
    case neutral
}

public enum PreferenceSignalScope: String, Codable, CaseIterable, Sendable {
    case global
    case app
    case taskFamily
    case skillFamily
    case windowPattern

    public var isEnabledByDefaultInV0: Bool {
        switch self {
        case .global, .app, .taskFamily:
            return true
        case .skillFamily, .windowPattern:
            return false
        }
    }
}

public enum PreferenceSignalPromotionStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case confirmed
    case rejected
    case superseded
}

public enum PreferenceSignalEvaluativeDecision: String, Codable, CaseIterable, Sendable {
    case pass
    case fail
    case neutral
}

public struct PreferenceSignalScopeReference: Codable, Equatable, Sendable {
    public let level: PreferenceSignalScope
    public let appBundleId: String?
    public let appName: String?
    public let taskFamily: String?
    public let skillFamily: String?
    public let windowPattern: String?

    public init(
        level: PreferenceSignalScope,
        appBundleId: String? = nil,
        appName: String? = nil,
        taskFamily: String? = nil,
        skillFamily: String? = nil,
        windowPattern: String? = nil
    ) {
        self.level = level
        self.appBundleId = appBundleId
        self.appName = appName
        self.taskFamily = taskFamily
        self.skillFamily = skillFamily
        self.windowPattern = windowPattern
    }

    public static func global() -> Self {
        Self(level: .global)
    }

    public static func app(bundleId: String, appName: String? = nil) -> Self {
        Self(level: .app, appBundleId: bundleId, appName: appName)
    }

    public static func taskFamily(_ taskFamily: String) -> Self {
        Self(level: .taskFamily, taskFamily: taskFamily)
    }

    public static func skillFamily(_ skillFamily: String) -> Self {
        Self(level: .skillFamily, skillFamily: skillFamily)
    }

    public static func windowPattern(
        _ windowPattern: String,
        appBundleId: String? = nil,
        appName: String? = nil
    ) -> Self {
        Self(
            level: .windowPattern,
            appBundleId: appBundleId,
            appName: appName,
            windowPattern: windowPattern
        )
    }

    public var isEnabledByDefaultInV0: Bool {
        level.isEnabledByDefaultInV0
    }
}

public struct PreferenceSignal: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let signalId: String
    public let turnId: String
    public let traceId: String?
    public let sessionId: String
    public let taskId: String
    public let stepId: String
    public let type: PreferenceSignalType
    public let evaluativeDecision: PreferenceSignalEvaluativeDecision
    public let polarity: PreferenceSignalPolarity
    public let scope: PreferenceSignalScopeReference
    public let hint: String?
    public let confidence: Double
    public let evidenceIds: [String]
    public let proposedAction: String?
    public let promotionStatus: PreferenceSignalPromotionStatus
    public let timestamp: String

    public init(
        schemaVersion: String = "openstaff.learning.preference-signal.v0",
        signalId: String,
        turnId: String,
        traceId: String? = nil,
        sessionId: String,
        taskId: String,
        stepId: String,
        type: PreferenceSignalType,
        evaluativeDecision: PreferenceSignalEvaluativeDecision,
        polarity: PreferenceSignalPolarity,
        scope: PreferenceSignalScopeReference,
        hint: String? = nil,
        confidence: Double,
        evidenceIds: [String],
        proposedAction: String? = nil,
        promotionStatus: PreferenceSignalPromotionStatus,
        timestamp: String
    ) {
        self.schemaVersion = schemaVersion
        self.signalId = signalId
        self.turnId = turnId
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.stepId = stepId
        self.type = type
        self.evaluativeDecision = evaluativeDecision
        self.polarity = polarity
        self.scope = scope
        self.hint = hint
        self.confidence = confidence
        self.evidenceIds = evidenceIds
        self.proposedAction = proposedAction
        self.promotionStatus = promotionStatus
        self.timestamp = timestamp
    }

    public var hasDirectivePayload: Bool {
        guard let hint, let proposedAction else {
            return false
        }

        return !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !proposedAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isEnabledByDefaultInV0: Bool {
        scope.isEnabledByDefaultInV0
    }
}
