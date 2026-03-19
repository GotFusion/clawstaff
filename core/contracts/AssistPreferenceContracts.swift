import Foundation

public enum AssistPreferenceWeightDimension: String, Codable, CaseIterable, Sendable {
    case stepPreference
    case appPreference
    case riskPreference
}

public struct AssistPreferenceRuleHit: Codable, Equatable, Sendable {
    public let ruleId: String
    public let dimension: AssistPreferenceWeightDimension
    public let weight: Double
    public let matchScore: Double
    public let delta: Double
    public let explanation: String

    public init(
        ruleId: String,
        dimension: AssistPreferenceWeightDimension,
        weight: Double,
        matchScore: Double,
        delta: Double,
        explanation: String
    ) {
        self.ruleId = ruleId
        self.dimension = dimension
        self.weight = weight
        self.matchScore = matchScore
        self.delta = delta
        self.explanation = explanation
    }
}

public struct AssistPreferenceCandidateExplanation: Codable, Equatable, Sendable {
    public let knowledgeItemId: String
    public let taskId: String
    public let stepId: String
    public let stepInstruction: String
    public let baseScore: Double
    public let finalScore: Double
    public let appliedRuleIds: [String]
    public let ruleHits: [AssistPreferenceRuleHit]
    public let loweredReasons: [String]
    public let summary: String

    public init(
        knowledgeItemId: String,
        taskId: String,
        stepId: String,
        stepInstruction: String,
        baseScore: Double,
        finalScore: Double,
        appliedRuleIds: [String],
        ruleHits: [AssistPreferenceRuleHit],
        loweredReasons: [String],
        summary: String
    ) {
        self.knowledgeItemId = knowledgeItemId
        self.taskId = taskId
        self.stepId = stepId
        self.stepInstruction = stepInstruction
        self.baseScore = baseScore
        self.finalScore = finalScore
        self.appliedRuleIds = appliedRuleIds
        self.ruleHits = ruleHits
        self.loweredReasons = loweredReasons
        self.summary = summary
    }
}

public struct AssistPreferenceRerankDecision: Codable, Equatable, Sendable {
    public let profileVersion: String
    public let selectedKnowledgeItemId: String
    public let selectedStepId: String
    public let selectedBaseScore: Double
    public let selectedFinalScore: Double
    public let appliedRuleIds: [String]
    public let summary: String
    public let candidateExplanations: [AssistPreferenceCandidateExplanation]

    public init(
        profileVersion: String,
        selectedKnowledgeItemId: String,
        selectedStepId: String,
        selectedBaseScore: Double,
        selectedFinalScore: Double,
        appliedRuleIds: [String],
        summary: String,
        candidateExplanations: [AssistPreferenceCandidateExplanation]
    ) {
        self.profileVersion = profileVersion
        self.selectedKnowledgeItemId = selectedKnowledgeItemId
        self.selectedStepId = selectedStepId
        self.selectedBaseScore = selectedBaseScore
        self.selectedFinalScore = selectedFinalScore
        self.appliedRuleIds = Array(Set(appliedRuleIds)).sorted()
        self.summary = summary
        self.candidateExplanations = candidateExplanations
    }
}
