import Foundation

public enum PolicyAssemblyTargetModule: String, Codable, CaseIterable, Sendable {
    case assist
    case student
    case skillGeneration
    case repair
}

public enum PolicyAssemblyWeightKind: String, Codable, CaseIterable, Sendable {
    case candidate
    case action
    case step
    case rule
}

public enum PolicyAssemblyRuleDisposition: String, Codable, CaseIterable, Sendable {
    case applied
    case suppressed
}

public struct PolicyAssemblyInputReference: Codable, Equatable, Sendable {
    public let traceId: String?
    public let sessionId: String?
    public let taskId: String?
    public let knowledgeItemId: String?
    public let stepId: String?
    public let skillName: String?
    public let skillDirectoryPath: String?
    public let sourceReference: String?

    public init(
        traceId: String? = nil,
        sessionId: String? = nil,
        taskId: String? = nil,
        knowledgeItemId: String? = nil,
        stepId: String? = nil,
        skillName: String? = nil,
        skillDirectoryPath: String? = nil,
        sourceReference: String? = nil
    ) {
        self.traceId = traceId
        self.sessionId = sessionId
        self.taskId = taskId
        self.knowledgeItemId = knowledgeItemId
        self.stepId = stepId
        self.skillName = skillName
        self.skillDirectoryPath = skillDirectoryPath
        self.sourceReference = sourceReference
    }
}

public struct PolicyAssemblyRuleEvaluation: Codable, Equatable, Sendable {
    public let ruleId: String
    public let targetId: String?
    public let targetLabel: String?
    public let disposition: PolicyAssemblyRuleDisposition
    public let matchScore: Double?
    public let weight: Double?
    public let delta: Double?
    public let explanation: String

    public init(
        ruleId: String,
        targetId: String? = nil,
        targetLabel: String? = nil,
        disposition: PolicyAssemblyRuleDisposition,
        matchScore: Double? = nil,
        weight: Double? = nil,
        delta: Double? = nil,
        explanation: String
    ) {
        self.ruleId = ruleId
        self.targetId = targetId
        self.targetLabel = targetLabel
        self.disposition = disposition
        self.matchScore = weightRound(matchScore)
        self.weight = weightRound(weight)
        self.delta = weightRound(delta)
        self.explanation = explanation
    }
}

public struct PolicyAssemblyFinalWeight: Codable, Equatable, Sendable {
    public let weightId: String
    public let label: String
    public let kind: PolicyAssemblyWeightKind
    public let baseValue: Double?
    public let finalValue: Double
    public let selected: Bool
    public let appliedRuleIds: [String]
    public let notes: [String]

    public init(
        weightId: String,
        label: String,
        kind: PolicyAssemblyWeightKind,
        baseValue: Double? = nil,
        finalValue: Double,
        selected: Bool,
        appliedRuleIds: [String] = [],
        notes: [String] = []
    ) {
        self.weightId = weightId
        self.label = label
        self.kind = kind
        self.baseValue = weightRound(baseValue)
        self.finalValue = weightRound(finalValue) ?? 0
        self.selected = selected
        self.appliedRuleIds = uniqueSorted(appliedRuleIds)
        self.notes = notes.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

public struct PolicyAssemblyDecision: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let decisionId: String
    public let targetModule: PolicyAssemblyTargetModule
    public let inputRef: PolicyAssemblyInputReference
    public let profileVersion: String?
    public let strategyVersion: String
    public let appliedRuleIds: [String]
    public let suppressedRuleIds: [String]
    public let finalDecisionSummary: String
    public let ruleEvaluations: [PolicyAssemblyRuleEvaluation]
    public let finalWeights: [PolicyAssemblyFinalWeight]
    public let timestamp: String

    public init(
        schemaVersion: String = "openstaff.learning.policy-assembly-decision.v0",
        decisionId: String,
        targetModule: PolicyAssemblyTargetModule,
        inputRef: PolicyAssemblyInputReference,
        profileVersion: String? = nil,
        strategyVersion: String,
        appliedRuleIds: [String],
        suppressedRuleIds: [String],
        finalDecisionSummary: String,
        ruleEvaluations: [PolicyAssemblyRuleEvaluation],
        finalWeights: [PolicyAssemblyFinalWeight],
        timestamp: String
    ) {
        self.schemaVersion = schemaVersion
        self.decisionId = decisionId
        self.targetModule = targetModule
        self.inputRef = inputRef
        self.profileVersion = profileVersion
        self.strategyVersion = strategyVersion
        self.appliedRuleIds = uniqueSorted(appliedRuleIds)
        self.suppressedRuleIds = uniqueSorted(
            suppressedRuleIds.filter { !appliedRuleIds.contains($0) }
        )
        self.finalDecisionSummary = finalDecisionSummary
        self.ruleEvaluations = ruleEvaluations.sorted(by: Self.ruleEvaluationSort)
        self.finalWeights = finalWeights.sorted(by: Self.finalWeightSort)
        self.timestamp = timestamp
    }

    private static func ruleEvaluationSort(
        lhs: PolicyAssemblyRuleEvaluation,
        rhs: PolicyAssemblyRuleEvaluation
    ) -> Bool {
        let lhsRank = lhs.disposition == .applied ? 0 : 1
        let rhsRank = rhs.disposition == .applied ? 0 : 1
        if lhsRank == rhsRank {
            let lhsMagnitude = abs(lhs.delta ?? 0)
            let rhsMagnitude = abs(rhs.delta ?? 0)
            if lhsMagnitude == rhsMagnitude {
                return lhs.ruleId < rhs.ruleId
            }
            return lhsMagnitude > rhsMagnitude
        }
        return lhsRank < rhsRank
    }

    private static func finalWeightSort(
        lhs: PolicyAssemblyFinalWeight,
        rhs: PolicyAssemblyFinalWeight
    ) -> Bool {
        if lhs.selected == rhs.selected {
            if lhs.finalValue == rhs.finalValue {
                return lhs.weightId < rhs.weightId
            }
            return lhs.finalValue > rhs.finalValue
        }
        return lhs.selected && !rhs.selected
    }
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}

private func weightRound(_ value: Double?) -> Double? {
    guard let value else {
        return nil
    }
    return (value * 100).rounded() / 100
}
