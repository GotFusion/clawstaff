import Foundation

public enum PreferenceConflictReasonCode: String, Codable, CaseIterable, Sendable {
    case activeRulePreferred
    case moreSpecificScope
    case recentTeacherConfirmation
    case lowerRisk
    case moreRecentlyUpdated
    case stableRuleIdTieBreak

    fileprivate var summaryFragment: String {
        switch self {
        case .activeRulePreferred:
            return "active rule outranks inactive history"
        case .moreSpecificScope:
            return "scope is more specific"
        case .recentTeacherConfirmation:
            return "teacher confirmation is more recent"
        case .lowerRisk:
            return "risk is lower"
        case .moreRecentlyUpdated:
            return "rule is more recently updated"
        case .stableRuleIdTieBreak:
            return "rule id provides a stable tie-break"
        }
    }
}

public struct PreferenceConflictExplanation: Codable, Equatable, Sendable {
    public let winnerRuleId: String
    public let loserRuleId: String
    public let reasonCodes: [PreferenceConflictReasonCode]
    public let summary: String

    public init(
        winnerRuleId: String,
        loserRuleId: String,
        reasonCodes: [PreferenceConflictReasonCode],
        summary: String
    ) {
        self.winnerRuleId = winnerRuleId
        self.loserRuleId = loserRuleId
        self.reasonCodes = reasonCodes
        self.summary = summary
    }
}

public struct PreferenceConflictResolution: Equatable, Sendable {
    public let orderedRules: [PreferenceRule]
    public let overrideExplanations: [PreferenceConflictExplanation]

    public init(
        orderedRules: [PreferenceRule],
        overrideExplanations: [PreferenceConflictExplanation]
    ) {
        self.orderedRules = orderedRules
        self.overrideExplanations = overrideExplanations
    }

    public var winningRuleId: String? {
        orderedRules.first?.ruleId
    }
}

public struct PreferenceConflictResolver: Sendable {
    public static let v0Default = Self(policy: .loadDefaultOrFallback())

    public let priorityOrder: [PreferenceConflictPriority]

    public init(policy: PreferencePromotionPolicy = .loadDefaultOrFallback()) {
        self.init(priorityOrder: policy.conflictPriority)
    }

    public init(priorityOrder: [PreferenceConflictPriority]) {
        self.priorityOrder = PreferenceConflictPriority.normalized(priorityOrder)
    }

    public func resolve(_ rules: [PreferenceRule]) -> PreferenceConflictResolution {
        let orderedRules = rules.sorted(by: sortsBefore)
        guard let winner = orderedRules.first else {
            return PreferenceConflictResolution(orderedRules: [], overrideExplanations: [])
        }

        let overrideExplanations = orderedRules.dropFirst().map { loser in
            explainOverride(winner: winner, loser: loser)
        }

        return PreferenceConflictResolution(
            orderedRules: orderedRules,
            overrideExplanations: overrideExplanations
        )
    }

    public func sortsBefore(_ lhs: PreferenceRule, _ rhs: PreferenceRule) -> Bool {
        if lhs.ruleId == rhs.ruleId {
            return false
        }

        for priority in priorityOrder {
            if let result = comparisonResult(for: priority, lhs: lhs, rhs: rhs) {
                return result
            }
        }

        return lhs.ruleId < rhs.ruleId
    }

    public func explainConflict(
        between first: PreferenceRule,
        and second: PreferenceRule
    ) -> PreferenceConflictExplanation {
        if sortsBefore(first, second) {
            return explainOverride(winner: first, loser: second)
        }
        return explainOverride(winner: second, loser: first)
    }

    public func explainOverride(
        winner: PreferenceRule,
        loser: PreferenceRule
    ) -> PreferenceConflictExplanation {
        let reasonCodes = reasonCodesForOverride(winner: winner, loser: loser)
        let summary = "\(winner.ruleId) overrides \(loser.ruleId) because \(reasonCodes.map(\.summaryFragment).joined(separator: ", "))."
        return PreferenceConflictExplanation(
            winnerRuleId: winner.ruleId,
            loserRuleId: loser.ruleId,
            reasonCodes: reasonCodes,
            summary: summary
        )
    }

    public static func scopeSpecificity(for scope: PreferenceSignalScopeReference) -> Int {
        var score: Int
        switch scope.level {
        case .global:
            score = 0
        case .app:
            score = 20
        case .taskFamily:
            score = 30
        case .skillFamily:
            score = 40
        case .windowPattern:
            score = 50
        }

        if scope.appBundleId != nil {
            score += 3
        }
        if scope.taskFamily != nil {
            score += 4
        }
        if scope.skillFamily != nil {
            score += 5
        }
        if scope.windowPattern != nil {
            score += 6
        }

        return score
    }

    private func reasonCodesForOverride(
        winner: PreferenceRule,
        loser: PreferenceRule
    ) -> [PreferenceConflictReasonCode] {
        var reasonCodes: [PreferenceConflictReasonCode] = []

        for priority in priorityOrder {
            if winnerWins(priority: priority, winner: winner, loser: loser) {
                reasonCodes.append(reasonCode(for: priority))
            }
        }

        if reasonCodes.isEmpty {
            reasonCodes.append(.stableRuleIdTieBreak)
        }

        return reasonCodes
    }

    private func confirmationSortKey(for rule: PreferenceRule) -> String {
        rule.teacherConfirmed ? rule.updatedAt : ""
    }

    private func comparisonResult(
        for priority: PreferenceConflictPriority,
        lhs: PreferenceRule,
        rhs: PreferenceRule
    ) -> Bool? {
        switch priority {
        case .activeRulePreferred:
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
        case .moreSpecificScope:
            let lhsSpecificity = Self.scopeSpecificity(for: lhs.scope)
            let rhsSpecificity = Self.scopeSpecificity(for: rhs.scope)
            if lhsSpecificity != rhsSpecificity {
                return lhsSpecificity > rhsSpecificity
            }
        case .recentTeacherConfirmation:
            let lhsConfirmationKey = confirmationSortKey(for: lhs)
            let rhsConfirmationKey = confirmationSortKey(for: rhs)
            if lhsConfirmationKey != rhsConfirmationKey {
                return lhsConfirmationKey > rhsConfirmationKey
            }
        case .lowerRisk:
            let lhsRiskRank = Self.riskRank(for: lhs.riskLevel)
            let rhsRiskRank = Self.riskRank(for: rhs.riskLevel)
            if lhsRiskRank != rhsRiskRank {
                return lhsRiskRank < rhsRiskRank
            }
        case .moreRecentlyUpdated:
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
        case .stableRuleIdTieBreak:
            if lhs.ruleId != rhs.ruleId {
                return lhs.ruleId < rhs.ruleId
            }
        }
        return nil
    }

    private func winnerWins(
        priority: PreferenceConflictPriority,
        winner: PreferenceRule,
        loser: PreferenceRule
    ) -> Bool {
        comparisonResult(for: priority, lhs: winner, rhs: loser) == true
    }

    private func reasonCode(for priority: PreferenceConflictPriority) -> PreferenceConflictReasonCode {
        switch priority {
        case .activeRulePreferred:
            return .activeRulePreferred
        case .moreSpecificScope:
            return .moreSpecificScope
        case .recentTeacherConfirmation:
            return .recentTeacherConfirmation
        case .lowerRisk:
            return .lowerRisk
        case .moreRecentlyUpdated:
            return .moreRecentlyUpdated
        case .stableRuleIdTieBreak:
            return .stableRuleIdTieBreak
        }
    }

    private static func riskRank(for riskLevel: InteractionTurnRiskLevel) -> Int {
        switch riskLevel {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        case .critical:
            return 3
        }
    }
}
