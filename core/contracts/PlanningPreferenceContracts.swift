import Foundation

public enum StudentExecutionStyle: String, Codable, CaseIterable, Sendable {
    case conservative
    case assertive
}

public enum StudentFailureRecoveryPreference: String, Codable, CaseIterable, Sendable {
    case repairBeforeReteach
    case reteachBeforeRepair
}

public struct StudentPlanningRuleHit: Codable, Equatable, Sendable {
    public let ruleId: String
    public let signalType: PreferenceSignalType
    public let scopeLevel: PreferenceSignalScope
    public let matchScore: Double
    public let scoreDelta: Double
    public let explanation: String

    public init(
        ruleId: String,
        signalType: PreferenceSignalType,
        scopeLevel: PreferenceSignalScope,
        matchScore: Double,
        scoreDelta: Double,
        explanation: String
    ) {
        self.ruleId = ruleId
        self.signalType = signalType
        self.scopeLevel = scopeLevel
        self.matchScore = matchScore
        self.scoreDelta = scoreDelta
        self.explanation = explanation
    }
}

public struct StudentPlanningPreferenceDecision: Codable, Equatable, Sendable {
    public let profileVersion: String
    public let selectedKnowledgeItemId: String
    public let executionStyle: StudentExecutionStyle
    public let failureRecoveryPreference: StudentFailureRecoveryPreference
    public let appliedRuleIds: [String]
    public let ruleHits: [StudentPlanningRuleHit]
    public let summary: String

    public init(
        profileVersion: String,
        selectedKnowledgeItemId: String,
        executionStyle: StudentExecutionStyle,
        failureRecoveryPreference: StudentFailureRecoveryPreference,
        appliedRuleIds: [String],
        ruleHits: [StudentPlanningRuleHit],
        summary: String
    ) {
        self.profileVersion = profileVersion
        self.selectedKnowledgeItemId = selectedKnowledgeItemId
        self.executionStyle = executionStyle
        self.failureRecoveryPreference = failureRecoveryPreference
        self.appliedRuleIds = Array(Set(appliedRuleIds)).sorted()
        self.ruleHits = ruleHits.sorted(by: Self.ruleHitSort)
        self.summary = summary
    }

    static func ruleHitSort(
        lhs: StudentPlanningRuleHit,
        rhs: StudentPlanningRuleHit
    ) -> Bool {
        let lhsMagnitude = abs(lhs.scoreDelta)
        let rhsMagnitude = abs(rhs.scoreDelta)
        if lhsMagnitude == rhsMagnitude {
            return lhs.ruleId < rhs.ruleId
        }
        return lhsMagnitude > rhsMagnitude
    }
}
