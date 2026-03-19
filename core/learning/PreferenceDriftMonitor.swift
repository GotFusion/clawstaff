import Foundation

public enum PreferenceDriftFindingKind: String, Codable, CaseIterable, Sendable {
    case longTimeNoHit
    case overrideRateElevated
    case stylePreferenceChanged
    case teacherRejectedRepeatedly
    case highRiskBehaviorMismatch
}

public enum PreferenceDriftFindingSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case high
    case critical

    fileprivate var rank: Int {
        switch self {
        case .critical:
            return 0
        case .high:
            return 1
        case .warning:
            return 2
        case .info:
            return 3
        }
    }
}

public struct PreferenceDriftMonitorConfiguration: Codable, Equatable, Sendable {
    public let staleWindowDays: Int
    public let recentRelevantDecisionLimit: Int
    public let overrideRateThreshold: Double
    public let explicitTeacherRejectionThreshold: Int
    public let styleChangeWindowDays: Int
    public let minimumRelevantDecisionCount: Int

    public init(
        staleWindowDays: Int = 30,
        recentRelevantDecisionLimit: Int = 10,
        overrideRateThreshold: Double = 0.5,
        explicitTeacherRejectionThreshold: Int = 3,
        styleChangeWindowDays: Int = 30,
        minimumRelevantDecisionCount: Int = 2
    ) {
        self.staleWindowDays = max(1, staleWindowDays)
        self.recentRelevantDecisionLimit = max(1, recentRelevantDecisionLimit)
        self.overrideRateThreshold = min(max(overrideRateThreshold, 0), 1)
        self.explicitTeacherRejectionThreshold = max(1, explicitTeacherRejectionThreshold)
        self.styleChangeWindowDays = max(1, styleChangeWindowDays)
        self.minimumRelevantDecisionCount = max(1, minimumRelevantDecisionCount)
    }

    public static let v0Default = Self()
}

public enum PreferenceDriftEvidenceKind: String, Codable, CaseIterable, Sendable {
    case policyAssemblyDecision
    case auditEntry
    case rule
}

public struct PreferenceDriftEvidenceReference: Codable, Equatable, Sendable {
    public let kind: PreferenceDriftEvidenceKind
    public let referenceId: String
    public let timestamp: String?
    public let summary: String

    public init(
        kind: PreferenceDriftEvidenceKind,
        referenceId: String,
        timestamp: String? = nil,
        summary: String
    ) {
        self.kind = kind
        self.referenceId = referenceId
        self.timestamp = timestamp
        self.summary = summary
    }
}

public struct PreferenceDriftFindingMetrics: Codable, Equatable, Sendable {
    public let daysSinceLastRelevantActivity: Int?
    public let recentRelevantDecisionCount: Int?
    public let recentOverrideCount: Int?
    public let recentOverrideRate: Double?
    public let explicitTeacherRejectionCount: Int?
    public let recentStyleSiblingCount: Int?

    public init(
        daysSinceLastRelevantActivity: Int? = nil,
        recentRelevantDecisionCount: Int? = nil,
        recentOverrideCount: Int? = nil,
        recentOverrideRate: Double? = nil,
        explicitTeacherRejectionCount: Int? = nil,
        recentStyleSiblingCount: Int? = nil
    ) {
        self.daysSinceLastRelevantActivity = daysSinceLastRelevantActivity
        self.recentRelevantDecisionCount = recentRelevantDecisionCount
        self.recentOverrideCount = recentOverrideCount
        self.recentOverrideRate = PreferenceDriftMonitor.round(recentOverrideRate)
        self.explicitTeacherRejectionCount = explicitTeacherRejectionCount
        self.recentStyleSiblingCount = recentStyleSiblingCount
    }
}

public struct PreferenceDriftFinding: Codable, Equatable, Sendable {
    public let findingId: String
    public let ruleId: String
    public let kind: PreferenceDriftFindingKind
    public let severity: PreferenceDriftFindingSeverity
    public let summary: String
    public let rationale: String
    public let metrics: PreferenceDriftFindingMetrics
    public let evidence: [PreferenceDriftEvidenceReference]
    public let triggeredAt: String

    public init(
        findingId: String,
        ruleId: String,
        kind: PreferenceDriftFindingKind,
        severity: PreferenceDriftFindingSeverity,
        summary: String,
        rationale: String,
        metrics: PreferenceDriftFindingMetrics,
        evidence: [PreferenceDriftEvidenceReference],
        triggeredAt: String
    ) {
        self.findingId = findingId
        self.ruleId = ruleId
        self.kind = kind
        self.severity = severity
        self.summary = summary
        self.rationale = rationale
        self.metrics = metrics
        self.evidence = evidence.sorted {
            ($0.timestamp ?? "", $0.referenceId) > ($1.timestamp ?? "", $1.referenceId)
        }
        self.triggeredAt = triggeredAt
    }
}

public struct PreferenceDriftRuleUsageStats: Codable, Equatable, Sendable {
    public let ruleId: String
    public let type: PreferenceSignalType
    public let scope: PreferenceSignalScopeReference
    public let riskLevel: InteractionTurnRiskLevel
    public let lastConsideredAt: String?
    public let lastAppliedAt: String?
    public let daysSinceLastRelevantActivity: Int?
    public let totalConsideredCount: Int
    public let totalAppliedCount: Int
    public let totalSuppressedCount: Int
    public let recentRelevantDecisionCount: Int
    public let recentOverrideCount: Int
    public let recentOverrideRate: Double?
    public let explicitTeacherRejectionCount: Int

    public init(
        ruleId: String,
        type: PreferenceSignalType,
        scope: PreferenceSignalScopeReference,
        riskLevel: InteractionTurnRiskLevel,
        lastConsideredAt: String?,
        lastAppliedAt: String?,
        daysSinceLastRelevantActivity: Int?,
        totalConsideredCount: Int,
        totalAppliedCount: Int,
        totalSuppressedCount: Int,
        recentRelevantDecisionCount: Int,
        recentOverrideCount: Int,
        recentOverrideRate: Double?,
        explicitTeacherRejectionCount: Int
    ) {
        self.ruleId = ruleId
        self.type = type
        self.scope = scope
        self.riskLevel = riskLevel
        self.lastConsideredAt = lastConsideredAt
        self.lastAppliedAt = lastAppliedAt
        self.daysSinceLastRelevantActivity = daysSinceLastRelevantActivity
        self.totalConsideredCount = totalConsideredCount
        self.totalAppliedCount = totalAppliedCount
        self.totalSuppressedCount = totalSuppressedCount
        self.recentRelevantDecisionCount = recentRelevantDecisionCount
        self.recentOverrideCount = recentOverrideCount
        self.recentOverrideRate = PreferenceDriftMonitor.round(recentOverrideRate)
        self.explicitTeacherRejectionCount = explicitTeacherRejectionCount
    }
}

public struct PreferenceDriftMonitorDataAvailability: Codable, Equatable, Sendable {
    public let auditEntriesAvailable: Bool
    public let assemblyDecisionsAvailable: Bool
    public let usageMetricsEvaluated: Bool
    public let totalAuditEntryCount: Int
    public let totalAssemblyDecisionCount: Int

    public init(
        auditEntriesAvailable: Bool,
        assemblyDecisionsAvailable: Bool,
        usageMetricsEvaluated: Bool,
        totalAuditEntryCount: Int,
        totalAssemblyDecisionCount: Int
    ) {
        self.auditEntriesAvailable = auditEntriesAvailable
        self.assemblyDecisionsAvailable = assemblyDecisionsAvailable
        self.usageMetricsEvaluated = usageMetricsEvaluated
        self.totalAuditEntryCount = totalAuditEntryCount
        self.totalAssemblyDecisionCount = totalAssemblyDecisionCount
    }
}

public struct PreferenceDriftMonitorReport: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let generatedAt: String
    public let profileVersion: String?
    public let activeRuleIds: [String]
    public let configuration: PreferenceDriftMonitorConfiguration
    public let dataAvailability: PreferenceDriftMonitorDataAvailability
    public let ruleStats: [PreferenceDriftRuleUsageStats]
    public let findings: [PreferenceDriftFinding]

    public init(
        schemaVersion: String = "openstaff.learning.preference-drift-monitor.v0",
        generatedAt: String,
        profileVersion: String?,
        activeRuleIds: [String],
        configuration: PreferenceDriftMonitorConfiguration,
        dataAvailability: PreferenceDriftMonitorDataAvailability,
        ruleStats: [PreferenceDriftRuleUsageStats],
        findings: [PreferenceDriftFinding]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.profileVersion = profileVersion
        self.activeRuleIds = Array(Set(activeRuleIds)).sorted()
        self.configuration = configuration
        self.dataAvailability = dataAvailability
        self.ruleStats = ruleStats.sorted { $0.ruleId < $1.ruleId }
        self.findings = findings.sorted(by: Self.sortFindings)
    }

    private static func sortFindings(
        lhs: PreferenceDriftFinding,
        rhs: PreferenceDriftFinding
    ) -> Bool {
        if lhs.severity.rank == rhs.severity.rank {
            if lhs.ruleId == rhs.ruleId {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.ruleId < rhs.ruleId
        }
        return lhs.severity.rank < rhs.severity.rank
    }
}

public enum PreferenceDriftMonitorError: LocalizedError {
    case profileSnapshotNotFound(profileVersion: String)

    public var errorDescription: String? {
        switch self {
        case .profileSnapshotNotFound(let profileVersion):
            return "Preference drift monitor target profile snapshot \(profileVersion) was not found."
        }
    }
}

public struct PreferenceDriftMonitor: Sendable {
    public let configuration: PreferenceDriftMonitorConfiguration

    public init(
        configuration: PreferenceDriftMonitorConfiguration = .v0Default
    ) {
        self.configuration = configuration
    }

    public func analyze(
        using store: PreferenceMemoryStore,
        profileVersion: String? = nil,
        generatedAt: String
    ) throws -> PreferenceDriftMonitorReport {
        let generatedDate = Self.parseDate(generatedAt) ?? Date()
        let snapshot = try loadSnapshot(profileVersion: profileVersion, using: store)
        let allRules = try store.loadRules(matching: PreferenceRuleQuery(includeInactive: true))
        let activeRules = resolvedActiveRules(from: allRules, snapshot: snapshot)
        let auditEntries = try store.loadAuditEntries()
        let decisionStore = PolicyAssemblyDecisionStore(preferencesRootDirectory: store.preferencesRootDirectory)
        let assemblyDecisions = try decisionStore.loadDecisions()

        let rejectionEntriesByRuleId = groupedTeacherRejections(from: auditEntries)
        let decisionsByRuleId = groupedDecisionsByRuleId(from: assemblyDecisions)
        let usageMetricsEvaluated = !assemblyDecisions.isEmpty

        let ruleStats = activeRules.map { rule in
            usageStats(
                for: rule,
                decisions: decisionsByRuleId[rule.ruleId] ?? [],
                rejectionEntries: rejectionEntriesByRuleId[rule.ruleId] ?? [],
                generatedAt: generatedDate
            )
        }
        let ruleStatsByRuleId = Dictionary(uniqueKeysWithValues: ruleStats.map { ($0.ruleId, $0) })

        var findings: [PreferenceDriftFinding] = []
        for rule in activeRules {
            guard let stats = ruleStatsByRuleId[rule.ruleId] else {
                continue
            }

            let rejectionEntries = rejectionEntriesByRuleId[rule.ruleId] ?? []
            let relevantDecisions = decisionsByRuleId[rule.ruleId] ?? []
            let recentDecisions = recentRelevantDecisions(from: relevantDecisions)
            let recentStyleSiblings = recentStyleSiblingRules(
                for: rule,
                in: allRules,
                generatedAt: generatedDate
            )

            if usageMetricsEvaluated,
               let staleFinding = staleUsageFinding(
                    rule: rule,
                    stats: stats,
                    generatedAt: generatedAt,
                    recentDecisions: recentDecisions
               ) {
                findings.append(staleFinding)
            }

            if usageMetricsEvaluated,
               let overrideFinding = overrideRateFinding(
                    rule: rule,
                    stats: stats,
                    generatedAt: generatedAt,
                    recentDecisions: recentDecisions
               ) {
                findings.append(overrideFinding)
            }

            if let rejectionFinding = repeatedTeacherRejectionFinding(
                rule: rule,
                stats: stats,
                generatedAt: generatedAt,
                rejectionEntries: rejectionEntries
            ) {
                findings.append(rejectionFinding)
            }

            if let styleFinding = styleChangeFinding(
                rule: rule,
                stats: stats,
                generatedAt: generatedAt,
                rejectionEntries: rejectionEntries,
                siblingRules: recentStyleSiblings
            ) {
                findings.append(styleFinding)
            }

            if usageMetricsEvaluated,
               let highRiskFinding = highRiskMismatchFinding(
                    rule: rule,
                    stats: stats,
                    generatedAt: generatedAt,
                    recentDecisions: recentDecisions,
                    rejectionEntries: rejectionEntries
               ) {
                findings.append(highRiskFinding)
            }
        }

        return PreferenceDriftMonitorReport(
            generatedAt: generatedAt,
            profileVersion: snapshot?.profileVersion,
            activeRuleIds: activeRules.map(\.ruleId),
            configuration: configuration,
            dataAvailability: PreferenceDriftMonitorDataAvailability(
                auditEntriesAvailable: !auditEntries.isEmpty,
                assemblyDecisionsAvailable: !assemblyDecisions.isEmpty,
                usageMetricsEvaluated: usageMetricsEvaluated,
                totalAuditEntryCount: auditEntries.count,
                totalAssemblyDecisionCount: assemblyDecisions.count
            ),
            ruleStats: ruleStats,
            findings: findings
        )
    }

    private func loadSnapshot(
        profileVersion: String?,
        using store: PreferenceMemoryStore
    ) throws -> PreferenceProfileSnapshot? {
        guard let profileVersion else {
            return try store.loadLatestProfileSnapshot()
        }
        guard let snapshot = try store.loadProfileSnapshot(profileVersion: profileVersion) else {
            throw PreferenceDriftMonitorError.profileSnapshotNotFound(profileVersion: profileVersion)
        }
        return snapshot
    }

    private func resolvedActiveRules(
        from rules: [PreferenceRule],
        snapshot: PreferenceProfileSnapshot?
    ) -> [PreferenceRule] {
        guard let snapshot else {
            return rules.filter(\.isActive).sorted { $0.ruleId < $1.ruleId }
        }

        let rulesById = Dictionary(uniqueKeysWithValues: rules.map { ($0.ruleId, $0) })
        return snapshot.profile.activeRuleIds.compactMap { rulesById[$0] }
    }

    private func groupedTeacherRejections(
        from entries: [PreferenceAuditLogEntry]
    ) -> [String: [PreferenceAuditLogEntry]] {
        var grouped: [String: [PreferenceAuditLogEntry]] = [:]

        for entry in entries where isExplicitTeacherRejection(entry) {
            for ruleId in entry.affectedRuleIds where !ruleId.isEmpty {
                grouped[ruleId, default: []].append(entry)
            }
        }

        return grouped.mapValues { entries in
            entries.sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.auditId > rhs.auditId
                }
                return lhs.timestamp > rhs.timestamp
            }
        }
    }

    private func groupedDecisionsByRuleId(
        from decisions: [PolicyAssemblyDecision]
    ) -> [String: [PolicyAssemblyDecision]] {
        var grouped: [String: [PolicyAssemblyDecision]] = [:]

        for decision in decisions {
            let ruleIds = Array(Set(decision.appliedRuleIds + decision.suppressedRuleIds))
            for ruleId in ruleIds where !ruleId.isEmpty {
                grouped[ruleId, default: []].append(decision)
            }
        }

        return grouped.mapValues { decisions in
            decisions.sorted(by: Self.sortDecisionsDescending)
        }
    }

    private func usageStats(
        for rule: PreferenceRule,
        decisions: [PolicyAssemblyDecision],
        rejectionEntries: [PreferenceAuditLogEntry],
        generatedAt: Date
    ) -> PreferenceDriftRuleUsageStats {
        let recentDecisions = recentRelevantDecisions(from: decisions)
        let lastConsideredAt = decisions.first?.timestamp
        let lastAppliedAt = decisions.first(where: { $0.appliedRuleIds.contains(rule.ruleId) })?.timestamp
        let fallbackTimestamp = lastConsideredAt ?? rule.updatedAt
        let lastRelevantDate = Self.parseDate(fallbackTimestamp)
        let daysSinceLastRelevantActivity = lastRelevantDate.map {
            Self.daysBetween($0, and: generatedAt)
        }
        let totalAppliedCount = decisions.filter { $0.appliedRuleIds.contains(rule.ruleId) }.count
        let totalSuppressedCount = decisions.filter { $0.suppressedRuleIds.contains(rule.ruleId) }.count
        let recentOverrideCount = recentDecisions.filter { $0.suppressedRuleIds.contains(rule.ruleId) }.count
        let recentOverrideRate = recentDecisions.isEmpty
            ? nil
            : Double(recentOverrideCount) / Double(recentDecisions.count)

        return PreferenceDriftRuleUsageStats(
            ruleId: rule.ruleId,
            type: rule.type,
            scope: rule.scope,
            riskLevel: rule.riskLevel,
            lastConsideredAt: lastConsideredAt,
            lastAppliedAt: lastAppliedAt,
            daysSinceLastRelevantActivity: daysSinceLastRelevantActivity,
            totalConsideredCount: decisions.count,
            totalAppliedCount: totalAppliedCount,
            totalSuppressedCount: totalSuppressedCount,
            recentRelevantDecisionCount: recentDecisions.count,
            recentOverrideCount: recentOverrideCount,
            recentOverrideRate: recentOverrideRate,
            explicitTeacherRejectionCount: rejectionEntries.count
        )
    }

    private func recentRelevantDecisions(
        from decisions: [PolicyAssemblyDecision]
    ) -> [PolicyAssemblyDecision] {
        Array(decisions.sorted(by: Self.sortDecisionsDescending).prefix(configuration.recentRelevantDecisionLimit))
    }

    private func recentStyleSiblingRules(
        for rule: PreferenceRule,
        in allRules: [PreferenceRule],
        generatedAt: Date
    ) -> [PreferenceRule] {
        guard rule.type == .style else {
            return []
        }

        return allRules
            .filter {
                $0.ruleId != rule.ruleId
                    && $0.type == .style
                    && Self.scopeFingerprint(for: $0.scope) == Self.scopeFingerprint(for: rule.scope)
                    && $0.statement != rule.statement
            }
            .filter { sibling in
                guard let updatedDate = Self.parseDate(sibling.updatedAt) else {
                    return false
                }
                return Self.daysBetween(updatedDate, and: generatedAt) <= configuration.styleChangeWindowDays
            }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.ruleId > rhs.ruleId
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    private func staleUsageFinding(
        rule: PreferenceRule,
        stats: PreferenceDriftRuleUsageStats,
        generatedAt: String,
        recentDecisions: [PolicyAssemblyDecision]
    ) -> PreferenceDriftFinding? {
        guard let daysSinceLastRelevantActivity = stats.daysSinceLastRelevantActivity,
              daysSinceLastRelevantActivity >= configuration.staleWindowDays else {
            return nil
        }

        let neverConsidered = stats.lastConsideredAt == nil
        let summary: String
        let rationale: String
        if neverConsidered {
            summary = "规则 \(rule.ruleId) 自最近一次更新后已 \(daysSinceLastRelevantActivity) 天未进入偏好装配。"
            rationale = "当前有装配日志可用，但这条规则在最近的策略装配中从未被考虑，可能已脱离老师当前工作流。"
        } else {
            summary = "规则 \(rule.ruleId) 已 \(daysSinceLastRelevantActivity) 天未再次命中。"
            rationale = "规则上次进入偏好装配已超过 \(configuration.staleWindowDays) 天，可能已过时或不再适用。"
        }

        return PreferenceDriftFinding(
            findingId: "drift-\(PreferenceDriftFindingKind.longTimeNoHit.rawValue)-\(rule.ruleId)",
            ruleId: rule.ruleId,
            kind: .longTimeNoHit,
            severity: severityForStaleFinding(rule.riskLevel),
            summary: summary,
            rationale: rationale,
            metrics: PreferenceDriftFindingMetrics(
                daysSinceLastRelevantActivity: daysSinceLastRelevantActivity
            ),
            evidence: staleFindingEvidence(
                rule: rule,
                recentDecisions: recentDecisions
            ),
            triggeredAt: generatedAt
        )
    }

    private func overrideRateFinding(
        rule: PreferenceRule,
        stats: PreferenceDriftRuleUsageStats,
        generatedAt: String,
        recentDecisions: [PolicyAssemblyDecision]
    ) -> PreferenceDriftFinding? {
        guard stats.recentRelevantDecisionCount >= configuration.minimumRelevantDecisionCount,
              let recentOverrideRate = stats.recentOverrideRate,
              recentOverrideRate > configuration.overrideRateThreshold else {
            return nil
        }

        return PreferenceDriftFinding(
            findingId: "drift-\(PreferenceDriftFindingKind.overrideRateElevated.rawValue)-\(rule.ruleId)",
            ruleId: rule.ruleId,
            kind: .overrideRateElevated,
            severity: severityForOverrideFinding(rule.riskLevel),
            summary: "规则 \(rule.ruleId) 在最近 \(stats.recentRelevantDecisionCount) 次相关装配里有 \(stats.recentOverrideCount) 次被覆盖。",
            rationale: "最近 override 比例为 \(Self.percentString(from: recentOverrideRate))，已超过阈值 \(Self.percentString(from: configuration.overrideRateThreshold))，说明老师当前行为更常走向别的策略。", 
            metrics: PreferenceDriftFindingMetrics(
                recentRelevantDecisionCount: stats.recentRelevantDecisionCount,
                recentOverrideCount: stats.recentOverrideCount,
                recentOverrideRate: recentOverrideRate
            ),
            evidence: overrideFindingEvidence(ruleId: rule.ruleId, recentDecisions: recentDecisions),
            triggeredAt: generatedAt
        )
    }

    private func repeatedTeacherRejectionFinding(
        rule: PreferenceRule,
        stats: PreferenceDriftRuleUsageStats,
        generatedAt: String,
        rejectionEntries: [PreferenceAuditLogEntry]
    ) -> PreferenceDriftFinding? {
        guard stats.explicitTeacherRejectionCount >= configuration.explicitTeacherRejectionThreshold else {
            return nil
        }

        return PreferenceDriftFinding(
            findingId: "drift-\(PreferenceDriftFindingKind.teacherRejectedRepeatedly.rawValue)-\(rule.ruleId)",
            ruleId: rule.ruleId,
            kind: .teacherRejectedRepeatedly,
            severity: rule.riskLevel == .critical ? .critical : .high,
            summary: "规则 \(rule.ruleId) 已被老师明确驳回 \(stats.explicitTeacherRejectionCount) 次。",
            rationale: "最近连续出现老师显式驳回或带 rejection 语义的审计事件，说明这条偏好已经明显偏离当前偏好。", 
            metrics: PreferenceDriftFindingMetrics(
                explicitTeacherRejectionCount: stats.explicitTeacherRejectionCount
            ),
            evidence: rejectionFindingEvidence(rejectionEntries),
            triggeredAt: generatedAt
        )
    }

    private func styleChangeFinding(
        rule: PreferenceRule,
        stats: PreferenceDriftRuleUsageStats,
        generatedAt: String,
        rejectionEntries: [PreferenceAuditLogEntry],
        siblingRules: [PreferenceRule]
    ) -> PreferenceDriftFinding? {
        guard rule.type == .style else {
            return nil
        }
        guard !siblingRules.isEmpty || !rejectionEntries.isEmpty else {
            return nil
        }

        let rationale: String
        if !siblingRules.isEmpty && !rejectionEntries.isEmpty {
            rationale = "同一作用域近期出现了新的风格规则，同时当前规则也收到老师驳回信号，说明风格偏好仍在变化。"
        } else if !siblingRules.isEmpty {
            rationale = "同一作用域在最近 \(configuration.styleChangeWindowDays) 天内出现了不同 statement 的风格规则，说明老师风格偏好正在调整。"
        } else {
            rationale = "当前风格规则最近收到了老师显式驳回信号，建议复核是否应替换为新的风格偏好。"
        }

        return PreferenceDriftFinding(
            findingId: "drift-\(PreferenceDriftFindingKind.stylePreferenceChanged.rawValue)-\(rule.ruleId)",
            ruleId: rule.ruleId,
            kind: .stylePreferenceChanged,
            severity: .warning,
            summary: "规则 \(rule.ruleId) 所在作用域近期出现风格偏好变化。",
            rationale: rationale,
            metrics: PreferenceDriftFindingMetrics(
                explicitTeacherRejectionCount: stats.explicitTeacherRejectionCount,
                recentStyleSiblingCount: siblingRules.count
            ),
            evidence: styleFindingEvidence(
                rejectionEntries: rejectionEntries,
                siblingRules: siblingRules
            ),
            triggeredAt: generatedAt
        )
    }

    private func highRiskMismatchFinding(
        rule: PreferenceRule,
        stats: PreferenceDriftRuleUsageStats,
        generatedAt: String,
        recentDecisions: [PolicyAssemblyDecision],
        rejectionEntries: [PreferenceAuditLogEntry]
    ) -> PreferenceDriftFinding? {
        guard rule.riskLevel == .high || rule.riskLevel == .critical else {
            return nil
        }

        let overrideTriggered = stats.recentRelevantDecisionCount >= configuration.minimumRelevantDecisionCount
            && (stats.recentOverrideRate ?? 0) > configuration.overrideRateThreshold
        let rejectionTriggered = stats.explicitTeacherRejectionCount > 0
        guard overrideTriggered || rejectionTriggered else {
            return nil
        }

        let rationale: String
        if overrideTriggered && rejectionTriggered {
            rationale = "这是一条高风险规则，但它最近既频繁被覆盖，也出现了老师显式驳回，说明当前实际行为和安全偏好已经不一致。"
        } else if overrideTriggered {
            rationale = "这是一条高风险规则，但最近相关装配中超过一半都没有真正采用它，说明当前行为正在偏离原先的高风险约束。"
        } else {
            rationale = "这是一条高风险规则，但老师已经对它给出显式驳回信号，建议尽快复核，避免安全偏好继续失真。"
        }

        let combinedEvidence = (
            overrideFindingEvidence(ruleId: rule.ruleId, recentDecisions: recentDecisions)
            + rejectionFindingEvidence(rejectionEntries)
        ).prefix(4)

        return PreferenceDriftFinding(
            findingId: "drift-\(PreferenceDriftFindingKind.highRiskBehaviorMismatch.rawValue)-\(rule.ruleId)",
            ruleId: rule.ruleId,
            kind: .highRiskBehaviorMismatch,
            severity: rule.riskLevel == .critical ? .critical : .high,
            summary: "高风险规则 \(rule.ruleId) 与最近行为表现不一致。",
            rationale: rationale,
            metrics: PreferenceDriftFindingMetrics(
                recentRelevantDecisionCount: stats.recentRelevantDecisionCount,
                recentOverrideCount: stats.recentOverrideCount,
                recentOverrideRate: stats.recentOverrideRate,
                explicitTeacherRejectionCount: stats.explicitTeacherRejectionCount
            ),
            evidence: Array(combinedEvidence),
            triggeredAt: generatedAt
        )
    }

    private func staleFindingEvidence(
        rule: PreferenceRule,
        recentDecisions: [PolicyAssemblyDecision]
    ) -> [PreferenceDriftEvidenceReference] {
        var evidence = [
            PreferenceDriftEvidenceReference(
                kind: .rule,
                referenceId: rule.ruleId,
                timestamp: rule.updatedAt,
                summary: "规则最近一次更新时间为 \(rule.updatedAt)。"
            )
        ]
        evidence.append(contentsOf: recentDecisions.prefix(2).map { decision in
            PreferenceDriftEvidenceReference(
                kind: .policyAssemblyDecision,
                referenceId: decision.decisionId,
                timestamp: decision.timestamp,
                summary: "最近的偏好装配仍在运行，但未再次考虑规则 \(rule.ruleId)。"
            )
        })
        return evidence
    }

    private func overrideFindingEvidence(
        ruleId: String,
        recentDecisions: [PolicyAssemblyDecision]
    ) -> [PreferenceDriftEvidenceReference] {
        recentDecisions
            .filter { $0.suppressedRuleIds.contains(ruleId) || $0.appliedRuleIds.contains(ruleId) }
            .prefix(3)
            .map { decision in
                let disposition = decision.suppressedRuleIds.contains(ruleId) ? "suppressed" : "applied"
                return PreferenceDriftEvidenceReference(
                    kind: .policyAssemblyDecision,
                    referenceId: decision.decisionId,
                    timestamp: decision.timestamp,
                    summary: "规则 \(ruleId) 在该次装配中被 \(disposition)。"
                )
            }
    }

    private func rejectionFindingEvidence(
        _ rejectionEntries: [PreferenceAuditLogEntry]
    ) -> [PreferenceDriftEvidenceReference] {
        rejectionEntries.prefix(3).map { entry in
            PreferenceDriftEvidenceReference(
                kind: .auditEntry,
                referenceId: entry.auditId,
                timestamp: entry.timestamp,
                summary: entry.note
                    ?? entry.source.summary
                    ?? "老师对该规则给出了显式驳回信号。"
            )
        }
    }

    private func styleFindingEvidence(
        rejectionEntries: [PreferenceAuditLogEntry],
        siblingRules: [PreferenceRule]
    ) -> [PreferenceDriftEvidenceReference] {
        let rejectionEvidence = rejectionFindingEvidence(rejectionEntries)
        let siblingEvidence = siblingRules.prefix(2).map { rule in
            PreferenceDriftEvidenceReference(
                kind: .rule,
                referenceId: rule.ruleId,
                timestamp: rule.updatedAt,
                summary: "同一作用域存在另一条风格规则：\(rule.statement)"
            )
        }
        return Array((rejectionEvidence + siblingEvidence).prefix(4))
    }

    private func severityForStaleFinding(
        _ riskLevel: InteractionTurnRiskLevel
    ) -> PreferenceDriftFindingSeverity {
        switch riskLevel {
        case .critical:
            return .critical
        case .high:
            return .high
        case .medium, .low:
            return .warning
        }
    }

    private func severityForOverrideFinding(
        _ riskLevel: InteractionTurnRiskLevel
    ) -> PreferenceDriftFindingSeverity {
        switch riskLevel {
        case .critical:
            return .critical
        case .high:
            return .high
        case .medium, .low:
            return .warning
        }
    }

    private func isExplicitTeacherRejection(
        _ entry: PreferenceAuditLogEntry
    ) -> Bool {
        guard isTeacherDriven(entry) else {
            return false
        }

        switch entry.action {
        case .ruleRevoked, .ruleSuperseded, .ruleRolledBack:
            return true
        default:
            break
        }

        let text = [
            entry.note,
            entry.source.summary
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return Self.rejectionKeywords.contains { keyword in
            text.contains(keyword)
        }
    }

    private func isTeacherDriven(
        _ entry: PreferenceAuditLogEntry
    ) -> Bool {
        if entry.source.kind == .teacherAction {
            return true
        }

        let normalizedActor = entry.actor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedActor.contains("teacher") || normalizedActor.contains("老师")
    }

    private static let rejectionKeywords: [String] = [
        "reject",
        "rejected",
        "override",
        "overridden",
        "dismiss",
        "dismissed",
        "驳回",
        "否决",
        "不再适用",
        "不再使用",
        "废弃",
        "太危险",
        "顺序不对",
        "风格不对"
    ]

    private static func scopeFingerprint(
        for scope: PreferenceSignalScopeReference
    ) -> String {
        [
            scope.level.rawValue,
            scope.appBundleId ?? "",
            scope.appName ?? "",
            scope.taskFamily ?? "",
            scope.skillFamily ?? "",
            scope.windowPattern ?? ""
        ].joined(separator: "|")
    }

    fileprivate static func parseDate(_ value: String) -> Date? {
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    fileprivate static func sortDecisionsDescending(
        lhs: PolicyAssemblyDecision,
        rhs: PolicyAssemblyDecision
    ) -> Bool {
        let lhsDate = parseDate(lhs.timestamp) ?? .distantPast
        let rhsDate = parseDate(rhs.timestamp) ?? .distantPast
        if lhsDate == rhsDate {
            return lhs.decisionId > rhs.decisionId
        }
        return lhsDate > rhsDate
    }

    fileprivate static func daysBetween(
        _ earlier: Date,
        and later: Date
    ) -> Int {
        max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: earlier, to: later).day ?? 0)
    }

    fileprivate static func round(_ value: Double?) -> Double? {
        guard let value else {
            return nil
        }
        return (value * 100).rounded() / 100
    }

    private static func percentString(from value: Double) -> String {
        let percentage = (value * 100).rounded()
        return "\(Int(percentage))%"
    }
}
