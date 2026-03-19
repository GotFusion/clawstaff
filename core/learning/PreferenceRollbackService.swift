import Foundation

public enum PreferenceRollbackOperationKind: String, Codable, CaseIterable, Sendable {
    case ruleRevocation
    case profileRollback
}

public struct PreferenceRollbackRuleImpact: Codable, Equatable, Sendable {
    public let ruleId: String
    public let statement: String
    public let scopeLevel: PreferenceSignalScope
    public let previousActivationStatus: PreferenceRuleActivationStatus
    public let newActivationStatus: PreferenceRuleActivationStatus
    public let reason: String

    public init(
        ruleId: String,
        statement: String,
        scopeLevel: PreferenceSignalScope,
        previousActivationStatus: PreferenceRuleActivationStatus,
        newActivationStatus: PreferenceRuleActivationStatus,
        reason: String
    ) {
        self.ruleId = ruleId
        self.statement = statement
        self.scopeLevel = scopeLevel
        self.previousActivationStatus = previousActivationStatus
        self.newActivationStatus = newActivationStatus
        self.reason = reason
    }
}

public struct PreferenceRollbackPlan: Codable, Equatable, Sendable {
    public let operation: PreferenceRollbackOperationKind
    public let actor: String
    public let timestamp: String
    public let reason: String
    public let ruleId: String?
    public let currentProfileVersion: String?
    public let targetProfileVersion: String?
    public let impactedRuleIds: [String]
    public let missingRuleIds: [String]
    public let ruleImpacts: [PreferenceRollbackRuleImpact]
    public let projectedSnapshot: PreferenceProfileSnapshot
    public let moduleSummaries: [PreferenceProfileModuleSummary]

    public init(
        operation: PreferenceRollbackOperationKind,
        actor: String,
        timestamp: String,
        reason: String,
        ruleId: String? = nil,
        currentProfileVersion: String? = nil,
        targetProfileVersion: String? = nil,
        impactedRuleIds: [String],
        missingRuleIds: [String],
        ruleImpacts: [PreferenceRollbackRuleImpact],
        projectedSnapshot: PreferenceProfileSnapshot,
        moduleSummaries: [PreferenceProfileModuleSummary]
    ) {
        self.operation = operation
        self.actor = actor
        self.timestamp = timestamp
        self.reason = reason
        self.ruleId = ruleId
        self.currentProfileVersion = currentProfileVersion
        self.targetProfileVersion = targetProfileVersion
        self.impactedRuleIds = Array(Set(impactedRuleIds)).sorted()
        self.missingRuleIds = Array(Set(missingRuleIds)).sorted()
        self.ruleImpacts = ruleImpacts.sorted { $0.ruleId < $1.ruleId }
        self.projectedSnapshot = projectedSnapshot
        self.moduleSummaries = moduleSummaries
    }
}

public struct PreferenceRollbackResult: Codable, Equatable, Sendable {
    public let plan: PreferenceRollbackPlan
    public let snapshot: PreferenceProfileSnapshot
    public let updatedRuleIds: [String]

    public init(
        plan: PreferenceRollbackPlan,
        snapshot: PreferenceProfileSnapshot,
        updatedRuleIds: [String]
    ) {
        self.plan = plan
        self.snapshot = snapshot
        self.updatedRuleIds = Array(Set(updatedRuleIds)).sorted()
    }
}

public enum PreferenceRollbackServiceError: LocalizedError {
    case ruleNotFound(ruleId: String)
    case profileSnapshotNotFound(profileVersion: String)
    case missingRulesForTargetProfile(profileVersion: String, ruleIds: [String])

    public var errorDescription: String? {
        switch self {
        case .ruleNotFound(let ruleId):
            return "Preference rollback target rule \(ruleId) was not found."
        case .profileSnapshotNotFound(let profileVersion):
            return "Preference rollback target profile snapshot \(profileVersion) was not found."
        case .missingRulesForTargetProfile(let profileVersion, let ruleIds):
            return "Preference rollback target profile \(profileVersion) is missing rule files: \(ruleIds.joined(separator: ", "))."
        }
    }
}

public struct PreferenceRollbackService: Sendable {
    public let profileBuilder: PreferenceProfileBuilder

    public init(
        profileBuilder: PreferenceProfileBuilder = PreferenceProfileBuilder()
    ) {
        self.profileBuilder = profileBuilder
    }

    public func previewRuleRevocation(
        ruleId: String,
        using store: PreferenceMemoryStore,
        actor: String = "system",
        timestamp: String,
        reason: String? = nil,
        projectedProfileVersion: String? = nil
    ) throws -> PreferenceRollbackPlan {
        let rules = try allRules(using: store)
        guard let targetRule = rules.first(where: { $0.ruleId == ruleId }) else {
            throw PreferenceRollbackServiceError.ruleNotFound(ruleId: ruleId)
        }

        let rollbackReason = normalizedReason(
            reason,
            fallback: "Revoke rule \(ruleId) from the active preference profile."
        )
        let currentProfileVersion = try store.loadLatestProfileSnapshot()?.profileVersion
        let updatedRule = targetRule.updatingActivationStatus(
            .revoked,
            updatedAt: timestamp,
            lifecycleReason: rollbackReason
        )

        let ruleImpacts: [PreferenceRollbackRuleImpact]
        let simulatedRules: [PreferenceRule]
        if targetRule.activationStatus == .revoked {
            ruleImpacts = []
            simulatedRules = rules
        } else {
            ruleImpacts = [
                PreferenceRollbackRuleImpact(
                    ruleId: ruleId,
                    statement: targetRule.statement,
                    scopeLevel: targetRule.scope.level,
                    previousActivationStatus: targetRule.activationStatus,
                    newActivationStatus: .revoked,
                    reason: rollbackReason
                )
            ]
            simulatedRules = replacingRule(updatedRule, in: rules)
        }

        let buildResult = profileBuilder.build(
            from: simulatedRules,
            profileVersion: projectedProfileVersion ?? derivedPreviewProfileVersion(generatedAt: timestamp),
            generatedAt: timestamp,
            previousProfileVersion: currentProfileVersion,
            note: rollbackReason
        )

        return PreferenceRollbackPlan(
            operation: .ruleRevocation,
            actor: actor,
            timestamp: timestamp,
            reason: rollbackReason,
            ruleId: ruleId,
            currentProfileVersion: currentProfileVersion,
            targetProfileVersion: nil,
            impactedRuleIds: ruleImpacts.map(\.ruleId),
            missingRuleIds: [],
            ruleImpacts: ruleImpacts,
            projectedSnapshot: buildResult.snapshot,
            moduleSummaries: buildResult.moduleSummaries
        )
    }

    @discardableResult
    public func applyRuleRevocation(
        ruleId: String,
        using store: PreferenceMemoryStore,
        actor: String = "system",
        timestamp: String,
        reason: String? = nil,
        profileVersion: String? = nil
    ) throws -> PreferenceRollbackResult {
        let plan = try previewRuleRevocation(
            ruleId: ruleId,
            using: store,
            actor: actor,
            timestamp: timestamp,
            reason: reason,
            projectedProfileVersion: profileVersion ?? PreferenceProfileBuilder.derivedProfileVersion(generatedAt: timestamp)
        )

        if let impact = plan.ruleImpacts.first,
           let rule = try store.loadRule(ruleId: impact.ruleId) {
            let updatedRule = rule.updatingActivationStatus(
                impact.newActivationStatus,
                updatedAt: timestamp,
                lifecycleReason: impact.reason
            )
            try store.storeRule(
                updatedRule,
                actor: actor,
                auditContext: PreferenceRuleAuditContext(
                    action: .ruleRevoked,
                    source: .rollbackService(referenceId: ruleId, summary: plan.reason)
                ),
                note: plan.reason
            )
        }

        try store.storeProfileSnapshot(
            plan.projectedSnapshot,
            actor: actor,
            auditContext: PreferenceProfileAuditContext(
                source: .rollbackService(referenceId: ruleId, summary: plan.reason),
                relatedProfileVersion: plan.currentProfileVersion
            ),
            note: plan.reason
        )

        return PreferenceRollbackResult(
            plan: plan,
            snapshot: plan.projectedSnapshot,
            updatedRuleIds: plan.impactedRuleIds
        )
    }

    public func previewProfileRollback(
        to targetProfileVersion: String,
        using store: PreferenceMemoryStore,
        actor: String = "system",
        timestamp: String,
        reason: String? = nil,
        projectedProfileVersion: String? = nil
    ) throws -> PreferenceRollbackPlan {
        guard let targetSnapshot = try store.loadProfileSnapshot(profileVersion: targetProfileVersion) else {
            throw PreferenceRollbackServiceError.profileSnapshotNotFound(profileVersion: targetProfileVersion)
        }

        let rules = try allRules(using: store)
        let currentProfileVersion = try store.loadLatestProfileSnapshot()?.profileVersion
        let desiredRuleIds = Set(targetSnapshot.profile.activeRuleIds)
        let existingRuleIds = Set(rules.map(\.ruleId))
        let missingRuleIds = Array(desiredRuleIds.subtracting(existingRuleIds)).sorted()
        let rollbackReason = normalizedReason(
            reason,
            fallback: "Rollback active preferences to snapshot \(targetProfileVersion)."
        )

        var simulatedRules = rules
        var ruleImpacts: [PreferenceRollbackRuleImpact] = []

        for rule in rules {
            if desiredRuleIds.contains(rule.ruleId) {
                guard rule.activationStatus != .active else {
                    continue
                }

                let restoredRule = rule.updatingActivationStatus(
                    .active,
                    updatedAt: timestamp,
                    lifecycleReason: rollbackReason
                )
                simulatedRules = replacingRule(restoredRule, in: simulatedRules)
                ruleImpacts.append(
                    PreferenceRollbackRuleImpact(
                        ruleId: rule.ruleId,
                        statement: rule.statement,
                        scopeLevel: rule.scope.level,
                        previousActivationStatus: rule.activationStatus,
                        newActivationStatus: .active,
                        reason: rollbackReason
                    )
                )
                continue
            }

            guard rule.activationStatus == .active else {
                continue
            }

            let revokedRule = rule.updatingActivationStatus(
                .revoked,
                updatedAt: timestamp,
                lifecycleReason: rollbackReason
            )
            simulatedRules = replacingRule(revokedRule, in: simulatedRules)
            ruleImpacts.append(
                PreferenceRollbackRuleImpact(
                    ruleId: rule.ruleId,
                    statement: rule.statement,
                    scopeLevel: rule.scope.level,
                    previousActivationStatus: rule.activationStatus,
                    newActivationStatus: .revoked,
                    reason: rollbackReason
                )
            )
        }

        let buildResult = profileBuilder.build(
            from: simulatedRules,
            profileVersion: projectedProfileVersion ?? derivedPreviewProfileVersion(generatedAt: timestamp),
            generatedAt: timestamp,
            previousProfileVersion: currentProfileVersion,
            note: rollbackReason
        )

        return PreferenceRollbackPlan(
            operation: .profileRollback,
            actor: actor,
            timestamp: timestamp,
            reason: rollbackReason,
            ruleId: nil,
            currentProfileVersion: currentProfileVersion,
            targetProfileVersion: targetProfileVersion,
            impactedRuleIds: ruleImpacts.map(\.ruleId),
            missingRuleIds: missingRuleIds,
            ruleImpacts: ruleImpacts,
            projectedSnapshot: buildResult.snapshot,
            moduleSummaries: buildResult.moduleSummaries
        )
    }

    @discardableResult
    public func applyProfileRollback(
        to targetProfileVersion: String,
        using store: PreferenceMemoryStore,
        actor: String = "system",
        timestamp: String,
        reason: String? = nil,
        profileVersion: String? = nil
    ) throws -> PreferenceRollbackResult {
        let plan = try previewProfileRollback(
            to: targetProfileVersion,
            using: store,
            actor: actor,
            timestamp: timestamp,
            reason: reason,
            projectedProfileVersion: profileVersion ?? PreferenceProfileBuilder.derivedProfileVersion(generatedAt: timestamp)
        )

        if !plan.missingRuleIds.isEmpty {
            throw PreferenceRollbackServiceError.missingRulesForTargetProfile(
                profileVersion: targetProfileVersion,
                ruleIds: plan.missingRuleIds
            )
        }

        for impact in plan.ruleImpacts {
            guard let rule = try store.loadRule(ruleId: impact.ruleId) else {
                continue
            }
            let updatedRule = rule.updatingActivationStatus(
                impact.newActivationStatus,
                updatedAt: timestamp,
                lifecycleReason: impact.reason
            )
            try store.storeRule(
                updatedRule,
                actor: actor,
                auditContext: PreferenceRuleAuditContext(
                    action: .ruleRolledBack,
                    source: .rollbackService(referenceId: targetProfileVersion, summary: plan.reason),
                    relatedProfileVersion: targetProfileVersion
                ),
                note: impact.reason
            )
        }

        try store.storeProfileSnapshot(
            plan.projectedSnapshot,
            actor: actor,
            auditContext: PreferenceProfileAuditContext(
                source: .rollbackService(referenceId: targetProfileVersion, summary: plan.reason),
                relatedProfileVersion: plan.currentProfileVersion
            ),
            note: plan.reason
        )

        try store.auditLogStore.append(
            PreferenceAuditLogEntry(
                auditId: "audit-rollback-\(UUID().uuidString)",
                action: .rollbackApplied,
                timestamp: timestamp,
                actor: actor,
                source: .rollbackService(referenceId: targetProfileVersion, summary: plan.reason),
                affectedRuleIds: plan.impactedRuleIds,
                profileVersion: plan.projectedSnapshot.profileVersion,
                relatedProfileVersion: targetProfileVersion,
                note: plan.reason
            )
        )

        return PreferenceRollbackResult(
            plan: plan,
            snapshot: plan.projectedSnapshot,
            updatedRuleIds: plan.impactedRuleIds
        )
    }

    private func allRules(using store: PreferenceMemoryStore) throws -> [PreferenceRule] {
        try store.loadRules(matching: PreferenceRuleQuery(includeInactive: true))
    }

    private func replacingRule(
        _ replacement: PreferenceRule,
        in rules: [PreferenceRule]
    ) -> [PreferenceRule] {
        rules.map { rule in
            rule.ruleId == replacement.ruleId ? replacement : rule
        }
    }

    private func normalizedReason(
        _ value: String?,
        fallback: String
    ) -> String {
        guard let value else {
            return fallback
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func derivedPreviewProfileVersion(generatedAt: String) -> String {
        "preview-\(PreferenceProfileBuilder.derivedProfileVersion(generatedAt: generatedAt))"
    }
}
